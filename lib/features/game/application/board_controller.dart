import 'package:flutter/foundation.dart';

import '../../../engine/game_engine.dart';
import '../../../engine/models/move_model.dart';
import '../../../engine/models/move_result.dart';
import '../../../engine/models/puzzle_state.dart';
import '../../../engine/rules/extra_bottle.dart';

/// A pour that is currently being shown. The move is ALREADY committed to the
/// engine; this only tells the view what to animate.
final class ActivePour {
  const ActivePour(this.token, this.result, {this.isUndo = false});

  /// Unique per pour. Finish/skip calls must present it, so a late callback
  /// from an old animation can never affect a newer one.
  final int token;
  final MoveResult result;

  /// True when this replays an UNDO (the liquid flows back). [result] is then
  /// the reversed pour, and the board it describes is already committed.
  final bool isUndo;
}

enum TapKind {
  /// A bottle was picked up.
  selected,

  /// The selected bottle was tapped again and put down.
  deselected,

  /// The tap was not a legal pour but the tapped bottle became the source.
  reselected,

  /// A legal pour was committed and its animation should start.
  pourStarted,

  /// An illegal pour (see [TapOutcome.failure]); selection unchanged.
  rejected,

  /// Input is locked (a pour is animating, or the game is paused).
  busy,

  /// Nothing to do (empty bottle, bad index).
  ignored,
}

final class TapOutcome {
  const TapOutcome(this.kind, {this.result, this.failure});

  final TapKind kind;
  final MoveResult? result;
  final MoveFailure? failure;

  @override
  String toString() =>
      'TapOutcome($kind${failure != null ? ', $failure' : ''})';
}

enum InterruptReason { background, navigation, reset, undo, pause, other }

/// The authority on what the player is doing.
///
/// Design rules that keep gameplay correct regardless of animation:
///  * A move is committed to the [engine] the instant it is accepted. The
///    animation is only a replay of that [MoveResult]; it never changes game
///    state, and the game state never waits for it.
///  * Therefore interrupting an animation (app backgrounded, screen closed,
///    reset, undo, pause) simply drops the replay. There is nothing to roll
///    back or re-apply, and any saved state is already final.
///  * While a pour is showing, all input is ignored (no conflicting or
///    duplicate moves).
///  * Completion callbacks carry a token, so stale ones are ignored.
class BoardController extends ChangeNotifier {
  BoardController(PuzzleState initial, {bool boosted = false})
    : _base = initial,
      _boosted = boosted && ExtraBottle.canAdd(initial),
      _engine = GameEngine(
        boosted && ExtraBottle.canAdd(initial)
            ? ExtraBottle.add(initial)
            : initial,
      );

  /// The level as it was dealt, WITHOUT the booster. Restart returns to this.
  PuzzleState _base;
  bool _boosted;
  GameEngine _engine;
  int? _selected;
  ActivePour? _active;
  bool _paused = false;
  bool _disposed = false;
  int _tokens = 0;
  InterruptReason? _lastInterrupt;

  /// The committed game. Read-only for the view; all changes go through the
  /// methods below.
  GameEngine get engine => _engine;

  /// What a save file should contain: always the final, committed state.
  PuzzleState get committedState => _engine.state;
  List<MoveModel> get committedMoves => [
    for (final r in _engine.history) r.move,
  ];

  /// The level as dealt (no extra bottle).
  PuzzleState get originalState => _base;

  /// Whether the extra-bottle booster has been used in this attempt.
  bool get boosted => _boosted;

  /// Whether the booster could be used right now.
  bool get canAddExtraBottle => !_boosted && ExtraBottle.canAdd(_base);

  int? get selectedIndex => _selected;
  ActivePour? get activePour => _active;
  bool get isPouring => _active != null;
  bool get isPaused => _paused;
  bool get inputLocked => isPouring || _paused;
  bool get isDisposed => _disposed;
  InterruptReason? get lastInterruption => _lastInterrupt;

