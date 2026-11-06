import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../engine/generator/generator_version.dart';
import '../../../engine/generator/level_generator.dart';
import '../../../engine/generator/level_service.dart';
import '../../../engine/generator/generated_level.dart';
import '../../../engine/models/move_model.dart';
import '../../../engine/rules/pour_rules.dart';
import '../../../engine/progression/star_rating.dart';
import '../../../engine/solver/hint.dart';
import '../../../engine/solver/solver_config.dart';
import '../../../engine/solver/solver_service.dart';
import '../../feedback/feedback_service.dart';
import '../../progress/application/providers.dart';
import '../../progress/domain/player_progress.dart';
import '../../settings/application/settings_providers.dart';
import '../../journey/domain/journey.dart';
import '../rendering/bottle_style.dart';
import '../rendering/liquid_palette.dart';
import 'board_controller.dart';
import 'playable_level.dart';

/// Loads a level (off the UI thread in the app, synchronously in tests).
typedef LevelLoader = Future<GeneratedLevel> Function(int level);

/// Debuggers (VS Code, Android Studio) tend to stop whenever the app spawns
/// an isolate, which looks like a pause "for no reason" every time Play is
/// pressed. So DEBUG builds generate the level in the main isolate (levels
/// take milliseconds, rarely a few hundred in debug mode). RELEASE builds
/// always generate off the UI thread. To exercise the real isolate path while
/// debugging, run with `--dart-define=PRISM_POUR_ISOLATES=true`.
const bool _forceIsolates = bool.fromEnvironment('PRISM_POUR_ISOLATES');

final levelLoaderProvider = Provider<LevelLoader>((ref) {
  if (kDebugMode && !_forceIsolates) {
    return (level) async => const LevelGenerator().generate(level);
  }
  return (level) => const LevelService().generate(level);
});

/// The in-game assist buttons.
enum GameAction { undo, hint, restart, booster }

enum SessionStatus { idle, loading, playing, completed, failed }

/// What the player achieved on a finished level.
final class LevelResult {
  const LevelResult({
    required this.level,
    required this.difficultyIndex,
    required this.moves,
    required this.par,
    required this.stars,
    required this.thresholds,
    required this.previousBest,
    required this.isNewBest,
    required this.starsImproved,
    this.hintsUsed = 0,
    this.assisted = false,
    this.newStyleIds = const [],
    this.newChapter,
  });

  final int level;
  final int difficultyIndex;
  final int moves;
  final int par;
  final int stars;
  final StarThresholds thresholds;
  final LevelRecord? previousBest;

  /// Fewer moves than ever before on this level.
  final bool isNewBest;

  /// More stars than ever before on this level.
  final bool starsImproved;

  /// Hints shown during this attempt.
  final int hintsUsed;

  /// The extra-bottle booster was used, so stars were capped at
  /// [GameSession.assistedStarCap] and the best-move record is not lowered
  /// below par.
  final bool assisted;

  /// Bottle designs this very completion unlocked.
  final List<String> newStyleIds;

  /// Set when this completion carried the player into a new chapter of the
  /// Alchemy Journey.
  final JourneyPosition? newChapter;

  bool get hasReward => newStyleIds.isNotEmpty || newChapter != null;
}

/// One play session: the level on screen, its board, hints and the result.
///
/// This is the bridge between the UI and the real game. Everything shown is
/// read from the [BoardController] (which owns the engine), and everything
/// remembered is written through the progress provider:
///  * after every committed move the game is saved as the list of moves, so
///    it can be restored exactly by replaying them through the engine;
///  * when the board is solved (and its last pour has finished animating)
///    stars are computed by [StarRating], progress is recorded and the next
///    level unlocks.
class GameSession extends ChangeNotifier {
  GameSession(this._ref);

  final Ref _ref;
  final Map<int, GeneratedLevel> _cache = {};
  int _hintsThisAttempt = 0;

