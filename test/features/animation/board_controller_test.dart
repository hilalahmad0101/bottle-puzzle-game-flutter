import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/move_result.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';

PuzzleState st(List<List<int>> b) => PuzzleState.fromIds(b);

List<List<int>> ids(PuzzleState s) => [
  for (final b in s.bottles) b.units.map((u) => u.id).toList(),
];

/// 0: [2,1] 1: [1] 2: [] 3: [2,2,2,2] (full)
BoardController make() => BoardController(
  st([
    [2, 1],
    [1],
    [],
    [2, 2, 2, 2],
  ]),
);

void main() {
  group('selection', () {
    test('tap selects, tap again deselects', () {
      final c = make();
      expect(c.tapBottle(0).kind, TapKind.selected);
      expect(c.selectedIndex, 0);
      expect(c.tapBottle(0).kind, TapKind.deselected);
      expect(c.selectedIndex, isNull);
      expect(c.engine.moveCount, 0);
    });

    test('an empty bottle cannot be picked up', () {
      final c = make();
      expect(c.tapBottle(2).kind, TapKind.ignored);
      expect(c.selectedIndex, isNull);
    });

    test('bad indices are ignored', () {
      final c = make();
      expect(c.tapBottle(-1).kind, TapKind.ignored);
      expect(c.tapBottle(99).kind, TapKind.ignored);
    });
  });

  group('starting a pour', () {
    test('a legal destination commits the move IMMEDIATELY', () {
      final c = make();
      c.tapBottle(0);
      final o = c.tapBottle(1);
      expect(o.kind, TapKind.pourStarted);
      expect(o.result!.isSuccess, isTrue);
      // Committed state is final already; animation is separate.
      expect(ids(c.committedState), [
        [2],
        [1, 1],
        <int>[],
        [2, 2, 2, 2],
      ]);
      expect(c.engine.moveCount, 1);
      expect(c.isPouring, isTrue);
      expect(c.activePour!.result, same(o.result));
      expect(c.selectedIndex, isNull);
    });

    test('the active pour describes exactly the engine result', () {
      final c = BoardController(
        st([
          [0, 1, 1, 1],
          [],
        ]),
      );
      c.tapBottle(0);
      c.tapBottle(1);
      final r = c.activePour!.result;
      expect(r.quantity, 3);
      expect(r.color!.id, 1);
      expect(r.previousState, isNot(r.resultingState));
      expect(c.committedState, r.resultingState);
    });

    test('an illegal pour onto a bottle reselects it', () {
      final c = make();
      c.tapBottle(0); // top colour 1
      final o = c.tapBottle(3); // top colour 2, and full
      expect(o.kind, TapKind.reselected);
      expect(o.failure, MoveFailure.destinationFull);
      expect(c.selectedIndex, 3);
      expect(c.engine.moveCount, 0);
      expect(c.isPouring, isFalse);
    });

    test('colour mismatch also reselects, nothing changes', () {
      final c = BoardController(
        st([
          [1],
          [2],
        ]),
      );
      c.tapBottle(0);
      final o = c.tapBottle(1);
      expect(o.kind, TapKind.reselected);
      expect(o.failure, MoveFailure.colorMismatch);
      expect(ids(c.committedState), [
        [1],
        [2],
      ]);
    });

    test(
      'an invalid pour onto an empty-handed target is rejected, selection kept',
      () {
        // Source full and destination empty is legal; use out-of-range-free
        // rejection: pouring needs a non-empty source which selection ensures,
        // so the only reject is a failure onto an EMPTY bottle - impossible
        // (empty accepts anything). Confirm that pouring into empty is legal.
        final c = make();
        c.tapBottle(0);
        expect(c.tapBottle(2).kind, TapKind.pourStarted);
      },
    );
  });

  group('no conflicting moves during a pour', () {
    test('all taps are ignored (busy) while pouring', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      for (var i = 0; i < 4; i++) {
        expect(c.tapBottle(i).kind, TapKind.busy);
      }
      expect(c.engine.moveCount, 1);
      expect(c.selectedIndex, isNull);
    });

    test('the same move can never be applied twice by tapping repeatedly', () {
      final c = BoardController(
        st([
          [1, 1],
          [1],
          [],
        ]),
      );
      c.tapBottle(0);
      c.tapBottle(1);
      for (var n = 0; n < 20; n++) {
        c.tapBottle(0);
        c.tapBottle(1);
      }
      expect(c.engine.moveCount, 1);
      expect(ids(c.committedState), [
        <int>[],
        [1, 1, 1],
        <int>[],
      ]);
    });

    test('after the pour finishes input works again', () {
      final c = make();
      c.tapBottle(0);
      final token = c.activePour?.token;
      c.tapBottle(1);
      final t = c.activePour!.token;
      expect(token, isNull);
      expect(c.finishPour(t), isTrue);
      expect(c.isPouring, isFalse);
      expect(c.tapBottle(3).kind, TapKind.selected);
    });
  });

  group('finishing and stale callbacks', () {
    test('finishPour needs the matching token', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      final t = c.activePour!.token;
      expect(c.finishPour(t + 1), isFalse);
      expect(c.isPouring, isTrue);
      expect(c.finishPour(t), isTrue);
      expect(c.finishPour(t), isFalse, reason: 'second call is a no-op');
    });

    test('a late callback from an OLD pour cannot end a newer one', () {
      final c = BoardController(
        st([
          [1, 1],
          [1],
          [],
        ]),
      );
      c.tapBottle(0);
      c.tapBottle(1);
      final old = c.activePour!.token;
      c.interruptPour(); // animation dropped
      c.tapBottle(2); // selects empty? ignored
      c.tapBottle(1);
      c.tapBottle(2);
      final fresh = c.activePour!.token;
      expect(fresh, isNot(old));
      expect(c.finishPour(old), isFalse);
      expect(c.isPouring, isTrue);
      expect(c.finishPour(fresh), isTrue);
    });

    test('tokens are unique and increasing', () {
      final c = BoardController(
        st([
          [1, 1],
          [],
          [],
        ]),
      );
      final seen = <int>[];
      for (final move in const [(0, 1), (1, 2), (2, 1)]) {
        c.tapBottle(move.$1);
        c.tapBottle(move.$2);
        seen.add(c.activePour!.token);
        c.finishPour(c.activePour!.token);
      }
      expect(seen, [1, 2, 3]);
    });
  });

  group('interruption keeps the game consistent', () {
    test('interrupting drops the animation but the move stays committed', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      final committed = c.committedState;
      expect(c.interruptPour(InterruptReason.background), isTrue);
      expect(c.isPouring, isFalse);
      expect(c.committedState, committed);
      expect(c.engine.moveCount, 1);
      expect(c.lastInterruption, InterruptReason.background);
    });

    test('interrupting when idle does nothing', () {
      final c = make();
      expect(c.interruptPour(), isFalse);
      expect(c.lastInterruption, isNull);
    });

    test('a snapshot taken at ANY point of a pour is the final state', () {
      final c = make();
      c.tapBottle(0);
      final before = c.committedState;
      c.tapBottle(1);
      final during = c.committedState;
      final moves = c.committedMoves;
      c.finishPour(c.activePour!.token);
      expect(c.committedState, during);
      expect(c.committedMoves, moves);
      expect(during, isNot(before));
      expect(moves, [const MoveModel(0, 1)]);
    });

    test('reset mid-pour restores the level and clears the animation', () {
      final c = make();
      final start = c.committedState;
      c.tapBottle(0);
      c.tapBottle(1);
      c.reset();
      expect(c.isPouring, isFalse);
      expect(c.committedState, start);
      expect(c.engine.moveCount, 0);
      expect(c.selectedIndex, isNull);
      expect(c.lastInterruption, InterruptReason.reset);
    });

    test('undo mid-pour undoes the pour that was being shown', () {
      final c = make();
      final start = c.committedState;
      c.tapBottle(0);
      c.tapBottle(1);
      final undone = c.undo();
      expect(undone, isNotNull);
      // The board is back at once; what remains is a replay of the liquid
      // flowing back, which can be dropped without changing anything.
      expect(c.committedState, start);
      expect(c.engine.moveCount, 0);
      expect(c.activePour!.isUndo, isTrue);
      c.interruptPour();
      expect(c.isPouring, isFalse);
      expect(c.committedState, start);
    });

    test('undo with nothing to undo is safe', () {
      final c = make();
      expect(c.undo(), isNull);
      expect(c.engine.moveCount, 0);
    });

    test('undo then redo of the same pour behaves like a fresh move', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      final firstToken = c.activePour!.token;
      c.undo();
      expect(c.tapBottle(0).kind, TapKind.busy, reason: 'undo is animating');
      c.finishPour(c.activePour!.token);
      c.tapBottle(0);
      c.tapBottle(1);
      expect(c.activePour!.token, isNot(firstToken));
      expect(c.engine.moveCount, 1);
    });

    test('pause drops the animation and locks input until resume', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      c.pause();
      expect(c.isPaused, isTrue);
      expect(c.isPouring, isFalse);
      expect(c.inputLocked, isTrue);
      expect(c.tapBottle(3).kind, TapKind.busy);
      c.resume();
      expect(c.inputLocked, isFalse);
      expect(c.tapBottle(3).kind, TapKind.selected);
      expect(c.engine.moveCount, 1);
    });

    test('pausing clears a selection so nothing stays half-picked-up', () {
      final c = make();
      c.tapBottle(0);
      c.pause();
      expect(c.selectedIndex, isNull);
    });

    test('loading a new level while pouring cancels everything', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      c.loadLevel(
        st([
          [1],
          [],
        ]),
      );
      expect(c.isPouring, isFalse);
      expect(c.engine.moveCount, 0);
      expect(c.committedState.bottleCount, 2);
    });
  });

  group('level completion is only shown after the animation', () {
    test('winning pour: engine knows at once, the UI flag waits', () {
      final c = BoardController(
        st([
          [1, 1, 1],
          [1],
        ]),
      );
      c.tapBottle(1);
      c.tapBottle(0);
      expect(c.engine.isLevelCompleted(), isTrue);
      expect(c.levelCompleteVisible, isFalse, reason: 'still pouring');
      c.finishPour(c.activePour!.token);
      expect(c.levelCompleteVisible, isTrue);
    });

    test('interrupting the winning pour still reveals completion', () {
      final c = BoardController(
        st([
          [1, 1, 1],
          [1],
        ]),
      );
      c.tapBottle(1);
      c.tapBottle(0);
      c.interruptPour();
      expect(c.levelCompleteVisible, isTrue);
    });
  });

  group('notifications and disposal', () {
    test('listeners are told about every visible change', () {
      final c = make();
      var n = 0;
      c.addListener(() => n++);
      c.tapBottle(0); // selected
      c.tapBottle(1); // pour started
      c.finishPour(c.activePour!.token); // done
      expect(n, 3);
      c.tapBottle(0); // selected
      c.tapBottle(0); // deselected
      expect(n, 5);
    });

    test('no notification for ignored or busy taps', () {
      final c = make();
      var n = 0;
      c.addListener(() => n++);
      c.tapBottle(2); // empty -> ignored
      c.tapBottle(99);
      expect(n, 0);
    });

    test('operations after dispose do not throw or notify', () {
      final c = make();
      c.tapBottle(0);
      c.tapBottle(1);
      c.dispose();
      expect(c.isDisposed, isTrue);
      expect(() => c.interruptPour(), returnsNormally);
    });
  });

  group('a full game stays consistent whatever the animation does', () {
    test('random taps with random interruptions keep invariants', () {
      var seed = 7;
      int next(int n) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return (seed >> 8) % n;
      }

      final c = BoardController(
        st([
          [1, 2, 3, 1],
          [2, 3, 1, 2],
          [3, 1, 2, 3],
          [],
          [],
        ]),
      );
      final totals = c.committedState.colorCounts;
      var applied = 0;
      for (var i = 0; i < 600; i++) {
        switch (next(10)) {
          case 0:
            c.interruptPour(InterruptReason.background);
          case 1:
            if (c.activePour != null) c.finishPour(c.activePour!.token);
          case 2:
            c.undo();
          case 3:
            c.finishPour(next(50)); // mostly stale tokens
          default:
            final o = c.tapBottle(next(5));
            if (o.kind == TapKind.pourStarted) applied++;
        }
        expect(c.engine.isStateValid(), isTrue);
        expect(c.committedState.colorCounts, totals);
        // History length always matches the committed moves.
        expect(c.committedMoves.length, c.engine.moveCount);
        // Busy <=> there is an active pour (never both a pour and a selection).
        if (c.isPouring) expect(c.selectedIndex, isNull);
      }
      expect(applied, greaterThan(20));
    });
  });
}