  /// True only once the winning pour has finished animating.
  bool get levelCompleteVisible => _engine.isLevelCompleted() && !isPouring;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The player tapped bottle [index].
  TapOutcome tapBottle(int index) {
    if (inputLocked) return const TapOutcome(TapKind.busy);
    if (index < 0 || index >= _engine.state.bottleCount) {
      return const TapOutcome(TapKind.ignored);
    }
    final src = _selected;

    if (src == null) {
      if (_engine.state.bottles[index].isEmpty) {
        return const TapOutcome(TapKind.ignored);
      }
      _selected = index;
      _notify();
      return const TapOutcome(TapKind.selected);
    }

    if (src == index) {
      _selected = null;
      _notify();
      return const TapOutcome(TapKind.deselected);
    }

    final result = _engine.applyMove(MoveModel(src, index));
    if (result.isSuccess) {
      _selected = null;
      _active = ActivePour(++_tokens, result);
      _notify();
      return TapOutcome(TapKind.pourStarted, result: result);
    }

    // Not a legal pour: a non-empty bottle simply becomes the new source.
    if (!_engine.state.bottles[index].isEmpty) {
      _selected = index;
      _notify();
      return TapOutcome(TapKind.reselected, failure: result.failure);
    }
    return TapOutcome(TapKind.rejected, failure: result.failure);
  }

  /// The view finished animating pour [token]. Stale tokens are ignored.
  bool finishPour(int token) {
    if (_active?.token != token) return false;
    _active = null;
    _notify();
    return true;
  }

  /// Drop the running animation, if any (the move stays committed).
  /// Returns whether there was one.
  bool interruptPour([InterruptReason reason = InterruptReason.other]) {
    if (_active == null) return false;
    _active = null;
    _lastInterrupt = reason;
    _notify();
    return true;
  }

  /// Undo the last committed move. Any animation is dropped first, so this
  /// also undoes the pour that was still being shown.
  MoveResult? undo() {
    interruptPour(InterruptReason.undo);
    _selected = null;
    final undone = _engine.undoMove();
    if (undone != null) {
      // The board is already back to the earlier position; this only shows
      // the liquid flowing back. Dropped like any other replay if something
      // interrupts it.
      _active = ActivePour(++_tokens, undone.reversed, isUndo: true);
    }
    _notify();
    return undone;
  }

  /// Use the extra-bottle booster: one empty bottle joins the board.
  ///
  /// The attempt is rebuilt on `initial + empty bottle` and the moves made so
  /// far are replayed on it, so the move count, the undo history and every
  /// bottle index are unchanged (the new bottle is last and starts empty, so
  /// no earlier move can be affected). Returns false, changing nothing, when
  /// the booster was already used or cannot be added.
  bool addExtraBottle() {
    if (!canAddExtraBottle) return false;
    final moves = committedMoves;
    final rebuilt = GameEngine(ExtraBottle.add(_base));
    for (final m in moves) {
      if (!rebuilt.applyMove(m).isSuccess) return false; // cannot happen
    }
    _active = null;
    _selected = null;
    _engine = rebuilt;
    _boosted = true;
    _notify();
    return true;
  }

  /// Restart the level from its initial state.
  void reset() {
    interruptPour(InterruptReason.reset);
    _selected = null;
    // Back to the level exactly as dealt: the booster is not kept.
    _boosted = false;
    _engine = GameEngine(_base);
    _notify();
  }

  /// Replace the whole game (new level).
  void loadLevel(PuzzleState state) {
    _active = null;
    _selected = null;
    _paused = false;
    _base = state;
    _boosted = false;
    _engine = GameEngine(state);
    _notify();
  }

  /// Pause: input is locked and any animation is dropped, because a frozen
  /// half-poured bottle must never be left on screen.
  void pause() {
    if (_paused) return;
    interruptPour(InterruptReason.pause);
    _selected = null;
    _paused = true;
    _notify();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