  SessionStatus status = SessionStatus.idle;
  PlayableLevel? level;
  BoardController? board;
  LiquidPalette? palette;
  LevelResult? result;

  /// Changes every time a new board is created (use as a widget key).
  int runId = 0;

  /// Bottles currently highlighted as a hint.
  Set<int> hintBottles = const {};
  bool hintLoading = false;

  /// A short message for the player (hint problems, etc.).
  String? notice;
  int noticeId = 0;

  /// Search limits for hints. A hint that cannot be found within them is
  /// reported honestly instead of guessed. (Settable so tests can force the
  /// limit.)
  SolverConfig hintConfig = const SolverConfig(maxNodes: 150000);

  HintController? _hints;
  int _loadToken = 0;
  int _movesSignature = 0;
  bool _disposed = false;
  bool _wasPouring = false;

  bool get isPlaying => status == SessionStatus.playing;
  int get moves => board?.engine.moveCount ?? 0;
  int get par => level?.par ?? 0;
  bool get isPaused => board?.isPaused ?? false;

  /// Stars an attempt that used the extra bottle can earn at most.
  static const int assistedStarCap = 1;

  /// Undo needs a move to take back, a running (not paused) game.
  bool get canUndo =>
      isPlaying && !isPaused && (board?.engine.canUndo ?? false);

  /// The booster is offered only when the player has switched it on.
  bool get boosterEnabled => _ref.read(appSettingsProvider).extraBottleBooster;
  bool get boosted => board?.boosted ?? false;
  bool get canUseBooster =>
      boosterEnabled &&
      isPlaying &&
      !isPaused &&
      (board?.canAddExtraBottle ?? false);

  /// Why [action] cannot be used right now, or null when it can.
  String? whyUnavailable(GameAction action) {
    final b = board;
    if (b == null || !isPlaying) return 'The game is not running.';
    if (isPaused) return 'The game is paused.';
    switch (action) {
      case GameAction.undo:
        return b.engine.canUndo ? null : 'Nothing to undo yet.';
      case GameAction.hint:
        if (hintLoading) return 'Looking for a hint…';
        return b.isPouring ? 'Wait for the pour to finish.' : null;
      case GameAction.restart:
        return null;
      case GameAction.booster:
        if (!boosterEnabled) return 'The extra bottle is switched off.';
        if (b.boosted) return 'The extra bottle is already in play.';
        return b.canAddExtraBottle
            ? null
            : "This board can't take another bottle.";
    }
  }

