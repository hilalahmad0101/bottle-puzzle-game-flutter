import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';
import '../solver/puzzle_solver.dart';
import '../solver/solver_config.dart';
import '../solver/solver_result.dart';
import 'difficulty.dart';
import 'generated_level.dart';
import 'generator_version.dart';
import 'level_curve.dart';
import 'level_validator.dart';
import 'puzzle_fingerprint.dart';
import 'reverse_builder.dart';
import 'seeded_random.dart';
import 'shuffled_board.dart';
import 'tutorial_levels.dart';

/// Tuning for generation cost. All limits are COUNTS (attempts, solver
/// nodes), never wall-clock time, so results stay deterministic. Part of
/// the generator version.
final class GeneratorConfig {
  const GeneratorConfig({
    this.maxAttempts = 16,
    this.referenceMaxNodes = 6000,
    this.improveMaxNodes = 6000,
    this.improveBfsBudget = 3000,
    this.toleranceBase = 0.05,
    this.toleranceStep = 0.01,
  });

  final int maxAttempts;

  /// Node cap for the reference solver run every candidate is graded on.
  final int referenceMaxNodes;

  /// Caps for the optional pass that looks for a shorter stored solution
  /// (only run on small boards where it is cheap).
  final int improveMaxNodes;
  final int improveBfsBudget;

  /// A candidate is accepted when |score - target| <= base + step*attempt.
  final double toleranceBase;
  final double toleranceStep;
}

/// Deterministic, unlimited level generator.
///
/// `generate(n)` is a pure function of (n, variant, [kGeneratorVersion],
/// config): it uses no clock, no global state and no `dart:math` Random.
///
/// Pipeline per candidate: reverse-scramble a solved board (every step
/// engine-checked) -> validate -> bounded solver search for a shorter
/// solution -> replay -> grade -> accept if close to the level's target.
/// If no attempt is accepted, the closest valid candidate is used; if none
/// is valid, a verified fallback board is returned and flagged.
/// The whole thing is bounded: at most [GeneratorConfig.maxAttempts]
/// solver runs of at most [GeneratorConfig.solverMaxNodes] states each.
final class LevelGenerator {
  const LevelGenerator({this.config = const GeneratorConfig()});

  final GeneratorConfig config;

  GeneratedLevel generate(int level, {int variant = 0}) {
    if (level < 1) throw ArgumentError.value(level, 'level', 'must be >= 1');
    if (variant < 0) {
      throw ArgumentError.value(variant, 'variant', 'must be >= 0');
    }
    if (level <= kTutorialLevels) return _tutorial(level);
    return _procedural(level, variant);
  }

  GeneratedLevel _tutorial(int level) {
    final t = TutorialLevels.all[level - 1];
    final puzzle = t.puzzle;
    final solution = t.solution;
    final problems = LevelValidator.problems(puzzle, solution);
    if (problems.isNotEmpty) {
      // A broken handcrafted level is a programming error, not a runtime
      // condition: fail loudly (the tests also cover this).
      throw StateError('Tutorial $level invalid: $problems');
    }
    return GeneratedLevel(
      levelNumber: level,
      seed: StableHash.levelSeed(kGeneratorVersion, level, 0),
      variant: 0,
      generatorVersion: kGeneratorVersion,
      puzzle: puzzle,
      fingerprint: PuzzleFingerprint.of(puzzle),
      metrics: DifficultyGrader.measure(
        puzzle,
        solution,
        storedLength: solution.length,
        storedIsOptimal: true, // proven by exhaustive BFS when authored
      ),
      difficulty: Difficulty.easy,
      solution: solution,
      method: GenerationMethod.tutorial,
    );
  }

  GeneratedLevel _procedural(int level, int variant) {
    final params = LevelCurve.forLevel(level);
    _Candidate? best;
    var attemptsUsed = 0;

    for (var attempt = 0; attempt < config.maxAttempts; attempt++) {
      attemptsUsed = attempt + 1;
      final seed = StableHash.levelSeed(
        kGeneratorVersion,
        level,
        variant,
        attempt,
      );
      final c = _candidate(params, seed);
      if (c == null) continue;

      final dist = (c.metrics.score - params.targetScore).abs();
      if (best == null ||
          dist < (best.metrics.score - params.targetScore).abs()) {
        best = c;
      }
      if (dist <= config.toleranceBase + config.toleranceStep * attempt) break;
    }

    if (best == null) return _fallback(level, variant, attemptsUsed);
    return GeneratedLevel(
      levelNumber: level,
      seed: best.seed,
      variant: variant,
      generatorVersion: kGeneratorVersion,
      puzzle: best.puzzle,
      fingerprint: PuzzleFingerprint.of(best.puzzle),
      metrics: best.metrics,
      difficulty: best.metrics.difficulty,
      solution: best.solution,
      method: best.method,
      attempts: attemptsUsed,
    );
  }

