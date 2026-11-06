import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/generator/difficulty.dart';
import 'package:prism_pour/engine/generator/generated_level.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/generator/level_curve.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/generator/level_service.dart';
import 'package:prism_pour/engine/generator/level_validator.dart';
import 'package:prism_pour/engine/generator/puzzle_fingerprint.dart';
import 'package:prism_pour/engine/generator/reverse_builder.dart';
import 'package:prism_pour/engine/generator/seeded_random.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/engine/rules/pour_rules.dart';
import 'package:prism_pour/engine/solver/puzzle_solver.dart';
import 'package:prism_pour/engine/solver/solver_config.dart';
import 'package:prism_pour/engine/solver/solver_result.dart';

const gen = LevelGenerator();

/// Replays through the real engine and asserts the level ends completed.
void expectReplayWins(PuzzleState start, List<MoveModel> moves) {
  final engine = GameEngine(start);
  for (final m in moves) {
    expect(engine.applyMove(m).isSuccess, isTrue, reason: 'illegal $m');
  }
  expect(engine.isLevelCompleted(), isTrue);
}

/// Level numbers for the representative sweep: every level 1..600, then 500
/// numbers spread (deterministically) up to the millions => 1100 levels.
final sweep = <int>[
  for (var l = 1; l <= 600; l++) l,
  for (var i = 1; i <= 500; i++) 600 + i * i * 37 + i,
];