  PlayerProgress get _progress => _ref.read(progressProvider);
  ProgressNotifier get _progressWriter => _ref.read(progressProvider.notifier);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Begin [levelNumber]. With [resume], an unfinished game of that level is
  /// restored from its saved moves; otherwise (or if the save is stale or
  /// damaged) the level starts fresh.
  Future<void> startLevel(int levelNumber, {bool resume = true}) async {
    final token = ++_loadToken;
    _detach();
    status = SessionStatus.loading;
    level = null;
    board = null;
    palette = null;
    result = null;
    _clearHint();
    notice = null;
    _notify();

    _hintsThisAttempt = 0;
    BoardController controller;
    PlayableLevel? lv;
    BoardController? restored;
    String? restoreNote;

    final saved = resume ? _progress.saved[levelNumber] : null;
    try {
      if (saved != null) {
        final r = await _restore(saved, levelNumber);
        if (token != _loadToken || _disposed) return;
        if (r != null) {
          lv = r.level;
          restored = r.controller;
          restoreNote = r.note;
        } else {
          // Unusable (damaged, or a legacy save the current generator can no
          // longer reproduce exactly): start fresh rather than show a
          // different puzzle under the old moves.
          await _progressWriter.clearSavedGame(levelNumber);
          restoreNote =
              'Your saved game for level $levelNumber could not be restored, so it was restarted.';
        }
      } else if (!resume) {
        await _progressWriter.clearSavedGame(levelNumber);
      }
      if (lv == null) {
        final generated =
            _cache[levelNumber] ??
            await _ref.read(levelLoaderProvider)(levelNumber);
        if (token != _loadToken || _disposed) return;
        _cache[levelNumber] = generated;
        if (_cache.length > 6) _cache.remove(_cache.keys.first);
        lv = PlayableLevel.fromGenerated(generated);
      }
    } catch (error, stack) {
      // Never swallow silently: the player sees the failed state, the
      // developer sees why.
      debugPrint('Level $levelNumber could not be prepared: $error\n$stack');
      if (token != _loadToken) return;
      status = SessionStatus.failed;
      _notify();
      return;
    }
    if (token != _loadToken || _disposed) {
      restored?.dispose();
      return;
    }
    controller = restored ?? BoardController(lv.puzzle);

    level = lv;
    board = controller;
    palette = LiquidPalette.forColorIds(
      lv.puzzle.colorCounts.keys,
      seed: lv.seed,
    );
    _hints = HintController(config: hintConfig);
    runId++;
    status = SessionStatus.playing;
    _movesSignature = _signature(controller);
    controller.addListener(_onBoard);
    unawaited(_progressWriter.setLastPlayed(levelNumber));
    if (restoreNote != null) _setNotice(restoreNote);
    if (restored != null &&
        saved != null &&
        controller.committedMoves.length < saved.moves.length) {
      _persist(controller); // store the rewound game so it stays consistent
    } else if (restored == null && saved == null && !resume) {
      // fresh start: nothing to persist until the first move
    }
    _notify();
    _onBoard(); // a restored game may already be solved
  }

  /// Rebuilds a saved game.
  ///
  /// With a stored snapshot the level is built from it, WITHOUT calling the
  /// generator, so a generator change can never alter a puzzle in progress.
  /// A pre-snapshot save can only be rebuilt by regenerating, which is allowed
  /// only when the generator version is unchanged (otherwise the level would
  /// differ from what the moves were played on).
  ///
  /// The moves are replayed through the real engine. If one is no longer
  /// legal (damaged data) the game is restored up to the last good move.
  /// Returns null when nothing usable can be rebuilt.
  Future<({PlayableLevel level, BoardController controller, String? note})?>
  _restore(SavedGame saved, int levelNumber) async {
    PlayableLevel? lv = PlayableLevel.fromSaved(saved);
    if (lv != null) {
      final p = lv.puzzle;
      if (!PourRules.isValid(p) || p.bottles.every((b) => b.isEmpty)) lv = null;
    }
    if (lv == null) {
      if (saved.generatorVersion != kGeneratorVersion) return null;
      final GeneratedLevel generated;
      try {
        generated =
            _cache[levelNumber] ??
            await _ref.read(levelLoaderProvider)(levelNumber);
      } catch (_) {
        return null;
      }
      if (generated.variant != saved.variant ||
          generated.generatorVersion != saved.generatorVersion) {
        return null;
      }
      _cache[levelNumber] = generated;
      lv = PlayableLevel.fromGenerated(generated);
    }

    final controller = BoardController(lv.puzzle, boosted: saved.boosted);
    var applied = 0;
    for (final m in saved.moves) {
      if (!controller.engine.applyMove(m).isSuccess) break;
      applied++;
    }
    String? note;
    if (applied < saved.moves.length) {
      note = 'Part of your saved game could not be restored; it was rewound to the last valid move.';
    } else if (saved.currentPuzzle != null &&
        controller.committedState != saved.currentPuzzle) {
      // The moves are the source of truth; a differing stored board only
      // means that copy was written inconsistently.
      debugPrint(
        'Saved board for level $levelNumber differed from its replayed moves; using the moves.',
      );
    }
    return (level: lv, controller: controller, note: note);
  }

