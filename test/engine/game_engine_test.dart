import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/engine/models/game_status.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/move_result.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';

PuzzleState s(List<List<int>> b, {int cap = 4}) =>
    PuzzleState.fromIds(b, capacity: cap);

List<List<int>> ids(PuzzleState st) => [
  for (final b in st.bottles) b.units.map((u) => u.id).toList(),
];

void main() {
  group('models', () {
    test('ColorUnit equality is by id', () {
      expect(const ColorUnit(1), const ColorUnit(1));
      expect(const ColorUnit(1), isNot(const ColorUnit(2)));
    });

    test('default capacity is 4', () {
      expect(BottleModel().capacity, 4);
    });

    test('bottle units list is unmodifiable', () {
      final b = BottleModel(units: [const ColorUnit(1)]);
      expect(() => b.units.add(const ColorUnit(2)), throwsUnsupportedError);
    });

    test('topGroupSize counts contiguous top colour only', () {
      expect(
        s([
          [1, 2, 2, 2],
        ]).bottles[0].topGroupSize,
        3,
      );
      expect(
        s([
          [2, 1, 2],
        ]).bottles[0].topGroupSize,
        1,
      );
      expect(s([[]]).bottles[0].topGroupSize, 0);
    });

    test('state equality is structural', () {
      expect(
        s([
          [1],
          [],
        ]),
        s([
          [1],
          [],
        ]),
      );
      expect(
        s([
          [1],
          [],
        ]),
        isNot(
          s([
            [],
            [1],
          ]),
        ),
      );
    });
  });

  group('empty source', () {
    test('cannot pour, no change', () {
      final e = GameEngine(
        s([
          [],
          [1],
        ]),
      );
      expect(e.canPour(0, 1), isFalse);
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.failure, MoveFailure.sourceEmpty);
      expect(ids(e.state), [
        [],
        [1],
      ]);
      expect(e.moveCount, 0);
    });
  });

  group('full destination', () {
    test('rejected even with matching colour', () {
      final e = GameEngine(
        s([
          [1],
          [1, 1, 1, 1],
        ]),
      );
      expect(e.canPour(0, 1), isFalse);
      expect(e.getAvailableSpace(1), 0);
      expect(
        e.applyMove(const MoveModel(0, 1)).failure,
        MoveFailure.destinationFull,
      );
      expect(ids(e.state), [
        [1],
        [1, 1, 1, 1],
      ]);
    });
  });

  group('matching colours', () {
    test('pours onto same top colour', () {
      final e = GameEngine(
        s([
          [2, 1],
          [3, 1],
        ]),
      );
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.isSuccess, isTrue);
      expect(ids(e.state), [
        [2],
        [3, 1, 1],
      ]);
    });

    test('pours into empty bottle', () {
      final e = GameEngine(
        s([
          [2, 1],
          [],
        ]),
      );
      e.applyMove(const MoveModel(0, 1));
      expect(ids(e.state), [
        [2],
        [1],
      ]);
    });
  });

  group('different colours', () {
    test('rejected with colorMismatch', () {
      final e = GameEngine(
        s([
          [1],
          [2],
        ]),
      );
      expect(e.canPour(0, 1), isFalse);
      expect(
        e.applyMove(const MoveModel(0, 1)).failure,
        MoveFailure.colorMismatch,
      );
      expect(ids(e.state), [
        [1],
        [2],
      ]);
    });
  });

  group('multiple same-colour top units', () {
    test('whole group moves at once', () {
      final e = GameEngine(
        s([
          [2, 1, 1, 1],
          [],
        ]),
      );
      expect(e.getPourableUnits(0, 1), 3);
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.quantity, 3);
      expect(ids(e.state), [
        [2],
        [1, 1, 1],
      ]);
    });

    test('only the top group moves, not same colour below a gap', () {
      final e = GameEngine(
        s([
          [1, 2, 1],
          [],
        ]),
      );
      e.applyMove(const MoveModel(0, 1));
      expect(ids(e.state), [
        [1, 2],
        [1],
      ]);
    });
  });

  group('partial transfer', () {
    test('limited by destination space', () {
      final e = GameEngine(
        s([
          [2, 1, 1, 1],
          [1, 1],
        ]),
      );
      // destination holds 2 -> space 2, group 3 -> moves 2
      expect(e.getAvailableSpace(1), 2);
      expect(e.getPourableUnits(0, 1), 2);
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.quantity, 2);
      expect(ids(e.state), [
        [2, 1],
        [1, 1, 1, 1],
      ]);
    });

    test('almost-full destination takes one unit', () {
      final e = GameEngine(
        s([
          [1, 1],
          [1, 1, 1],
        ]),
      );
      expect(e.applyMove(const MoveModel(0, 1)).quantity, 1);
      expect(ids(e.state), [
        [1],
        [1, 1, 1, 1],
      ]);
    });

    test('respects non-default capacity', () {
      final e = GameEngine(
        s([
          [1, 1, 1],
          [1, 1, 1, 1],
        ], cap: 5),
      );
      expect(e.applyMove(const MoveModel(0, 1)).quantity, 1);
    });
  });

  group('invalid moves', () {
    test('same bottle', () {
      final e = GameEngine(
        s([
          [1],
          [],
        ]),
      );
      final r = e.applyMove(const MoveModel(0, 0));
      expect(r.failure, MoveFailure.sameBottle);
      expect(ids(e.state), [
        [1],
        [],
      ]);
    });

    test('out-of-range indices', () {
      final e = GameEngine(
        s([
          [1],
          [],
        ]),
      );
      for (final m in const [
        MoveModel(-1, 0),
        MoveModel(0, 2),
        MoveModel(5, 5),
      ]) {
        expect(e.applyMove(m).failure, MoveFailure.invalidIndex);
      }
      expect(e.getAvailableSpace(9), 0);
      expect(e.getPourableUnits(0, 9), 0);
      expect(e.moveCount, 0);
    });

    test('failure result carries unchanged state and no payload', () {
      final e = GameEngine(
        s([
          [1],
          [2],
        ]),
      );
      final before = e.state;
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.isSuccess, isFalse);
      expect(r.quantity, 0);
      expect(r.color, isNull);
      expect(r.previousState, before);
      expect(r.resultingState, before);
      expect(identical(e.state, before), isTrue);
    });

    test('failed move does not add undo history', () {
      final e = GameEngine(
        s([
          [1],
          [2],
        ]),
      );
      e.applyMove(const MoveModel(0, 1));
      expect(e.canUndo, isFalse);
      expect(e.undoMove(), isNull);
    });
  });

  group('move result data', () {
    test('contains everything the animation layer needs', () {
      final e = GameEngine(
        s([
          [2, 1, 1],
          [1],
        ]),
      );
      final before = e.state;
      final r = e.applyMove(const MoveModel(0, 1));
      expect(r.sourceIndex, 0);
      expect(r.destinationIndex, 1);
      expect(r.color, const ColorUnit(1));
      expect(r.quantity, 2);
      expect(r.sourceBefore, before.bottles[0]);
      expect(r.destinationBefore, before.bottles[1]);
      expect(ids(PuzzleState([r.sourceAfter!, r.destinationAfter!])), [
        [2],
        [1, 1, 1],
      ]);
      expect(r.previousState, before);
      expect(r.resultingState, e.state);
    });

    test('states are immutable snapshots (old state unaffected)', () {
      final e = GameEngine(
        s([
          [1],
          [],
        ]),
      );
      final before = e.state;
      e.applyMove(const MoveModel(0, 1));
      expect(ids(before), [
        [1],
        [],
      ]);
      expect(ids(e.state), [
        [],
        [1],
      ]);
    });
  });

  group('legal moves', () {
    test('lists exactly the legal pours', () {
      final e = GameEngine(
        s([
          [1],
          [1, 2],
          [],
        ]),
      );
      expect(e.getLegalMoves(), [const MoveModel(0, 2), const MoveModel(1, 2)]);
      for (final m in e.getLegalMoves()) {
        expect(e.canPour(m.source, m.destination), isTrue);
      }
    });

    test('none when stuck', () {
      final e = GameEngine(
        s([
          [1, 2],
          [2, 1],
        ]),
      );
      expect(e.getLegalMoves(), isEmpty);
      expect(e.status, GameStatus.stuck);
    });
  });

  group('win detection', () {
    test('solved when non-empty bottles are full and uniform', () {
      expect(
        GameEngine(
          s([
            [1, 1, 1, 1],
            [2, 2, 2, 2],
            [],
          ]),
        ).isLevelCompleted(),
        isTrue,
      );
    });

    test('not solved if a bottle is partial', () {
      expect(
        GameEngine(
          s([
            [1, 1, 1],
            [1],
            [],
          ]),
        ).isLevelCompleted(),
        isFalse,
      );
    });

    test('not solved if a bottle is mixed', () {
      expect(
        GameEngine(
          s([
            [1, 1, 2, 2],
          ]),
        ).isLevelCompleted(),
        isFalse,
      );
    });

    test('all empty counts as completed', () {
      expect(GameEngine(s([[], []])).isLevelCompleted(), isTrue);
    });

    test('final pour completes the level', () {
      final e = GameEngine(
        s([
          [1, 1, 1],
          [1],
          [2, 2, 2, 2],
        ]),
      );
      expect(e.status, GameStatus.inProgress);
      e.applyMove(const MoveModel(1, 0));
      expect(e.isLevelCompleted(), isTrue);
      expect(e.status, GameStatus.completed);
    });
  });

  group('undo / reset', () {
    test('undo restores exact previous state and returns the move', () {
      final e = GameEngine(
        s([
          [2, 1, 1],
          [1],
        ]),
      );
      final start = e.state;
      final r = e.applyMove(const MoveModel(0, 1));
      final undone = e.undoMove();
      expect(undone, same(r));
      expect(e.state, start);
      expect(e.moveCount, 0);
    });

    test('multiple undos unwind in order', () {
      final e = GameEngine(
        s([
          [2, 1],
          [1],
          [],
        ]),
      );
      final s0 = e.state;
      e.applyMove(const MoveModel(0, 1));
      final s1 = e.state;
      e.applyMove(const MoveModel(0, 2));
      expect(e.moveCount, 2);
      e.undoMove();
      expect(e.state, s1);
      e.undoMove();
      expect(e.state, s0);
      expect(e.undoMove(), isNull);
    });

    test('undo after completion returns to in-progress', () {
      final e = GameEngine(
        s([
          [1, 1, 1],
          [1],
        ]),
      );
      e.applyMove(const MoveModel(1, 0));
      expect(e.status, GameStatus.completed);
      e.undoMove();
      expect(e.status, GameStatus.inProgress);
    });

    test('resetLevel restores initial state and clears history', () {
      final e = GameEngine(
        s([
          [2, 1],
          [1],
          [],
        ]),
      );
      final init = e.state;
      e.applyMove(const MoveModel(0, 1));
      e.applyMove(const MoveModel(0, 2));
      e.resetLevel();
      expect(e.state, init);
      expect(e.moveCount, 0);
      expect(e.canUndo, isFalse);
    });

    test('history is unmodifiable', () {
      final e = GameEngine(
        s([
          [1],
          [],
        ]),
      );
      e.applyMove(const MoveModel(0, 1));
      expect(() => e.history.clear(), throwsUnsupportedError);
    });
  });

  group('state invariants', () {
    test('isStateValid true for fresh and played states', () {
      final e = GameEngine(
        s([
          [1, 2, 1, 2],
          [2, 1, 2, 1],
          [],
          [],
        ]),
      );
      expect(e.isStateValid(), isTrue);
    });

    test('overfilled / zero-capacity bottles are invalid', () {
      final over = PuzzleState([
        BottleModel(
          capacity: 2,
          units: const [ColorUnit(1), ColorUnit(1), ColorUnit(1)],
        ),
      ]);
      expect(over.bottles[0].isValid, isFalse);
      expect(BottleModel(capacity: 0).isValid, isFalse);
      expect(() => GameEngine(over), throwsA(isA<AssertionError>()));
    });

    test('random playouts preserve invariants', () {
      // Deterministic pseudo-random walk over many moves + undos.
      var seed = 12345;
      int next(int n) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed % n;
      }

      final e = GameEngine(
        s([
          [1, 2, 3, 1],
          [2, 3, 1, 2],
          [3, 1, 2, 3],
          [],
          [],
        ]),
      );
      final totals = e.state.colorCounts;
      for (var i = 0; i < 500; i++) {
        final legal = e.getLegalMoves();
        if (legal.isEmpty || next(10) == 0) {
          if (e.canUndo) e.undoMove();
        } else {
          final m = legal[next(legal.length)];
          final r = e.applyMove(m);
          expect(r.isSuccess, isTrue);
          expect(r.quantity, inInclusiveRange(1, 4));
        }
        expect(e.isStateValid(), isTrue);
        expect(e.state.colorCounts, totals, reason: 'units conserved');
      }
    });

    test('every legal move succeeds, every non-legal move fails', () {
      final e = GameEngine(
        s([
          [1, 2],
          [2],
          [1, 1],
          [],
          [3, 3, 3, 3],
        ]),
      );
      final legal = e.getLegalMoves().toSet();
      for (var i = -1; i <= e.state.bottleCount; i++) {
        for (var j = -1; j <= e.state.bottleCount; j++) {
          final probe = GameEngine(e.initialState);
          final ok = probe.applyMove(MoveModel(i, j)).isSuccess;
          expect(ok, legal.contains(MoveModel(i, j)), reason: '$i->$j');
        }
      }
    });
  });
}
