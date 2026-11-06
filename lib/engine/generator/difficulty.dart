import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';

enum Difficulty { easy, medium, hard, expert }

/// Measured properties of one puzzle plus a 0..1 difficulty score.
///
/// The solution length is the best KNOWN solution (recorded construction vs.
/// bounded solver), so it is an upper bound on the true optimum unless
/// [solutionIsOptimal] is true.
final class DifficultyMetrics {
  const DifficultyMetrics({
    required this.colors,
    required this.bottles,
    required this.solutionLength,
    required this.solutionIsOptimal,
    required this.referenceLength,
    required this.segments,
    required this.avgBranching,
    required this.score,
  });

  final int colors;
  final int bottles;

  /// Length of the stored (best known) solution.
  final int solutionLength;
  final bool solutionIsOptimal;

  /// Length of the solution from the fixed reference solver run that EVERY
  /// candidate is graded on, so scores are comparable no matter how the
  /// board was built.
  final int referenceLength;

  /// Total same-colour runs over all non-empty bottles (colours = fully
  /// sorted, higher = more fragmented).
  final int segments;

  /// Mean number of legal moves over the states along the known solution.
  final double avgBranching;

  /// 0 (trivial) .. 1 (hardest this generator makes).
  final double score;

  Difficulty get difficulty => DifficultyGrader.tierOf(score);

  Map<String, Object> toJson() => {
    'colors': colors,
    'bottles': bottles,
    'solutionLength': solutionLength,
    'solutionIsOptimal': solutionIsOptimal,
    'referenceLength': referenceLength,
    'segments': segments,
    'avgBranching': avgBranching,
    'score': score,
  };
}

/// Grades puzzles. Weights/thresholds are part of the generator version.
abstract final class DifficultyGrader {
  static const double mediumFrom = 0.40;
  static const double hardFrom = 0.55;
  static const double expertFrom = 0.70;

  static Difficulty tierOf(double score) {
    if (score >= expertFrom) return Difficulty.expert;
    if (score >= hardFrom) return Difficulty.hard;
    if (score >= mediumFrom) return Difficulty.medium;
    return Difficulty.easy;
  }

  static double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  /// [reference] is the move list the score is computed from (the fixed
  /// reference solver's output). [storedLength]/[storedIsOptimal] describe
  /// the solution actually stored with the level.
  static DifficultyMetrics measure(
    PuzzleState puzzle,
    List<MoveModel> reference, {
    required int storedLength,
    required bool storedIsOptimal,
  }) {
    final colors = puzzle.colorCounts.length;
    var segments = 0;
    for (final b in puzzle.bottles) {
      if (b.isEmpty) continue;
      segments++;
      for (var i = 1; i < b.length; i++) {
        if (b.units[i] != b.units[i - 1]) segments++;
      }
    }

    var branching = 0;
    var cur = puzzle;
    for (final m in reference) {
      branching += PourRules.legalMoves(cur).length;
      cur = PourRules.apply(cur, m).resultingState;
    }
    final avgBranching = reference.isEmpty ? 0.0 : branching / reference.length;

    final cap = puzzle.bottles.isEmpty ? 4 : puzzle.bottles.first.capacity;
    final colourNorm = _clamp01((colors - 3) / 7);
    final lenNorm = _clamp01(
      (reference.length / (colors == 0 ? 1 : colors) - 1.5) / 1.5,
    );
    final fragNorm = _clamp01(
      (segments - colors) / (colors == 0 ? 1 : colors * (cap - 1)),
    );
    final branchNorm = _clamp01((avgBranching - 5) / 8);

    final score =
        0.35 * colourNorm +
        0.30 * lenNorm +
        0.15 * fragNorm +
        0.20 * branchNorm;

    return DifficultyMetrics(
      colors: colors,
      bottles: puzzle.bottleCount,
      solutionLength: storedLength,
      solutionIsOptimal: storedIsOptimal,
      referenceLength: reference.length,
      segments: segments,
      avgBranching: avgBranching,
      score: score,
    );
  }
}