  void _detach() {
    if (_wasPouring) {
      _wasPouring = false;
      if (!_disposed) _ref.read(feedbackProvider).pourEnded();
    }
    board?.removeListener(_onBoard);
    board?.dispose();
    _hints?.dispose();
    _hints = null;
  }

  void _onBoard() {
    final b = board;
    if (b == null) return;
    // The liquid sound lasts exactly as long as the pour is shown.
    final pouring = b.isPouring;
    if (_wasPouring && !pouring) _ref.read(feedbackProvider).pourEnded();
    _wasPouring = pouring;
    if (!isPlaying) return;
    final sig = _signature(b);
    if (sig != _movesSignature) {
      _movesSignature = sig;
      _clearHint();
      _hints?.invalidate();
      _persist(b);
    }
    if (b.levelCompleteVisible) _complete(b);
    _notify();
  }

  /// Changes whenever something worth saving changes: the moves or the
  /// booster.
  static int _signature(BoardController b) =>
      Object.hash(Object.hashAll(b.committedMoves), b.boosted);

  void _persist(BoardController b) {
    final lv = level;
    if (lv == null) return;
    final moves = b.committedMoves;
    if (moves.isEmpty && !b.boosted) {
      unawaited(_progressWriter.clearSavedGame(lv.levelNumber));
    } else {
      unawaited(
        _progressWriter.saveGame(
          lv.toSaved(moves, b.committedState, boosted: b.boosted),
        ),
      );
    }
  }

  void _complete(BoardController b) {
    final lv = level!;
    status = SessionStatus.completed; // synchronous: only ever once
    final moves = b.engine.moveCount;
    final par = lv.par;
    final assisted = b.boosted;
    final earned = StarRating.starsFor(moves: moves, par: par);
    final stars = assisted && earned > assistedStarCap
        ? assistedStarCap
        : earned;
    // An attempt with an extra bottle must not set a "best moves" that a
    // standard attempt can never reach: no standard solution is shorter than
    // par, so the record is never below it.
    final recordedMoves = assisted && moves < par ? par : moves;
    final previous = _progress.recordOf(lv.levelNumber);
    // What this completion earns, worked out from the progress before and
    // after it (the same calculation the saved progress will make).
    final before = _progress;
    final after = before.withCompletion(
      level: lv.levelNumber,
      stars: stars,
      moves: recordedMoves,
    );
    final chapterNow = Journey.at(before.currentLevel - 1);
    final chapterNext = Journey.at(after.currentLevel - 1);
    result = LevelResult(
      level: lv.levelNumber,
      difficultyIndex: lv.difficulty.index,
      moves: moves,
      par: par,
      stars: stars,
      thresholds: StarRating.thresholds(par),
      previousBest: previous,
      isNewBest: previous == null || recordedMoves < previous.bestMoves,
      starsImproved: previous == null || stars > previous.stars,
      hintsUsed: _hintsThisAttempt,
      assisted: assisted,
      newStyleIds: [
        for (final st in BottleStyles.all)
          if (!before.isStyleUnlocked(st.id) && after.isStyleUnlocked(st.id))
            st.id,
      ],
      newChapter: chapterNext.chapter != chapterNow.chapter
          ? chapterNext
          : null,
    );
    _clearHint();
    unawaited(
      _progressWriter.recordCompletion(
        level: lv.levelNumber,
        stars: stars,
        moves: recordedMoves,
      ),
    );
    _ref.read(feedbackProvider).complete();
  }

  // ---- player actions ----

  /// Feedback and hint housekeeping for a tap on the board.
  void onTap(TapOutcome outcome) {
    final f = _ref.read(feedbackProvider);
    switch (outcome.kind) {
      case TapKind.selected:
      case TapKind.deselected:
        f.select();
      case TapKind.reselected:
        // The tapped bottle became the source, but the pour the player
        // wanted was not possible: say so softly (never silently).
        outcome.failure == null ? f.select() : f.reject();
      case TapKind.pourStarted:
        f.pour();
      case TapKind.rejected:
        f.reject();
      case TapKind.busy:
      case TapKind.ignored:
        return;
    }
    if (hintBottles.isNotEmpty) {
      _clearHint();
      _notify();
    }
  }

