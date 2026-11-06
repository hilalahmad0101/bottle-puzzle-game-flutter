import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/engine/rules/pour_rules.dart';
import 'package:prism_pour/engine/solver/hint.dart';
import 'package:prism_pour/engine/solver/puzzle_solver.dart';
import 'package:prism_pour/engine/solver/solution_verifier.dart';
import 'package:prism_pour/engine/solver/solver_config.dart';
import 'package:prism_pour/engine/solver/solver_result.dart';
import 'package:prism_pour/engine/solver/solver_service.dart';
import 'package:prism_pour/engine/solver/state_key.dart';

const solver = PuzzleSolver();

PuzzleState st(List<List<int>> b, {int cap = 4}) =>
    PuzzleState.fromIds(b, capacity: cap);

/// Replays through the real engine and asserts the level ends completed.
void expectReplayWins(PuzzleState start, SolveResult r) {
  expect(r.isSolved, isTrue, reason: '$r');
  final engine = GameEngine(start);
  for (final m in r.moves) {
    expect(engine.applyMove(m).isSuccess, isTrue, reason: 'illegal $m');
  }
  expect(engine.isLevelCompleted(), isTrue);
  expect(SolutionVerifier.verify(start, r.moves), isTrue);
}

/// Seeded test-only puzzle shuffler (NOT level generation).
PuzzleState shuffled(int colors, int empties, int seed, {int cap = 4}) {
  var x = seed * 2654435761 + 1;
  int next(int n) {
    x = (x * 1103515245 + 12345) & 0x7fffffff;
    return (x >> 8) % n;
  }

  final units = [
    for (var c = 0; c < colors; c++)
      for (var k = 0; k < cap; k++) c,
  ];
  for (var i = units.length - 1; i > 0; i--) {
    final j = next(i + 1);
    final t = units[i];
    units[i] = units[j];
    units[j] = t;
  }
  return st([
    for (var b = 0; b < colors; b++) units.sublist(b * cap, (b + 1) * cap),
    for (var e = 0; e < empties; e++) <int>[],
  ], cap: cap);
}

/// Independent reference: plain BFS over RAW states, no canonicalization,
/// no pruning. Returns shortest length, or null if unsolvable.
int? referenceShortest(PuzzleState start) {
  if (PourRules.isCompleted(start)) return 0;
  final seen = <PuzzleState>{start};
  var frontier = [start];
  var d = 0;
  while (frontier.isNotEmpty) {
    d++;
    final next = <PuzzleState>[];
    for (final s in frontier) {
      for (final m in PourRules.legalMoves(s)) {
        final c = PourRules.apply(s, m).resultingState;
        if (!seen.add(c)) continue;
        if (PourRules.isCompleted(c)) return d;
        next.add(c);
      }
    }
    frontier = next;
  }
  return null;
}