void main() {
  group('seeded random', () {
    test('matches the canonical mulberry32 stream (golden)', () {
      final r = SeededRandom(12345);
      expect(
        [for (var i = 0; i < 4; i++) r.nextUint32()],
        [4207900869, 1317490944, 2079646450, 3513001552],
      );
    });

    test('seed derivation is pinned (golden)', () {
      expect(StableHash.levelSeed(1, 6, 0), 996287868);
      expect(StableHash.levelSeed(1, 1000, 0), 612121123);
      expect(StableHash.levelSeed(1, 6, 1), 4166997825);
    });

    test('same seed, same stream; different seed, different stream', () {
      List<int> take(int s) {
        final r = SeededRandom(s);
        return [for (var i = 0; i < 8; i++) r.nextUint32()];
      }

      expect(take(7), take(7));
      expect(take(7), isNot(take(8)));
    });

    test('nextInt stays in range and shuffle is a permutation', () {
      final r = SeededRandom(99);
      for (var i = 0; i < 1000; i++) {
        expect(r.nextInt(7), inInclusiveRange(0, 6));
      }
      final list = List<int>.generate(20, (i) => i);
      r.shuffle(list);
      expect(list.toList()..sort(), List<int>.generate(20, (i) => i));
      expect(list, isNot(List<int>.generate(20, (i) => i)));
    });

    test('seeds for adjacent levels / attempts / variants all differ', () {
      final seeds = <int>{
        for (var l = 1; l <= 200; l++)
          for (var v = 0; v < 3; v++)
            for (var a = 0; a < 3; a++) StableHash.levelSeed(1, l, v, a),
      };
      expect(seeds.length, 200 * 3 * 3);
    });
  });

  group('tutorials (levels 1-5)', () {
    test('are handcrafted, valid and replay to a win', () {
      for (var l = 1; l <= kTutorialLevels; l++) {
        final lv = gen.generate(l);
        expect(lv.isTutorial, isTrue);
        expect(lv.difficulty, Difficulty.easy);
        expect(
          LevelValidator.problems(lv.puzzle, lv.solution),
          isEmpty,
          reason: 'level $l',
        );
        expectReplayWins(lv.puzzle, lv.solution);
      }
    });

    test('stored solutions are PROVEN shortest by exhaustive BFS', () {
      for (var l = 1; l <= kTutorialLevels; l++) {
        final lv = gen.generate(l);
        final r = const PuzzleSolver().solve(
          lv.puzzle,
          config: const SolverConfig(
            strategy: SolverStrategy.bfs,
            maxNodes: 2000000,
          ),
        );
        expect(r.status, SolverStatus.solved);
        expect(r.isOptimal, isTrue);
        expect(lv.solution.length, r.moves.length, reason: 'level $l');
      }
    });

    test('get progressively longer', () {
      final lens = [
        for (var l = 1; l <= kTutorialLevels; l++)
          gen.generate(l).solution.length,
      ];
      for (var i = 1; i < lens.length; i++) {
        expect(lens[i], greaterThan(lens[i - 1]));
      }
    });

    test('are fixed: variants do not alter them', () {
      for (var l = 1; l <= kTutorialLevels; l++) {
        expect(
          gen.generate(l, variant: 3).fingerprint,
          gen.generate(l).fingerprint,
        );
      }
    });

    test('level 6 is the first procedural level', () {
      expect(gen.generate(5).isTutorial, isTrue);
      expect(gen.generate(6).isTutorial, isFalse);
      expect(gen.generate(6).method, isNot(GenerationMethod.tutorial));
    });
  });

  group('determinism', () {
    test('same level + version => identical puzzle, solution, metadata', () {
      for (final l in [6, 7, 29, 100, 777, 1000, 54321, 100000]) {
        final a = gen.generate(l);
        final b = const LevelGenerator().generate(l);
        expect(a.puzzle, b.puzzle, reason: 'level $l');
        expect(a.solution, b.solution);
        expect(a.fingerprint, b.fingerprint);
        expect(a.seed, b.seed);
        expect(a.difficulty, b.difficulty);
        expect(a.generatorVersion, kGeneratorVersion);
      }
    });

    test('generation order / history does not matter', () {
      final first = gen.generate(500);
      for (var l = 1; l < 40; l++) {
        gen.generate(l * 13);
      }
      expect(gen.generate(500).puzzle, first.puzzle);
    });

    test('golden fingerprints: tuning changes require a version bump', () {
      // If this fails you changed generation output. Bump
      // kGeneratorVersion deliberately and refresh these values.
      expect(kGeneratorVersion, 1);
      expect(gen.generate(6).fingerprint, '8128797dc0f46ea1');
      expect(gen.generate(100).fingerprint, 'a0c33e85368a31d9');
      expect(gen.generate(1000).fingerprint, '6846731f5745623b');
      expect(gen.generate(100000).fingerprint, '3623dd0b04b74397');
    });

    test('a stored seed + variant reproduces the level', () {
      final lv = gen.generate(321, variant: 2);
      expect(lv.variant, 2);
      expect(
        gen.generate(lv.levelNumber, variant: lv.variant).puzzle,
        lv.puzzle,
      );
    });

    test('variants give different layouts', () {
      final a = gen.generate(250, variant: 0);
      final b = gen.generate(250, variant: 1);
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('JSON round-trip preserves everything', () {
      for (final l in [2, 6, 90, 12345]) {
        final lv = gen.generate(l);
        final back = GeneratedLevel.fromJson(lv.toJson());
        expect(back.puzzle, lv.puzzle);
        expect(back.solution, lv.solution);
        expect(back.fingerprint, lv.fingerprint);
        expect(back.seed, lv.seed);
        expect(back.variant, lv.variant);
        expect(back.generatorVersion, lv.generatorVersion);
        expect(back.difficulty, lv.difficulty);
        expect(back.method, lv.method);
        expect(back.metrics.score, lv.metrics.score);
      }
    });
  });

  group('unlimited levels', () {
    test('very large level numbers generate valid levels', () {
      for (final l in [
        1000000,
        1 << 31,
        1 << 32,
        (1 << 32) + 1,
        1 << 40,
        1 << 62,
      ]) {
        final lv = gen.generate(l);
        expect(lv.levelNumber, l);
        expect(
          LevelValidator.problems(lv.puzzle, lv.solution, minEmptyBottles: 2),
          isEmpty,
          reason: 'level $l',
        );
      }
      expect(
        gen.generate(1 << 32).fingerprint,
        isNot(gen.generate((1 << 32) + 1).fingerprint),
      );
    });

    test('invalid inputs are rejected', () {
      expect(() => gen.generate(0), throwsArgumentError);
      expect(() => gen.generate(-5), throwsArgumentError);
      expect(() => gen.generate(6, variant: -1), throwsArgumentError);
    });
  });

  group('sweep of ${sweep.length} representative levels', () {
    final levels = <GeneratedLevel>[];
    var maxAttempts = 0;

    setUpAll(() {
      for (final l in sweep) {
        levels.add(gen.generate(l));
      }
    });

    test('covers at least 1000 distinct level numbers', () {
      expect(sweep.toSet().length, greaterThanOrEqualTo(1000));
    });

    test('every level is mathematically valid and replays to a win', () {
      for (final lv in levels) {
        final reason = 'level ${lv.levelNumber}';
        final p = lv.puzzle;
        final cap = p.bottles.first.capacity;
        final empties = lv.isTutorial ? 1 : kEmptyBottles;

        expect(
          LevelValidator.problems(
            p,
            lv.solution,
            minEmptyBottles: empties,
            maxBottles: kMaxBottles,
          ),
          isEmpty,
          reason: reason,
        );
        expect(cap, kBottleCapacity, reason: reason);
        // Each colour appears exactly `capacity` times.
        for (final n in p.colorCounts.values) {
          expect(n, cap, reason: reason);
        }
        expect(PourRules.isCompleted(p), isFalse, reason: reason);
        expect(p.bottleCount, lessThanOrEqualTo(kMaxBottles), reason: reason);
        expectReplayWins(p, lv.solution);

        // Metadata.
        expect(lv.generatorVersion, kGeneratorVersion);
        expect(lv.fingerprint, PuzzleFingerprint.of(p), reason: reason);
        expect(lv.variant, 0);
        if (!lv.isTutorial) {
          expect(
            lv.difficulty,
            DifficultyGrader.tierOf(lv.metrics.score),
            reason: reason,
          );
          expect(lv.attempts, inInclusiveRange(1, gen.config.maxAttempts));
          if (lv.attempts > maxAttempts) maxAttempts = lv.attempts;
        }
      }
    });

    test('an independent solver agrees every level is solvable', () {
      // Every 7th level, with a bigger budget and a different strategy.
      for (var i = 0; i < levels.length; i += 7) {
        final lv = levels[i];
        final r = const PuzzleSolver().solve(
          lv.puzzle,
          config: const SolverConfig(
            strategy: SolverStrategy.bestFirst,
            maxNodes: 50000,
          ),
        );
        expect(
          r.status,
          SolverStatus.solved,
          reason: 'level ${lv.levelNumber}',
        );
      }
    });

    test('safe fallback is (almost) never needed', () {
      final fallbacks = levels.where((l) => l.usedFallback).length;
      expect(fallbacks, lessThanOrEqualTo(levels.length ~/ 100));
    });

    test('generation cost is bounded by the attempt cap', () {
      expect(maxAttempts, lessThanOrEqualTo(gen.config.maxAttempts));
    });

    test('colour count never decreases along the ramp and caps at 10', () {
      var prev = 0;
      for (var l = 6; l <= 400; l++) {
        final c = LevelCurve.forLevel(l).colors;
        expect(c, greaterThanOrEqualTo(prev));
        expect(c, lessThanOrEqualTo(kMaxColors));
        prev = c;
      }
      expect(LevelCurve.forLevel(6).colors, kMinColors);
      expect(LevelCurve.forLevel(1000000).colors, kMaxColors);
    });

    test('difficulty rises gradually: block means climb', () {
      double mean(int from, int to) {
        final xs = [
          for (final lv in levels)
            if (lv.levelNumber >= from && lv.levelNumber <= to)
              lv.metrics.score,
        ];
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      final blocks = <double>[
        for (var s = 6; s < 126; s += 20) mean(s, s + 19),
      ];
      for (var i = 1; i < blocks.length; i++) {
        expect(
          blocks[i],
          greaterThan(blocks[i - 1] - 0.02),
          reason: 'block $i: $blocks',
        );
      }
      expect(blocks.last, greaterThan(blocks.first + 0.3));
      expect(mean(130, 600), greaterThan(0.7));
    });

    test('all four tiers appear, in order of level number', () {
      double firstLevelOf(Difficulty d) => levels
          .where((l) => !l.isTutorial && l.difficulty == d)
          .map((l) => l.levelNumber)
          .reduce((a, b) => a < b ? a : b)
          .toDouble();
      final e = firstLevelOf(Difficulty.easy);
      final m = firstLevelOf(Difficulty.medium);
      final h = firstLevelOf(Difficulty.hard);
      final x = firstLevelOf(Difficulty.expert);
      expect(e, lessThan(m));
      expect(m, lessThan(h));
      expect(h, lessThan(x));
    });

    test('early levels are easy and late levels are expert', () {
      final early = levels.where(
        (l) => l.levelNumber >= 6 && l.levelNumber <= 20,
      );
      final late = levels.where((l) => l.levelNumber >= 150);
      expect(
        early.where((l) => l.difficulty == Difficulty.easy).length,
        greaterThanOrEqualTo((early.length * 0.8).floor()),
      );
      expect(
        late.where((l) => l.difficulty == Difficulty.expert).length,
        greaterThanOrEqualTo((late.length * 0.9).floor()),
      );
    });

    test('solution length grows with level (reference length)', () {
      double meanLen(int from, int to) {
        final xs = [
          for (final lv in levels)
            if (lv.levelNumber >= from && lv.levelNumber <= to)
              lv.metrics.referenceLength.toDouble(),
        ];
        return xs.reduce((a, b) => a + b) / xs.length;
      }

      expect(meanLen(6, 25), lessThan(meanLen(46, 65)));
      expect(meanLen(46, 65), lessThan(meanLen(100, 140)));
    });

    test('procedural levels use both construction methods', () {
      final methods = levels.map((l) => l.method).toSet();
      expect(
        methods,
        containsAll([
          GenerationMethod.reverse,
          GenerationMethod.solverVerified,
        ]),
      );
    });

    test('layout repeats: none among late levels, rare overall', () {
      final late = levels
          .where((l) => l.levelNumber >= 100)
          .map((l) => l.fingerprint);
      expect(late.toSet().length, late.length);
      final all = levels.map((l) => l.fingerprint).toList();
      final dupes = all.length - all.toSet().length;
      expect(dupes, lessThan(all.length ~/ 20)); // < 5%
    });
  });

  group('bounded cost and safe fallback', () {
    test(
      'starved budgets fall back to a verified level instead of hanging',
      () {
        const starved = LevelGenerator(
          config: GeneratorConfig(maxAttempts: 2, referenceMaxNodes: 1),
        );
        final lv = starved.generate(200);
        expect(lv.usedFallback, isTrue);
        expect(lv.method, GenerationMethod.fallback);
        expect(lv.attempts, lessThanOrEqualTo(2));
        expect(LevelValidator.problems(lv.puzzle, lv.solution), isEmpty);
        expectReplayWins(lv.puzzle, lv.solution);
      },
    );

    test('a tight tolerance still terminates and returns a valid level', () {
      const strict = LevelGenerator(
        config: GeneratorConfig(toleranceBase: 0, toleranceStep: 0),
      );
      final lv = strict.generate(90);
      expect(lv.attempts, 16);
      expect(
        LevelValidator.problems(lv.puzzle, lv.solution, minEmptyBottles: 2),
        isEmpty,
      );
    });
  });

  group('reverse builder', () {
    test(
      'every build is a classic, correct-count, solvable-by-recording board',
      () {
        var built = 0;
        for (var seed = 1; seed <= 150; seed++) {
          final colors = 3 + seed % 4; // 3..6
          final b = ReverseBuilder.build(
            colors: colors,
            empties: 2,
            capacity: 4,
            steps: colors * 4,
            rng: SeededRandom(seed),
          );
          if (b == null) continue;
          built++;
          final p = b.puzzle;
          expect(p.bottleCount, colors + 2);
          expect(p.bottles.where((x) => x.isEmpty).length, 2);
          expect(
            p.bottles.where((x) => !x.isEmpty).every((x) => x.isFull),
            isTrue,
          );
          for (final n in p.colorCounts.values) {
            expect(n, 4);
          }
          // Recorded forward moves are legal under the real engine and end solved.
          expectReplayWins(p, b.solution);
          // And undoing them reconstructs the earlier states exactly.
          final engine = GameEngine(p);
          for (final m in b.solution) {
            engine.applyMove(m);
          }
          while (engine.canUndo) {
            engine.undoMove();
          }
          expect(engine.state, p);
        }
        expect(built, greaterThan(100));
      },
    );
  });

  group('validator', () {
    PuzzleState st(List<List<int>> b, {int cap = 4}) =>
        PuzzleState.fromIds(b, capacity: cap);

    final good = st([
      [0, 0, 0, 1],
      [1, 1, 1, 0],
      [],
      [],
    ]);
    const goodSol = [MoveModel(0, 2), MoveModel(1, 0), MoveModel(1, 2)];

    test('accepts a correct level', () {
      expect(
        LevelValidator.problems(good, goodSol, minEmptyBottles: 2),
        isEmpty,
      );
    });

    test('rejects wrong colour counts', () {
      final bad = st([
        [0, 0, 0],
        [1, 1, 1, 1],
        [],
        [],
      ]);
      expect(
        LevelValidator.problems(bad, const []),
        anyElement(contains('colour 0')),
      );
    });

    test('rejects an already completed puzzle', () {
      final done = st([
        [0, 0, 0, 0],
        [1, 1, 1, 1],
        [],
        [],
      ]);
      expect(
        LevelValidator.problems(done, const []),
        contains('already completed'),
      );
    });

    test('rejects too few empty bottles', () {
      expect(
        LevelValidator.problems(good, goodSol, minEmptyBottles: 3),
        anyElement(contains('empty bottles')),
      );
    });

    test('rejects a solution that does not win or is illegal', () {
      expect(
        LevelValidator.problems(good, const [MoveModel(0, 2)]),
        contains('solution does not replay to a win'),
      );
      expect(
        LevelValidator.problems(good, const [MoveModel(2, 3)]),
        contains('solution does not replay to a win'),
      );
    });

    test('rejects too many bottles and mixed capacities', () {
      expect(
        LevelValidator.problems(good, goodSol, maxBottles: 3),
        anyElement(contains('exceeds')),
      );
      final mixed = PuzzleState([
        BottleModel(
          capacity: 4,
          units: const [ColorUnit(0), ColorUnit(0), ColorUnit(0), ColorUnit(1)],
        ),
        BottleModel(
          capacity: 3,
          units: const [ColorUnit(1), ColorUnit(1), ColorUnit(1)],
        ),
        BottleModel(capacity: 4),
      ]);
      expect(
        LevelValidator.problems(mixed, const []),
        contains('bottle capacities differ'),
      );
    });
  });

  group('fingerprint', () {
    test('ignores bottle order, distinguishes layouts', () {
      final a = PuzzleState.fromIds([
        [0, 1],
        [1, 0],
        [],
      ]);
      final b = PuzzleState.fromIds([
        [],
        [0, 1],
        [1, 0],
      ]);
      final c = PuzzleState.fromIds([
        [1, 0],
        [1, 0],
        [],
      ]);
      expect(PuzzleFingerprint.of(a), PuzzleFingerprint.of(b));
      expect(PuzzleFingerprint.of(a), isNot(PuzzleFingerprint.of(c)));
      expect(PuzzleFingerprint.of(a), hasLength(16));
    });
  });

  group('recent layouts & background generation', () {
    test('RecentLayouts is bounded and refreshes on re-add', () {
      final r = RecentLayouts(capacity: 3);
      for (final f in ['a', 'b', 'c', 'd']) {
        r.add(f);
      }
      expect(r.items, ['b', 'c', 'd']);
      r.add('b');
      expect(r.items, ['c', 'd', 'b']);
      expect(r.contains('a'), isFalse);
    });

    test('LevelService matches synchronous generation', () async {
      const service = LevelService();
      for (final l in [3, 6, 80, 5000]) {
        final remote = await service.generate(l);
        final local = gen.generate(l);
        expect(remote.puzzle, local.puzzle);
        expect(remote.solution, local.solution);
        expect(remote.fingerprint, local.fingerprint);
      }
    });

    test('a recently seen layout is replaced by a recorded variant', () async {
      const service = LevelService();
      final canonical = gen.generate(250);
      final recent = RecentLayouts()..add(canonical.fingerprint);
      final lv = await service.levelAvoidingRecent(250, recent: recent);
      expect(lv.variant, greaterThan(0));
      expect(lv.fingerprint, isNot(canonical.fingerprint));
      // Reproducible from (level, variant) alone.
      expect(gen.generate(250, variant: lv.variant).puzzle, lv.puzzle);
      // The canonical level itself is untouched by history.
      expect(gen.generate(250).puzzle, canonical.puzzle);
      expect(recent.contains(lv.fingerprint), isTrue);
    });

    test('with no history the canonical level is returned', () async {
      const service = LevelService();
      final lv = await service.levelAvoidingRecent(
        250,
        recent: RecentLayouts(),
      );
      expect(lv.variant, 0);
      expect(lv.puzzle, gen.generate(250).puzzle);
    });

    test('tutorials ignore repeat avoidance', () async {
      const service = LevelService();
      final t = gen.generate(2);
      final recent = RecentLayouts()..add(t.fingerprint);
      final lv = await service.levelAvoidingRecent(2, recent: recent);
      expect(lv.variant, 0);
      expect(lv.fingerprint, t.fingerprint);
    });
  });
}