  /// Take back the last move (repeatable down to the starting position).
  void undo() {
    final b = board;
    if (b == null || !canUndo) return;
    // The liquid runs back: the same glass-and-pour sound as a pour.
    _ref.read(feedbackProvider).pour();
    b.undo();
  }

  /// Tap on an action that is currently unavailable: say why, with a buzz,
  /// instead of silently doing nothing.
  void explainUnavailable(GameAction action) {
    final why = whyUnavailable(action);
    if (why == null) return;
    _ref.read(feedbackProvider).reject();
    _setNotice(why);
    _notify();
  }

  /// Add the optional extra empty bottle (only if switched on in settings).
  /// The attempt then scores at most [assistedStarCap] star.
  bool useBooster() {
    final b = board;
    if (b == null || !canUseBooster) return false;
    if (!b.addExtraBottle()) return false;
    _ref.read(feedbackProvider).button();
    _clearHint();
    _hints?.invalidate();
    return true; // the board listener saves it and refreshes the screen
  }

  /// Start the same level over. Hints, stars and moves of this attempt are
  /// forgotten (the saved game is cleared by the move-change listener).
  void restart() {
    final b = board;
    if (b == null || !isPlaying) return;
    _ref.read(feedbackProvider).button();
    b.reset(); // paused or not: the level is dealt again as originally
    _hintsThisAttempt = 0;
    _clearHint();
    _notify();
  }

  void pause() => board?.pause();
  void resume() => board?.resume();

  /// Ask the solver for the next move from the CURRENT position.
  Future<void> requestHint() async {
    final b = board;
    final hints = _hints;
    if (b == null || hints == null || !isPlaying || hintLoading) return;
    if (b.isPouring || b.isPaused) return;
    if (b.engine.isLevelCompleted()) return;
    final run = runId;
    hintLoading = true;
    _clearHint();
    _notify();
    final lv = level;
    if (lv != null) {
      unawaited(_progressWriter.recordHint(lv.levelNumber, requested: 1));
    }
    final r = await hints.requestHint(b.committedState);
    if (_disposed || run != runId || board != b) return;
    hintLoading = false;
    switch (r.status) {
      case HintStatus.available:
        final m = r.hint!.move;
        hintBottles = {m.source, m.destination};
        _hintsThisAttempt++;
        if (lv != null) {
          unawaited(_progressWriter.recordHint(lv.levelNumber, shown: 1));
        }
        _ref.read(feedbackProvider).hint();
      case HintStatus.unsolvable:
        _setNotice(
          "This position can't be solved. Undo a few moves or restart.",
        );
      case HintStatus.budgetExceeded:
        _setNotice('No hint found in time. Try a different move.');
      case HintStatus.alreadySolved:
        break;
      case HintStatus.stale:
        break;
      case HintStatus.invalidState:
        _setNotice('No hint is available for this position.');
    }
    _notify();
  }

  void _clearHint() {
    hintBottles = const {};
  }

  void _setNotice(String m) {
    notice = m;
    noticeId++;
  }

  void dismissNotice(int id) {
    if (id != noticeId || notice == null) return;
    notice = null;
    _notify();
  }

  /// Show a message from the UI (e.g. "complete level 4 first").
  void showNotice(String m) {
    _setNotice(m);
    _notify();
  }

  List<MoveModel> get committedMoves => board?.committedMoves ?? const [];

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    _detach();
    super.dispose();
  }
}

final gameSessionProvider = Provider<GameSession>((ref) {
  final session = GameSession(ref);
  ref.onDispose(session.dispose);
  return session;
});
