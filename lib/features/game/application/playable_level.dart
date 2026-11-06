import '../../../engine/generator/difficulty.dart';
import '../../../engine/generator/generated_level.dart';
import '../../../engine/models/move_model.dart';
import '../../../engine/models/puzzle_state.dart';
import '../../progress/domain/player_progress.dart';

/// Everything the game needs to PLAY a level, without caring whether it came
/// from the generator just now or from a saved game days ago.
///
/// [puzzle] is always the ORIGINAL board. A restored level is built from what
/// was stored, not regenerated, so it is identical to what the player started
/// with even if the generator has changed since.
final class PlayableLevel {
  const PlayableLevel({
    required this.levelNumber,
    required this.puzzle,
    required this.seed,
    required this.variant,
    required this.generatorVersion,
    required this.difficulty,
    required this.par,
    required this.fingerprint,
  });

  factory PlayableLevel.fromGenerated(GeneratedLevel g) => PlayableLevel(
    levelNumber: g.levelNumber,
    puzzle: g.puzzle,
    seed: g.seed,
    variant: g.variant,
    generatorVersion: g.generatorVersion,
    difficulty: g.difficulty,
    par: g.solution.length,
    fingerprint: g.fingerprint,
  );

  /// Null unless [s] carries a complete snapshot.
  static PlayableLevel? fromSaved(SavedGame s) {
    final puzzle = s.originalPuzzle;
    final seed = s.seed, par = s.par, d = s.difficultyIndex;
    if (puzzle == null || seed == null || par == null || d == null) return null;
    if (d < 0 || d >= Difficulty.values.length) return null;
    return PlayableLevel(
      levelNumber: s.level,
      puzzle: puzzle,
      seed: seed,
      variant: s.variant,
      generatorVersion: s.generatorVersion,
      difficulty: Difficulty.values[d],
      par: par,
      fingerprint: s.fingerprint ?? '',
    );
  }

  final int levelNumber;
  final PuzzleState puzzle;
  final int seed;
  final int variant;
  final int generatorVersion;
  final Difficulty difficulty;

  /// Length of the best known solution (see `StarRating`).
  final int par;
  final String fingerprint;

  /// The full save for this level at the given moment.
  SavedGame toSaved(
    List<MoveModel> moves,
    PuzzleState current, {
    bool boosted = false,
  }) => SavedGame(
    level: levelNumber,
    variant: variant,
    generatorVersion: generatorVersion,
    moves: moves,
    seed: seed,
    originalPuzzle: puzzle,
    currentPuzzle: current,
    difficultyIndex: difficulty.index,
    par: par,
    fingerprint: fingerprint,
    boosted: boosted,
  );
}