  /// Builds, validates, solves and grades one candidate. Null = rejected.
  _Candidate? _candidate(LevelParams p, int seed) {
    final rng = SeededRandom(seed);

    // 1. Board. Reverse construction where it yields classic boards;
    //    otherwise a random classic board that the solver must vouch for.
    ReverseBuild? built;
    if (p.colors <= kReverseMaxColors) {
      final steps =
          p.colors * (3 + (p.progress * 2).round()) + rng.nextInt(p.colors + 1);
      built = ReverseBuilder.build(
        colors: p.colors,
        empties: p.empties,
        capacity: p.capacity,
        steps: steps,
        rng: rng,
      );
    }
    final puzzle =
        built?.puzzle ??
        ShuffledBoard.build(
          colors: p.colors,
          empties: p.empties,
          capacity: p.capacity,
          rng: rng,
        );
    final method = built != null
        ? GenerationMethod.reverse
        : GenerationMethod.solverVerified;
    if (PourRules.isCompleted(puzzle)) return null;

    // 2. Reference solve: the fixed measuring stick for difficulty. It also
    //    proves solvability of shuffled boards. Anything not solved within
    //    the node cap is rejected (bounded cost; fairness).
    const solver = PuzzleSolver();
    final ref = solver.solve(
      puzzle,
      config: SolverConfig(
        strategy: SolverStrategy.bestFirst,
        maxNodes: config.referenceMaxNodes,
      ),
    );
    if (ref.status != SolverStatus.solved) return null;

    // 3. Stored solution: shortest verified of {recorded, reference,
    //    improved}. Improvement is only attempted on small boards.
    var solution = ref.moves;
    var optimal = false;
    if (built != null && built.solution.length < solution.length) {
      solution = built.solution;
    }
    if (p.colors <= kReverseMaxColors) {
      final better = solver.solve(
        puzzle,
        config: SolverConfig(
          maxNodes: config.improveMaxNodes,
          bfsNodeBudget: config.improveBfsBudget,
        ),
      );
      if (better.status == SolverStatus.solved &&
          better.moves.length <= solution.length) {
        solution = better.moves;
        optimal = better.isOptimal;
      }
    }

    // 4. Validate everything, including a full engine replay.
    final problems = LevelValidator.problems(
      puzzle,
      solution,
      minEmptyBottles: p.empties,
      maxBottles: kMaxBottles,
    );
    if (problems.isNotEmpty) return null;
    if (ref.moves.length < p.colors) return null; // too trivial

    return _Candidate(
      seed: seed,
      puzzle: puzzle,
      solution: solution,
      method: method,
      metrics: DifficultyGrader.measure(
        puzzle,
        ref.moves,
        storedLength: solution.length,
        storedIsOptimal: optimal,
      ),
    );
  }

  /// Last resort: a fixed, verified board. Only reachable if every attempt
  /// was rejected (never observed in testing, but must be safe).
  GeneratedLevel _fallback(int level, int variant, int attempts) {
    final t = TutorialLevels.all.last;
    final puzzle = t.puzzle;
    return GeneratedLevel(
      levelNumber: level,
      seed: StableHash.levelSeed(kGeneratorVersion, level, variant),
      variant: variant,
      generatorVersion: kGeneratorVersion,
      puzzle: puzzle,
      fingerprint: PuzzleFingerprint.of(puzzle),
      metrics: DifficultyGrader.measure(
        puzzle,
        t.solution,
        storedLength: t.solution.length,
        storedIsOptimal: true,
      ),
      difficulty: Difficulty.easy,
      solution: t.solution,
      method: GenerationMethod.fallback,
      attempts: attempts,
    );
  }
}

final class _Candidate {
  _Candidate({
    required this.seed,
    required this.puzzle,
    required this.solution,
    required this.method,
    required this.metrics,
  });

  final int seed;
  final GenerationMethod method;
  final PuzzleState puzzle;
  final List<MoveModel> solution;
  final DifficultyMetrics metrics;
}
