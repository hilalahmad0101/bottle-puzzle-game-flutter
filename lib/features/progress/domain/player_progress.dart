import 'package:flutter/foundation.dart';

import '../../../engine/models/move_model.dart';
import '../../../engine/models/puzzle_state.dart';
import '../../settings/domain/app_settings.dart';

/// Best result achieved on one level.
@immutable
final class LevelRecord {
  const LevelRecord({
    required this.stars,
    required this.bestMoves,
    this.completions = 1,
  });

  final int stars;
  final int bestMoves;

  /// How many times the level has been completed. Rewards (stars, unlocks)
  /// are derived from the BEST result only, so repeating a level can never
  /// pay out twice; this is just a statistic.
  final int completions;

  Map<String, Object> toJson() => {
    'stars': stars,
    'bestMoves': bestMoves,
    'completions': completions,
  };

  static LevelRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['stars'], m = j['bestMoves'], c = j['completions'];
    if (s is! int || m is! int || s < 1 || s > 3 || m < 1) return null;
    return LevelRecord(
      stars: s,
      bestMoves: m,
      completions: c is int && c >= 1 ? c : 1,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LevelRecord &&
      other.stars == stars &&
      other.bestMoves == bestMoves &&
      other.completions == completions;

  @override
  int get hashCode => Object.hash(stars, bestMoves, completions);
}

/// Hint usage on one level (all attempts).
@immutable
final class HintStat {
  const HintStat({this.requested = 0, this.shown = 0});

  /// Times the player pressed Hint.
  final int requested;

  /// Times a hint was actually shown (the solver found one).
  final int shown;

  HintStat add({int requested = 0, int shown = 0}) => HintStat(
    requested: this.requested + requested,
    shown: this.shown + shown,
  );

  @override
  bool operator ==(Object other) =>
      other is HintStat && other.requested == requested && other.shown == shown;

  @override
  int get hashCode => Object.hash(requested, shown);
}

/// A game in progress.
///
/// A complete save carries the ORIGINAL puzzle (plus the seed, difficulty and
/// par it was graded with) and the move list. Restoring replays the moves on
/// the stored puzzle and never calls the level generator, so changing the
/// generator can never alter a puzzle the player is part-way through.
///
/// Saves written before that (only level + moves) have a null
/// [originalPuzzle]; they can be restored only by regenerating the level
/// with the SAME generator version.
@immutable
final class SavedGame {
  SavedGame({
    required this.level,
    required this.variant,
    required this.generatorVersion,
    required Iterable<MoveModel> moves,
    this.seed,
    this.originalPuzzle,
    this.currentPuzzle,
    this.difficultyIndex,
    this.par,
    this.fingerprint,
    this.boosted = false,
  }) : moves = List.unmodifiable(moves);

  final int level;
  final int variant;
  final int generatorVersion;

  /// The move history, oldest first. This IS the undo history: replaying it
  /// rebuilds the engine's undo stack.
  final List<MoveModel> moves;

  final int? seed;
  final PuzzleState? originalPuzzle;

  /// The board when it was saved. Stored as an integrity check against the
  /// replayed moves; the moves are the source of truth.
  final PuzzleState? currentPuzzle;
  final int? difficultyIndex;
  final int? par;
  final String? fingerprint;

  /// The extra-bottle booster was used in this attempt. [originalPuzzle] is
  /// still the level as dealt; the extra bottle is added again on restore.
  final bool boosted;

  int get moveCount => moves.length;
  bool get hasSnapshot => originalPuzzle != null;

  SavedGame withMoves(Iterable<MoveModel> newMoves, {PuzzleState? current}) =>
      SavedGame(
        level: level,
        variant: variant,
        generatorVersion: generatorVersion,
        moves: newMoves,
        seed: seed,
        originalPuzzle: originalPuzzle,
        currentPuzzle: current ?? currentPuzzle,
        difficultyIndex: difficultyIndex,
        par: par,
        fingerprint: fingerprint,
        boosted: boosted,
      );

  /// The pre-snapshot JSON form (still read when importing old data).
  Map<String, Object> toJson() => {
    'level': level,
    'variant': variant,
    'generatorVersion': generatorVersion,
    'moves': [
      for (final m in moves) [m.source, m.destination],
    ],
  };