void main() {
  group('already solved / trivial', () {
    test('completed puzzle needs no moves and is optimal', () {
      final p = st([
        [1, 1, 1, 1],
        [2, 2, 2, 2],
        [],
      ]);
      final r = solver.solve(p);
      expect(r.status, SolverStatus.alreadySolved);
      expect(r.moves, isEmpty);
      expect(r.isOptimal, isTrue);
      expectReplayWins(p, r);
    });

    test('all-empty and zero-bottle states count as solved', () {
      expect(solver.solve(st([[], []])).status, SolverStatus.alreadySolved);
      expect(solver.solve(st([])).status, SolverStatus.alreadySolved);
    });

    test('invalid state is rejected', () {
      final bad = PuzzleState([
        BottleModel(capacity: 1, units: const [ColorUnit(1), ColorUnit(1)]),
      ]);
      expect(solver.solve(bad).status, SolverStatus.invalidState);
    });
  });

  group('handcrafted solvable puzzles', () {
    test('one move', () {
      final p = st([
        [1, 1, 1],
        [1],
      ]);
      final r = solver.solve(p);
      expect(r.status, SolverStatus.solved);
      // Either (1->0) or (0->1) completes it; both are 1 move.
      expect(r.moves.length, 1);
      expect(r.isOptimal, isTrue);
      expectReplayWins(p, r);
    });

    test('easy: two colours, one empty bottle', () {
      final p = st([
        [1, 2, 1, 2],
        [2, 1, 2, 1],
        [],
      ]);
      final r = solver.solve(p);
      expectReplayWins(p, r);
      expect(r.isOptimal, isTrue);
    });

    test('medium: 4 colours, 2 empty bottles', () {
      final p = st([
        [1, 2, 3, 4],
        [2, 3, 4, 1],
        [3, 4, 1, 2],
        [4, 1, 2, 3],
        [],
        [],
      ]);
      final r = solver.solve(p);
      expectReplayWins(p, r);
    });

    test('preserves real bottle indices (solution not renumbered)', () {
      // The only legal first pours go into the single empty bottle, so the
      // destination must be that bottle's real index, wherever it sits.
      final empty0 = st([
        [],
        [1, 2, 1, 2],
        [2, 1, 2, 1],
      ]);
      final r0 = solver.solve(empty0);
      expectReplayWins(empty0, r0);
      expect(r0.moves.first.destination, 0);

      final empty2 = st([
        [1, 2, 1, 2],
        [2, 1, 2, 1],
        [],
      ]);
      final r2 = solver.solve(empty2);
      expectReplayWins(empty2, r2);
      expect(r2.moves.first.destination, 2);
    });

    test('mixed capacities are supported', () {
      final p = PuzzleState([
        BottleModel(capacity: 2, units: const [ColorUnit(1), ColorUnit(2)]),
        BottleModel(
          capacity: 3,
          units: const [ColorUnit(2), ColorUnit(1), ColorUnit(1)],
        ),
        BottleModel(capacity: 3, units: const [ColorUnit(2)]),
        BottleModel(capacity: 2),
      ]);
      final r = solver.solve(p);
      if (r.isSolved) expectReplayWins(p, r);
      expect(r.status, isNot(SolverStatus.budgetExceeded));
    });
  });

  group('complex puzzles', () {
    test('8 colours, 2 empties (auto strategy) is solved and replays', () {
      final p = shuffled(8, 2, 7);
      final r = solver.solve(p);
      expect(r.status, SolverStatus.solved, reason: '$r');
      expectReplayWins(p, r);
    });

    test('10 colours, 2 empties best-first solves and replays', () {
      final p = shuffled(10, 2, 3);
      final r = solver.solve(
        p,
        config: const SolverConfig(strategy: SolverStrategy.bestFirst),
      );
      expect(r.status, SolverStatus.solved, reason: '$r');
      expect(r.isOptimal, isFalse, reason: 'best-first must not claim optimal');
      expectReplayWins(p, r);
    });

    test('several seeded boards all verify through the engine', () {
      for (var seed = 1; seed <= 12; seed++) {
        final p = shuffled(6, 2, seed);
        final r = solver.solve(p);
        expect(r.status, SolverStatus.solved, reason: 'seed $seed: $r');
        expectReplayWins(p, r);
      }
    });
  });

  group('impossible puzzles', () {
    test('colour count not a multiple of capacity (counting proof)', () {
      final r = solver.solve(
        st([
          [1, 1, 1],
          [2, 2, 2, 2],
          [],
        ]),
      );
      expect(r.status, SolverStatus.unsolvable);
      expect(r.nodesGenerated, 0);
    });

    test('more full bottles needed than exist (counting proof)', () {
      final r = solver.solve(
        st([
          [1, 1, 2, 2],
          [3, 3, 1, 1],
          [2, 2, 3, 3],
        ]),
      );
      expect(r.status, SolverStatus.unsolvable);
    });

    test('stuck board with no legal move (exhausted search)', () {
      final r = solver.solve(
        st([
          [1, 1, 2, 2],
          [2, 2, 1, 1],
        ]),
      );
      expect(r.status, SolverStatus.unsolvable);
      expect(r.moves, isEmpty);
    });

    test('unsolvable proven by exhausting a non-trivial space', () {
      // One empty bottle gives legal moves; some such boards are dead ends.
      var found = 0;
      for (var seed = 1; seed <= 200; seed++) {
        final p = shuffled(3, 1, seed);
        final r = solver.solve(p);
        if (r.status == SolverStatus.unsolvable && r.nodesGenerated > 1) {
          found++;
          expect(referenceShortest(p), isNull, reason: 'seed $seed');
        }
      }
      expect(found, greaterThan(0), reason: 'expected dead-end boards');
    });
  });

  group('equivalence & canonicalization', () {
    test('bottle order does not change the key', () {
      final a = st([
        [1, 2],
        [3],
        [],
      ]);
      final b = st([
        [],
        [1, 2],
        [3],
      ]);
      final k = StateKeyer(a);
      expect(k.key(a), k.key(b));
    });

    test('different contents or capacities never share a key', () {
      final a = st([
        [1, 2],
        [3],
      ]);
      final k = StateKeyer(a);
      expect(
        k.key(a),
        isNot(
          k.key(
            st([
              [2, 1],
              [3],
            ]),
          ),
        ),
      );
      expect(
        k.key(a),
        isNot(
          k.key(
            st([
              [1, 2],
              [3],
            ], cap: 5),
          ),
        ),
      );
      expect(
        k.key(
          st([
            [1],
            [2],
          ]),
        ),
        isNot(
          k.key(
            st([
              [1, 2],
              [],
            ]),
          ),
        ),
      );
    });

    test('large / negative colour ids use the exact fallback key', () {
      final a = PuzzleState([
        BottleModel(units: const [ColorUnit(-5), ColorUnit(70000)]),
        BottleModel(),
      ]);
      final b = PuzzleState([a.bottles[1], a.bottles[0]]);
      final k = StateKeyer(a);
      expect(k.key(a), k.key(b));
      final r = solver.solve(a);
      expect(r.status, isNot(SolverStatus.invalidState));
    });

    test('permuted boards agree on status and optimal length', () {
      final a = st([
        [1, 2, 1, 2],
        [2, 1, 2, 1],
        [],
      ]);
      final perms = [
        st([
          [],
          [1, 2, 1, 2],
          [2, 1, 2, 1],
        ]),
        st([
          [2, 1, 2, 1],
          [],
          [1, 2, 1, 2],
        ]),
      ];
      final base = solver.solve(a);
      for (final p in perms) {
        final r = solver.solve(p);
        expect(r.status, base.status);
        expect(r.moves.length, base.moves.length);
        expectReplayWins(p, r);
      }
    });

    test('solver matches an independent raw-state BFS on random boards', () {
      var solvable = 0, unsolvable = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final colors = seed.isEven ? 3 : 2;
        final empties = seed % 3 == 0 ? 0 : 1;
        final cap = colors == 3 ? 3 : 4;
        final p = shuffled(colors, empties, seed, cap: cap);
        final ref = referenceShortest(p);
        final r = solver.solve(
          p,
          config: const SolverConfig(strategy: SolverStrategy.bfs),
        );
        if (ref == null) {
          unsolvable++;
          expect(r.status, SolverStatus.unsolvable, reason: 'seed $seed');
        } else {
          solvable++;
          expect(r.isSolved, isTrue, reason: 'seed $seed');
          expect(r.moves.length, ref, reason: 'optimal length, seed $seed');
          expect(r.isOptimal, isTrue);
          expectReplayWins(p, r);
        }
      }
      expect(solvable, greaterThan(5));
      expect(unsolvable, greaterThan(0));
    });
  });

  group('limits and cancellation', () {
    test('node budget yields budgetExceeded, never a false verdict', () {
      final p = shuffled(8, 2, 7);
      final r = solver.solve(p, config: const SolverConfig(maxNodes: 50));
      expect(r.status, SolverStatus.budgetExceeded);
      expect(r.moves, isEmpty);
      expect(r.nodesGenerated, lessThanOrEqualTo(50));
    });

    test('time budget yields budgetExceeded', () {
      final p = shuffled(10, 2, 3);
      final r = solver.solve(
        p,
        config: const SolverConfig(
          maxNodes: 100000000,
          maxDuration: Duration.zero,
        ),
      );
      expect(r.status, SolverStatus.budgetExceeded);
    });

    test('isCancelled callback stops the search', () {
      final p = shuffled(8, 2, 7);
      final r = solver.solve(p, isCancelled: () => true);
      expect(r.status, SolverStatus.cancelled);
    });

    test('BFS-only does not claim a solution when over budget', () {
      final p = shuffled(8, 2, 7);
      final r = solver.solve(
        p,
        config: const SolverConfig(strategy: SolverStrategy.bfs, maxNodes: 200),
      );
      expect(r.status, SolverStatus.budgetExceeded);
      expect(r.isOptimal, isFalse);
    });
  });

  group('hints (sync planner)', () {
    test('hint is legal and highlights real bottles', () {
      final p = st([
        [1, 1, 2, 2],
        [2, 2, 1, 1],
        [],
      ]);
      final h = HintPlanner().hint(p);
      expect(h.status, HintStatus.available);
      expect(
        PourRules.canPour(p, h.hint!.sourceIndex, h.hint!.destinationIndex),
        isTrue,
      );
      expect(
        h.hint!.quantity,
        PourRules.getPourableUnits(
          p,
          h.hint!.sourceIndex,
          h.hint!.destinationIndex,
        ),
      );
    });

    test('following hints repeatedly wins the level', () {
      final p = shuffled(5, 2, 11);
      final planner = HintPlanner();
      final engine = GameEngine(p);
      var guard = 0;
      while (!engine.isLevelCompleted() && guard++ < 500) {
        final h = planner.hint(engine.state);
        expect(h.status, HintStatus.available);
        expect(engine.applyMove(h.hint!.move).isSuccess, isTrue);
      }
      expect(engine.isLevelCompleted(), isTrue);
    });

    test('cached path is reused while the player follows it', () {
      final planner = HintPlanner();
      final p = shuffled(5, 2, 11);
      final first = planner.hint(p);
      final next = PourRules.apply(p, first.hint!.move).resultingState;
      final second = planner.hint(next);
      expect(second.solve, isNull, reason: 'served from cache, no new solve');
      expect(second.hint!.movesRemaining, first.hint!.movesRemaining - 1);
    });

    test('player deviates: hint is recomputed for the actual state', () {
      final planner = HintPlanner();
      final engine = GameEngine(shuffled(5, 2, 11));
      final suggested = planner.hint(engine.state).hint!.move;
      // Make a different legal move than suggested.
      final other = engine.getLegalMoves().firstWhere((m) => m != suggested);
      engine.applyMove(other);
      final h = planner.hint(engine.state);
      if (h.status == HintStatus.available) {
        expect(
          PourRules.canPour(
            engine.state,
            h.hint!.sourceIndex,
            h.hint!.destinationIndex,
          ),
          isTrue,
        );
        // And it must still lead to a win.
        final e2 = GameEngine(engine.state);
        e2.applyMove(h.hint!.move);
      } else {
        expect(h.status, HintStatus.unsolvable);
      }
    });

    test('player undoes back onto the cached path', () {
      final planner = HintPlanner();
      final p = shuffled(5, 2, 11);
      final first = planner.hint(p);
      final moved = PourRules.apply(p, first.hint!.move).resultingState;
      planner.hint(moved);
      final again = planner.hint(p); // undo to start
      expect(again.solve, isNull);
      expect(again.hint!.move, first.hint!.move);
    });

    test('solved, unsolvable and over-budget states are reported', () {
      final planner = HintPlanner(config: const SolverConfig(maxNodes: 30));
      expect(
        planner
            .hint(
              st([
                [1, 1, 1, 1],
                [],
              ]),
            )
            .status,
        HintStatus.alreadySolved,
      );
      expect(
        planner
            .hint(
              st([
                [1, 2],
                [1, 2],
              ], cap: 2),
            )
            .hint,
        isNull,
      );
      expect(
        planner
            .hint(
              st([
                [1, 1, 2, 2],
                [2, 2, 1, 1],
              ]),
            )
            .status,
        HintStatus.unsolvable,
      );
      final big = planner.hint(shuffled(8, 2, 7));
      expect(big.status, HintStatus.budgetExceeded);
      expect(big.hint, isNull);
    });
  });

  group('background solving (isolate)', () {
    test('service result matches the synchronous solver', () async {
      final p = shuffled(5, 2, 4);
      final local = solver.solve(p);
      final remote = await const SolverService().solve(p);
      expect(remote.status, local.status);
      expect(remote.moves, local.moves);
      expectReplayWins(p, remote);
    });

    test('config crosses the isolate boundary', () async {
      final r = await const SolverService().solve(
        shuffled(8, 2, 7),
        config: const SolverConfig(maxNodes: 50),
      );
      expect(r.status, SolverStatus.budgetExceeded);
    });

    test('cancel resolves to cancelled', () async {
      final req = const SolverService().start(shuffled(10, 2, 3));
      req.cancel();
      expect((await req.result).status, SolverStatus.cancelled);
    });

    test('controller returns a legal hint', () async {
      final c = HintController();
      final p = shuffled(5, 2, 4);
      final r = await c.requestHint(p);
      expect(r.status, HintStatus.available);
      expect(
        PourRules.canPour(p, r.hint!.sourceIndex, r.hint!.destinationIndex),
        isTrue,
      );
      c.dispose();
    });

    test('invalidate() makes an in-flight hint stale', () async {
      final c = HintController();
      final future = c.requestHint(shuffled(8, 2, 7));
      c.invalidate(); // player moved
      expect((await future).status, HintStatus.stale);
    });

    test('a newer request supersedes an older one', () async {
      final c = HintController();
      final older = c.requestHint(shuffled(8, 2, 7));
      final p2 = shuffled(5, 2, 4);
      final newer = c.requestHint(p2);
      expect((await older).status, HintStatus.stale);
      final r = await newer;
      expect(r.status, HintStatus.available);
      expect(
        PourRules.canPour(p2, r.hint!.sourceIndex, r.hint!.destinationIndex),
        isTrue,
      );
      c.dispose();
    });
  });
}
