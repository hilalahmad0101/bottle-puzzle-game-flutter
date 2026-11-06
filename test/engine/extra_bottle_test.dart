import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/engine/rules/extra_bottle.dart';
import 'package:prism_pour/engine/rules/pour_rules.dart';
import 'package:prism_pour/engine/solver/puzzle_solver.dart';
import 'package:prism_pour/engine/solver/solution_verifier.dart';
import 'package:prism_pour/engine/solver/solver_result.dart';

const solver = PuzzleSolver();

void main() {
  group('adding the extra bottle', () {
    final base = PuzzleState.fromIds([
      [0, 0, 0, 1],
      [1, 1, 1, 0],
      [],
    ]);

    test('appends exactly one EMPTY bottle of the same capacity', () {
      final boosted = ExtraBottle.add(base);
      expect(boosted.bottleCount, 4);
      expect(boosted.bottles.last.isEmpty, isTrue);
      expect(boosted.bottles.last.capacity, 4);
      expect(boosted.colorCounts, base.colorCounts);
    });

    test('every existing bottle keeps its index and contents', () {
      final boosted = ExtraBottle.add(base);
      for (var i = 0; i < base.bottleCount; i++) {
        expect(boosted.bottles[i], base.bottles[i]);
      }
    });

    test('does not change the state it was given', () {
      ExtraBottle.add(base);
      expect(base.bottleCount, 3);
    });

    test('the result is a structurally valid puzzle', () {
      expect(PourRules.isValid(ExtraBottle.add(base)), isTrue);
    });

    test('follows a non-default capacity', () {
      final six = PuzzleState([
        BottleModel(capacity: 6),
        BottleModel(capacity: 6),
      ]);
      expect(ExtraBottle.add(six).bottles.last.capacity, 6);
    });

    test('refuses an empty board and a board at the size limit', () {
      expect(ExtraBottle.canAdd(PuzzleState(const [])), isFalse);
      final big = PuzzleState([
        for (var i = 0; i < ExtraBottle.maxBottlesWithBooster; i++)
          BottleModel(),
      ]);
      expect(ExtraBottle.canAdd(big), isFalse);
      expect(() => ExtraBottle.add(big), throwsStateError);
      expect(() => ExtraBottle.add(PuzzleState(const [])), throwsStateError);
    });
  });

  group('winning rules are unchanged', () {
    test('an unused extra bottle does not stop a win', () {
      final done = PuzzleState.fromIds([
        [0, 0, 0, 0],
        [1, 1, 1, 1],
        [],
      ]);
      expect(PourRules.isCompleted(done), isTrue);
      expect(PourRules.isCompleted(ExtraBottle.add(done)), isTrue);
    });

    test('a half-full bottle still means "not solved", extra or not', () {
      final s = ExtraBottle.add(
        PuzzleState.fromIds([
          [0, 0, 0],
          [0, 1, 1, 1],
          [],
        ]),
      );
      expect(PourRules.isCompleted(s), isFalse);
    });

    test('the extra bottle can hold the finished colour', () {
      // Colour 1 ends up in the extra bottle; everything is still solved.
      final s = ExtraBottle.add(
        PuzzleState.fromIds([
          [0, 0, 0, 0],
          [1, 1, 1, 1],
        ]),
      );
      expect(PourRules.isCompleted(s), isTrue);
    });

    test('engine on a boosted board plays and wins like a normal one', () {
      final e = GameEngine(
        ExtraBottle.add(
          PuzzleState.fromIds([
            [0, 0, 0, 1],
            [1, 1, 1, 0],
            [],
          ]),
        ),
      );
      for (final m in const [(0, 2), (1, 0), (1, 2)]) {
        expect(e.applyMove(MoveModel(m.$1, m.$2)).isSuccess, isTrue);
      }
      expect(e.isLevelCompleted(), isTrue);
      expect(e.moveCount, 3);
    });
  });

  group('solver behaviour on a boosted board', () {
    test('a solvable level stays solvable, and never needs more moves', () {
      final gen = const LevelGenerator();
      for (final n in [1, 2, 3, 6, 10, 17, 25, 40, 80]) {
        final level = gen.generate(n);
        final plain = solver.solve(level.puzzle);
        final boosted = solver.solve(ExtraBottle.add(level.puzzle));
        expect(plain.isSolved, isTrue, reason: 'level $n');
        expect(boosted.isSolved, isTrue, reason: 'boosted level $n');
        expect(
          SolutionVerifier.verify(ExtraBottle.add(level.puzzle), boosted.moves),
          isTrue,
          reason: 'level $n: replaying the boosted solution must win',
        );
        if (plain.isOptimal && boosted.isOptimal) {
          expect(
            boosted.moves.length,
            lessThanOrEqualTo(plain.moves.length),
            reason: 'extra room cannot make the optimum longer (level $n)',
          );
        }
      }
    });

    test('a dead end becomes solvable with the extra bottle', () {
      // No empty bottle and mismatched tops: nothing can move.
      final stuck = PuzzleState.fromIds([
        [0, 0, 1, 1],
        [1, 1, 0, 0],
      ]);
      expect(PourRules.legalMoves(stuck), isEmpty);
      expect(solver.solve(stuck).status, SolverStatus.unsolvable);
      final rescued = ExtraBottle.add(stuck);
      final r = solver.solve(rescued);
      expect(r.isSolved, isTrue, reason: '$r');
      expect(SolutionVerifier.verify(rescued, r.moves), isTrue);
    });

    test('the counting proof of unsolvability still holds', () {
      // 3 units of colour 0 can never fill a bottle, extra bottle or not.
      final impossible = ExtraBottle.add(
        PuzzleState.fromIds([
          [0, 0, 0],
          [1, 1, 1, 1],
        ]),
      );
      expect(solver.solve(impossible).status, SolverStatus.unsolvable);
    });

    test('solution indices refer to the real bottles, extra one last', () {
      final level = const LevelGenerator().generate(30);
      final boosted = ExtraBottle.add(level.puzzle);
      final r = solver.solve(boosted);
      expect(r.isSolved, isTrue);
      final last = boosted.bottleCount - 1;
      for (final m in r.moves) {
        expect(m.source, inInclusiveRange(0, last));
        expect(m.destination, inInclusiveRange(0, last));
      }
    });
  });

  group('a recorded move list survives the booster', () {
    test('moves made before the booster replay identically after it', () {
      final level = const LevelGenerator().generate(12);
      final plain = GameEngine(level.puzzle);
      final moves = <MoveModel>[];
      for (var i = 0; i < 6; i++) {
        final legal = plain.getLegalMoves();
        if (legal.isEmpty) break;
        plain.applyMove(legal.first);
        moves.add(legal.first);
      }
      final boosted = GameEngine(ExtraBottle.add(level.puzzle));
      for (final m in moves) {
        expect(boosted.applyMove(m).isSuccess, isTrue);
      }
      for (var i = 0; i < plain.state.bottleCount; i++) {
        expect(boosted.state.bottles[i], plain.state.bottles[i]);
      }
      expect(boosted.state.bottles.last.isEmpty, isTrue);
    });
  });

  group('MoveResult.reversed (the picture of an undo)', () {
    test('swaps before/after and describes pouring back', () {
      final e = GameEngine(
        PuzzleState.fromIds([
          [0, 0, 1],
          [1],
          [],
        ]),
      );
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.isSuccess, isTrue);
      final back = r.reversed;
      expect(back.move, const MoveModel(1, 0));
      expect(back.quantity, r.quantity);
      expect(back.color, r.color);
      expect(back.previousState, r.resultingState);
      expect(back.resultingState, r.previousState);
      expect(back.sourceBefore, r.destinationAfter);
      expect(back.destinationAfter, r.sourceBefore);
    });
  });
}