  static SavedGame? fromJson(Object? j) {
    if (j is! Map) return null;
    final level = j['level'],
        variant = j['variant'],
        gv = j['generatorVersion'];
    final raw = j['moves'];
    if (level is! int ||
        level < 1 ||
        variant is! int ||
        gv is! int ||
        raw is! List) {
      return null;
    }
    final moves = <MoveModel>[];
    for (final m in raw) {
      if (m is! List || m.length != 2 || m[0] is! int || m[1] is! int) {
        return null;
      }
      moves.add(MoveModel(m[0] as int, m[1] as int));
    }
    return SavedGame(
      level: level,
      variant: variant,
      generatorVersion: gv,
      moves: moves,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedGame &&
      other.level == level &&
      other.variant == variant &&
      other.generatorVersion == generatorVersion &&
      other.seed == seed &&
      other.difficultyIndex == difficultyIndex &&
      other.par == par &&
      other.fingerprint == fingerprint &&
      other.boosted == boosted &&
      other.originalPuzzle == originalPuzzle &&
      other.currentPuzzle == currentPuzzle &&
      listEquals(other.moves, moves);

  @override
  int get hashCode => Object.hash(
    level,
    variant,
    generatorVersion,
    seed,
    difficultyIndex,
    par,
    fingerprint,
    boosted,
    originalPuzzle,
    currentPuzzle,
    Object.hashAll(moves),
  );
}

/// Everything the game remembers about the player's progress. Immutable.
///
/// Levels unlock in order: level n can be played once every level before it
/// is completed, so the CURRENT level is the first one not completed. Levels
/// are plain 64-bit integers: there is no maximum.
final class PlayerProgress {
  PlayerProgress({
    Map<int, LevelRecord> records = const {},
    Map<int, SavedGame> saved = const {},
    Map<int, HintStat> hints = const {},
    Set<String> unlockedStyles = const {},
    this.lastPlayedLevel,
  }) : records = Map.unmodifiable(records),
       saved = Map.unmodifiable(saved),
       hints = Map.unmodifiable(hints),
       unlockedStyles = Set.unmodifiable(unlockedStyles);

  static final PlayerProgress empty = PlayerProgress();

  /// At most this many unfinished games are remembered.
  static const int maxSavedGames = 10;

  final Map<int, LevelRecord> records;
  final Map<int, SavedGame> saved;
  final Map<int, HintStat> hints;

  /// Bottle styles unlocked so far. Only ever grows: a later change to the
  /// unlock rules cannot take a style away from a player who earned it.
  final Set<String> unlockedStyles;
  final int? lastPlayedLevel;

  late final int currentLevel = _firstIncomplete();
  late final int completedCount = records.length;
  late final int totalStars = records.values.fold(0, (a, r) => a + r.stars);
  late final int totalHintsShown = hints.values.fold(0, (a, h) => a + h.shown);
  late final int totalHintsRequested = hints.values.fold(
    0,
    (a, h) => a + h.requested,
  );

  int _firstIncomplete() {
    var n = 1;
    while (records.containsKey(n)) {
      n++;
    }
    return n;
  }

  bool isCompleted(int level) => records.containsKey(level);
  bool isUnlocked(int level) => level >= 1 && level <= currentLevel;
  LevelRecord? recordOf(int level) => records[level];
  HintStat hintsOf(int level) => hints[level] ?? const HintStat();

  /// Whether a bottle style may be used: free, already unlocked, or earned by
  /// the current star total.
  bool isStyleUnlocked(String styleId) =>
      BottleUnlocks.required(styleId) == 0 ||
      unlockedStyles.contains(styleId) ||
      BottleUnlocks.isUnlocked(styleId, totalStars);

  /// The game "Continue" resumes: the last level played, if unfinished.
  SavedGame? get continueGame {
    final l = lastPlayedLevel;
    return l == null ? null : saved[l];
  }

  int starsIn(int first, int last) {
    var s = 0;
    for (var l = first; l <= last; l++) {
      s += records[l]?.stars ?? 0;
    }
    return s;
  }

  int completedIn(int first, int last) {
    var c = 0;
    for (var l = first; l <= last; l++) {
      if (records.containsKey(l)) c++;
    }
    return c;
  }

  PlayerProgress _copy({
    Map<int, LevelRecord>? records,
    Map<int, SavedGame>? saved,
    Map<int, HintStat>? hints,
    Set<String>? unlockedStyles,
    int? lastPlayedLevel,
  }) => PlayerProgress(
    records: records ?? this.records,
    saved: saved ?? this.saved,
    hints: hints ?? this.hints,
    unlockedStyles: unlockedStyles ?? this.unlockedStyles,
    lastPlayedLevel: lastPlayedLevel ?? this.lastPlayedLevel,
  );

  /// Styles earned by [stars] stars, added to those already unlocked.
  Set<String> _unlockedFor(int stars) => {
    ...unlockedStyles,
    // Free styles are always available, so they are never stored.
    for (final e in BottleUnlocks.starsRequired.entries)
      if (e.value > 0 && stars >= e.value) e.key,
  };

  /// Records a solved level, keeping the best stars and fewest moves, and
  /// drops its saved game. Idempotent where it matters: stars and unlocks are
  /// derived from the best result, so completing a level again can never
  /// award anything twice.
  PlayerProgress withCompletion({
    required int level,
    required int stars,
    required int moves,
  }) {
    final old = records[level];
    final merged = LevelRecord(
      stars: old == null || stars > old.stars ? stars : old.stars,
      bestMoves: old == null || moves < old.bestMoves ? moves : old.bestMoves,
      completions: (old?.completions ?? 0) + 1,
    );
    final next = {...records, level: merged};
    final total = next.values.fold(0, (a, r) => a + r.stars);
    return _copy(
      records: next,
      saved: {...saved}..remove(level),
      unlockedStyles: _unlockedFor(total),
    );
  }

  PlayerProgress withSavedGame(SavedGame game) {
    final next = {...saved}..remove(game.level);
    next[game.level] = game; // newest last
    while (next.length > maxSavedGames) {
      next.remove(next.keys.first);
    }
    return _copy(saved: next, lastPlayedLevel: game.level);
  }

  PlayerProgress withoutSavedGame(int level) {
    if (!saved.containsKey(level)) return this;
    return _copy(saved: {...saved}..remove(level));
  }

  PlayerProgress withLastPlayed(int level) =>
      lastPlayedLevel == level ? this : _copy(lastPlayedLevel: level);

  PlayerProgress withHint(int level, {int requested = 0, int shown = 0}) {
    if (requested == 0 && shown == 0) return this;
    return _copy(
      hints: {
        ...hints,
        level: hintsOf(level).add(requested: requested, shown: shown),
      },
    );
  }

  /// Adds any style the current stars have earned (used when loading, so a
  /// player is never short of an unlock they have qualified for).
  PlayerProgress normalized() {
    final u = _unlockedFor(totalStars);
    return u.length == unlockedStyles.length ? this : _copy(unlockedStyles: u);
  }

  /// The pre-database JSON form (still read when importing old data).
  Map<String, Object?> toJson() => {
    'v': 1,
    'last': lastPlayedLevel,
    'records': {for (final e in records.entries) '${e.key}': e.value.toJson()},
    'saved': [for (final g in saved.values) g.toJson()],
  };

  /// Tolerant of corrupt or foreign data: bad entries are skipped, never
  /// thrown, so a damaged file cannot stop the game from starting.
  static PlayerProgress fromJson(Object? j) {
    if (j is! Map) return empty;
    final records = <int, LevelRecord>{};
    final rawRecords = j['records'];
    if (rawRecords is Map) {
      for (final e in rawRecords.entries) {
        final level = int.tryParse('${e.key}');
        final rec = LevelRecord.fromJson(e.value);
        if (level != null && level >= 1 && rec != null) records[level] = rec;
      }
    }
    final saved = <int, SavedGame>{};
    final rawSaved = j['saved'];
    if (rawSaved is List) {
      for (final s in rawSaved) {
        final g = SavedGame.fromJson(s);
        if (g != null && !records.containsKey(g.level)) saved[g.level] = g;
      }
    }
    final last = j['last'];
    return PlayerProgress(
      records: records,
      saved: saved,
      lastPlayedLevel: last is int && last >= 1 ? last : null,
    );
  }
}
