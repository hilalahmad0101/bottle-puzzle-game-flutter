import '../models/bottle_model.dart';
import '../models/color_unit.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import 'difficulty.dart';

/// How a level's board was produced.
enum GenerationMethod {
  tutorial,

  /// Scrambled backwards from a solved board (solvable by construction).
  reverse,

  /// Random classic board accepted only after the solver found a solution.
  solverVerified,

  /// Fixed safe board used when no candidate was acceptable.
  fallback,
}

/// A fully described level, ready to store and to play.
final class GeneratedLevel {
  GeneratedLevel({
    required this.levelNumber,
    required this.seed,
    required this.variant,
    required this.generatorVersion,
    required this.puzzle,
    required this.fingerprint,
    required this.metrics,
    required this.difficulty,
    required Iterable<MoveModel> solution,
    required this.method,
    this.attempts = 0,
  }) : solution = List.unmodifiable(solution);

  final int levelNumber;

  /// Seed of the winning attempt's random stream.
  final int seed;

  /// 0 for the canonical level. Only >0 when a caller asked for an
  /// alternative layout to avoid a recently seen one.
  final int variant;
  final int generatorVersion;

  /// The ORIGINAL puzzle state (before any move).
  final PuzzleState puzzle;
  final String fingerprint;
  final DifficultyMetrics metrics;

  /// A verified winning move list (not necessarily the shortest unless
  /// `metrics.solutionIsOptimal`).
  final List<MoveModel> solution;

  final GenerationMethod method;

  bool get isTutorial => method == GenerationMethod.tutorial;

  /// True if the safe fallback board was used instead of a candidate.
  bool get usedFallback => method == GenerationMethod.fallback;
  final int attempts;

  /// Stored tier. Tutorials are always easy; procedural levels use the
  /// graded tier of their metrics.
  final Difficulty difficulty;

  Map<String, Object> toJson() => {
    'levelNumber': levelNumber,
    'seed': seed,
    'variant': variant,
    'generatorVersion': generatorVersion,
    'fingerprint': fingerprint,
    'difficulty': difficulty.name,
    'method': method.name,
    'attempts': attempts,
    'capacity': puzzle.bottles.first.capacity,
    'bottles': [
      for (final b in puzzle.bottles) [for (final u in b.units) u.id],
    ],
    'solution': [
      for (final m in solution) [m.source, m.destination],
    ],
    'metrics': metrics.toJson(),
  };

  static GeneratedLevel fromJson(Map<String, Object?> j) {
    final cap = j['capacity']! as int;
    final m = (j['metrics']! as Map).cast<String, Object?>();
    return GeneratedLevel(
      levelNumber: j['levelNumber']! as int,
      seed: j['seed']! as int,
      variant: j['variant']! as int,
      generatorVersion: j['generatorVersion']! as int,
      fingerprint: j['fingerprint']! as String,
      difficulty: Difficulty.values.byName(j['difficulty']! as String),
      method: GenerationMethod.values.byName(j['method']! as String),
      attempts: j['attempts']! as int,
      puzzle: PuzzleState([
        for (final b in (j['bottles']! as List))
          BottleModel(
            capacity: cap,
            units: [for (final id in (b as List)) ColorUnit(id as int)],
          ),
      ]),
      solution: [
        for (final s in (j['solution']! as List))
          MoveModel((s as List)[0] as int, s[1] as int),
      ],
      metrics: DifficultyMetrics(
        colors: m['colors']! as int,
        bottles: m['bottles']! as int,
        solutionLength: m['solutionLength']! as int,
        solutionIsOptimal: m['solutionIsOptimal']! as bool,
        referenceLength: m['referenceLength']! as int,
        segments: m['segments']! as int,
        avgBranching: (m['avgBranching']! as num).toDouble(),
        score: (m['score']! as num).toDouble(),
      ),
    );
  }
}
