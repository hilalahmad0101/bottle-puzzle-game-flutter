import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/difficulty.dart';
import 'package:prism_pour/engine/generator/generated_level.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/move_result.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/engine/solver/solver_config.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';

import '../../support/test_app.dart';

// Tutorial level 1: [[0,0,0,1],[1,1,1,0],[]], optimal 0>2, 1>0, 1>2.
const _level1 = [(0, 2), (1, 0), (1, 2)];

PuzzleState _board() => PuzzleState.fromIds([
  [0, 0, 1, 1],
  [1, 1, 0, 0],
  [],
  [],
]);

/// Plays a legal pour and lets its animation finish.
void _play(BoardController b, int from, int to) {
  b.tapBottle(from);
  final o = b.tapBottle(to);
  expect(o.kind, TapKind.pourStarted, reason: '$from -> $to must be legal');
  b.finishPour(b.activePour!.token);
}

void _play2(GameSession s, int from, int to) => _play(s.board!, from, to);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  // ---------------------------------------------------------------- UNDO
  group('undo', () {
    test('restores the exact bottle contents of the previous position', () {
      final c = BoardController(_board());
      final before = c.committedState;
      _play(c, 0, 2);
      final after = c.committedState;
      expect(after, isNot(before));
      c.undo();
      expect(c.committedState, before);
      expect(c.committedState.bottles[0].units, before.bottles[0].units);
      expect(c.committedState.bottles[2].isEmpty, isTrue);
    });

    test('several consecutive undos walk back through every position', () {
      final c = BoardController(_board());
      final states = [c.committedState];
      for (final m in const [(0, 2), (1, 3), (2, 1), (3, 0)]) {
        _play(c, m.$1, m.$2);
        states.add(c.committedState);
      }
      expect(c.engine.moveCount, 4);
      for (var i = states.length - 2; i >= 0; i--) {
        expect(c.undo(), isNotNull);
        c.interruptPour(); // the undo animation is only a picture
        expect(c.committedState, states[i], reason: 'after undo to #$i');
        expect(c.engine.moveCount, i);
      }
      expect(c.undo(), isNull, reason: 'nothing left to undo');
      expect(c.committedState, states.first);
    });

    test('undo is repeatable without waiting for the animation', () {
      final c = BoardController(_board());
      final start = c.committedState;
      _play(c, 0, 2);
      _play(c, 1, 3);
      c.undo();
      expect(c.isPouring, isTrue);
      c.undo(); // pressed again while the first undo is still showing
      expect(c.engine.moveCount, 0);
      expect(c.committedState, start);
      expect(c.activePour!.isUndo, isTrue);
      c.finishPour(c.activePour!.token);
      expect(c.isPouring, isFalse);
    });

    test('undo hands back the move it reverted', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      final undone = c.undo()!;
      expect(undone.move, const MoveModel(0, 2));
      expect(undone.isSuccess, isTrue);
    });

    test('the undo animation is a reversed pour of the same liquid', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      final forward = c.engine.history.single;
      c.undo();
      final ap = c.activePour!;
      expect(ap.isUndo, isTrue);
      expect(ap.result.move, const MoveModel(2, 0));
      expect(ap.result.quantity, forward.quantity);
      expect(ap.result.color, forward.color);
    });

    test('an interrupted undo animation leaves the undone position', () {
      final c = BoardController(_board());
      final start = c.committedState;
      _play(c, 0, 2);
      c.undo();
      expect(c.interruptPour(InterruptReason.background), isTrue);
      expect(c.committedState, start);
      expect(c.engine.moveCount, 0);
      expect(c.isPouring, isFalse);
    });

    test('input is ignored while the undo shows, then works again', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      c.undo();
      expect(c.tapBottle(0).kind, TapKind.busy);
      c.finishPour(c.activePour!.token);
      expect(c.tapBottle(0).kind, TapKind.selected);
    });

    test('undo drops the current selection', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      c.tapBottle(1);
      expect(c.selectedIndex, 1);
      c.undo();
      expect(c.selectedIndex, isNull);
    });

    test('undo mid-pour reverts the pour that was still showing', () {
      final c = BoardController(_board());
      final start = c.committedState;
      c.tapBottle(0);
      c.tapBottle(2); // animating
      c.undo();
      expect(c.committedState, start);
      expect(c.activePour!.isUndo, isTrue);
    });
  });

  // ------------------------------------------------------------ MOVE COUNT
  group('move counter', () {
    test('counts successful pours only', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      _play(c, 1, 3);
      expect(c.engine.moveCount, 2);
    });

    test('selecting and deselecting is not a move', () {
      final c = BoardController(_board());
      c.tapBottle(0);
      c.tapBottle(0);
      expect(c.engine.moveCount, 0);
    });

    test('tapping an empty bottle first is not a move', () {
      final c = BoardController(_board());
      expect(c.tapBottle(2).kind, TapKind.ignored);
      expect(c.engine.moveCount, 0);
    });

    test('an illegal pour (colour mismatch) is rejected and not counted', () {
      final start = PuzzleState.fromIds([
        [0, 0, 1],
        [1, 0],
        [],
        [],
      ]);
      final c = BoardController(start);
      c.tapBottle(0);
      final o = c.tapBottle(1);
      expect(o.kind, TapKind.reselected);
      expect(o.failure, MoveFailure.colorMismatch);
      expect(c.engine.moveCount, 0);
      expect(c.committedState, start);
    });

    test('pouring into a full bottle is not counted', () {
      final c = BoardController(
        PuzzleState.fromIds([
          [0, 0, 0, 0],
          [0],
          [],
        ]),
      );
      c.tapBottle(1);
      final o = c.tapBottle(0);
      expect(o.failure, MoveFailure.destinationFull);
      expect(c.engine.moveCount, 0);
    });

    test(
      'taps while a pour animates or the game is paused are not counted',
      () {
        final c = BoardController(_board());
        c.tapBottle(0);
        c.tapBottle(2);
        expect(c.engine.moveCount, 1);
        expect(c.tapBottle(1).kind, TapKind.busy);
        expect(c.tapBottle(3).kind, TapKind.busy);
        expect(c.engine.moveCount, 1);
        c.finishPour(c.activePour!.token);
        c.pause();
        expect(c.tapBottle(1).kind, TapKind.busy);
        expect(c.engine.moveCount, 1);
      },
    );

    test('out-of-range taps are ignored', () {
      final c = BoardController(_board());
      expect(c.tapBottle(-1).kind, TapKind.ignored);
      expect(c.tapBottle(99).kind, TapKind.ignored);
      expect(c.engine.moveCount, 0);
    });

    test('undo takes the count back, a new move counts again', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      _play(c, 1, 3);
      c.undo();
      c.interruptPour();
      expect(c.engine.moveCount, 1);
      _play(c, 1, 3);
      expect(c.engine.moveCount, 2);
    });
  });

  // ------------------------------------------------------------------ PAUSE
  group('pause', () {
    test('locks the board, keeps every move, resumes consistently', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      final state = c.committedState;
      c.tapBottle(1); // selected
      c.pause();
      expect(c.isPaused, isTrue);
      expect(c.inputLocked, isTrue);
      expect(c.selectedIndex, isNull, reason: 'no half-made move survives');
      expect(c.tapBottle(0).kind, TapKind.busy);
      expect(c.committedState, state);
      c.resume();
      expect(c.isPaused, isFalse);
      expect(c.committedState, state);
      expect(c.engine.moveCount, 1);
      expect(c.tapBottle(1).kind, TapKind.selected);
    });

    test('pausing and resuming twice is harmless', () {
      final c = BoardController(_board());
      c.pause();
      c.pause();
      expect(c.isPaused, isTrue);
      c.resume();
      c.resume();
      expect(c.isPaused, isFalse);
      expect(c.tapBottle(0).kind, TapKind.selected);
    });

    test('pausing during a pour drops only the replay, not the move', () {
      final c = BoardController(_board());
      c.tapBottle(0);
      c.tapBottle(2);
      c.pause();
      expect(c.isPouring, isFalse);
      expect(c.engine.moveCount, 1);
      expect(c.committedState.bottles[2].isEmpty, isFalse);
    });
  });

  // ---------------------------------------------------------------- RESTART
  group('restart (controller)', () {
    test('returns to the original layout and clears history and selection', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      _play(c, 1, 3);
      c.tapBottle(0);
      c.reset();
      expect(c.committedState, _board());
      expect(c.engine.moveCount, 0);
      expect(c.engine.canUndo, isFalse);
      expect(c.selectedIndex, isNull);
      expect(c.isPouring, isFalse);
    });

    test('reset during a pour is safe', () {
      final c = BoardController(_board());
      c.tapBottle(0);
      c.tapBottle(2);
      c.reset();
      expect(c.committedState, _board());
      expect(c.isPouring, isFalse);
    });

    test('the level can be played again after a restart', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      c.reset();
      _play(c, 0, 2);
      expect(c.engine.moveCount, 1);
    });
  });

  // ---------------------------------------------------------- BOOSTER (ctrl)
  group('extra bottle (controller)', () {
    test('adds one empty bottle at the end, keeping moves and undo', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      _play(c, 1, 3);
      final before = c.committedState;
      expect(c.canAddExtraBottle, isTrue);
      expect(c.addExtraBottle(), isTrue);
      expect(c.boosted, isTrue);
      final after = c.committedState;
      expect(after.bottleCount, before.bottleCount + 1);
      for (var i = 0; i < before.bottleCount; i++) {
        expect(after.bottles[i], before.bottles[i]);
      }
      expect(after.bottles.last.isEmpty, isTrue);
      expect(c.engine.moveCount, 2);
      expect(c.committedMoves, const [MoveModel(0, 2), MoveModel(1, 3)]);
      // The undo history still works across the booster.
      c.undo();
      c.interruptPour();
      expect(c.engine.moveCount, 1);
      expect(c.committedState.bottleCount, 5, reason: 'the bottle stays');
    });

    test('can be used only once per attempt', () {
      final c = BoardController(_board());
      expect(c.addExtraBottle(), isTrue);
      final s = c.committedState;
      expect(c.canAddExtraBottle, isFalse);
      expect(c.addExtraBottle(), isFalse);
      expect(c.committedState, s);
    });

    test('the new bottle takes part in play', () {
      final c = BoardController(_board());
      c.addExtraBottle();
      _play(c, 0, 4); // pour into the extra bottle
      expect(c.committedState.bottles.last.isEmpty, isFalse);
      expect(c.engine.moveCount, 1);
    });

    test('restart removes it: the level is dealt as originally', () {
      final c = BoardController(_board());
      _play(c, 0, 2);
      c.addExtraBottle();
      c.reset();
      expect(c.boosted, isFalse);
      expect(c.committedState, _board());
      expect(c.canAddExtraBottle, isTrue);
    });

    test('a controller can start boosted (restoring a saved game)', () {
      final c = BoardController(_board(), boosted: true);
      expect(c.boosted, isTrue);
      expect(c.committedState.bottleCount, 5);
      expect(c.originalState, _board());
    });

    test('using it mid-pour drops the replay but keeps the move', () {
      final c = BoardController(_board());
      c.tapBottle(0);
      c.tapBottle(2);
      expect(c.addExtraBottle(), isTrue);
      expect(c.isPouring, isFalse);
      expect(c.engine.moveCount, 1);
    });

    test('a standard controller is untouched by the feature', () {
      final c = BoardController(_board());
      expect(c.boosted, isFalse);
      expect(c.committedState, _board());
      expect(c.committedState.bottleCount, 4);
    });
  });

  // ------------------------------------------------------------- SESSION
  group('session', () {
    late MemoryProgressRepository repo;
    late ProviderContainer c;
    late GameSession s;
    late RecordingFeedback fb;

    Future<void> setUpSession({
      PlayerProgress? progress,
      AppSettings? settings,
      LevelLoader? loader,
      MemoryProgressRepository? repository,
    }) async {
      repo =
          repository ??
          MemoryProgressRepository(progress: progress, settings: settings);
      fb = RecordingFeedback();
      c = await readyContainer(repo: repo, feedback: fb, levelLoader: loader);
      addTearDown(c.dispose);
      s = c.read(gameSessionProvider);
    }

    const boosterOn = AppSettings(extraBottleBooster: true);

    group('undo', () {
      test('is unavailable at the start and available after a move', () async {
        await setUpSession();
        await s.startLevel(1);
        expect(s.canUndo, isFalse);
        expect(s.whyUnavailable(GameAction.undo), 'Nothing to undo yet.');
        _play2(s, 0, 2);
        expect(s.canUndo, isTrue);
        expect(s.whyUnavailable(GameAction.undo), isNull);
      });

      test('restores the board and the HUD move count', () async {
        await setUpSession();
        await s.startLevel(1);
        final start = s.board!.committedState;
        _play2(s, 0, 2);
        _play2(s, 1, 0);
        expect(s.moves, 2);
        s.undo();
        expect(s.moves, 1);
        s.undo();
        expect(s.moves, 0);
        expect(s.board!.committedState, start);
        expect(s.canUndo, isFalse);
      });

      test('does nothing while paused', () async {
        await setUpSession();
        await s.startLevel(1);
        _play2(s, 0, 2);
        s.pause();
        expect(s.canUndo, isFalse);
        s.undo();
        expect(s.moves, 1);
        s.resume();
        expect(s.canUndo, isTrue);
      });

      test('undo history is persisted and survives a restart', () async {
        await setUpSession();
        await s.startLevel(1);
        _play2(s, 0, 2);
        _play2(s, 1, 0);
        await _settle();
        expect(repo.progress.saved[1]!.moves, const [
          MoveModel(0, 2),
          MoveModel(1, 0),
        ]);

        // "Restart the app": a new container on the same storage.
        final c2 = await readyContainer(
          repo: repo,
          feedback: RecordingFeedback(),
        );
        addTearDown(c2.dispose);
        final s2 = c2.read(gameSessionProvider);
        await s2.startLevel(1);
        expect(s2.moves, 2);
        expect(s2.canUndo, isTrue);
        s2.undo();
        s2.undo();
        expect(s2.moves, 0);
        expect(s2.board!.committedState, s2.level!.puzzle);
      });

      test('an undo is saved too', () async {
        await setUpSession();
        await s.startLevel(1);
        _play2(s, 0, 2);
        _play2(s, 1, 0);
        s.undo();
        await _settle();
        expect(repo.progress.saved[1]!.moves, const [MoveModel(0, 2)]);
        s.undo();
        await _settle();
        expect(repo.progress.saved.containsKey(1), isFalse);
      });

      test('gives haptic feedback when it works', () async {
        await setUpSession();
        await s.startLevel(1);
        _play2(s, 0, 2);
        fb.calls.clear();
        s.undo();
        await _settle();
        expect(fb.calls, contains('light'));
      });
    });

    group('hint', () {
      test('suggests a legal move, and makes NO move by itself', () async {
        await setUpSession();
        await s.startLevel(3);
        final b = s.board!;
        final before = b.committedState;
        await s.requestHint();
        expect(s.hintBottles.length, 2);
        final [x, y] = s.hintBottles.toList();
        expect(b.engine.canPour(x, y) || b.engine.canPour(y, x), isTrue);
        expect(b.committedState, before);
        expect(b.engine.moveCount, 0);
        expect(b.isPouring, isFalse);
        await _settle();
        expect(b.committedState, before, reason: 'still no automatic move');
        expect(s.moves, 0);
      });

      test('the suggested move is the first step of a real solution', () async {
        await setUpSession();
        await s.startLevel(1);
        await s.requestHint();
        // Level 1's only winning first moves lead to a 3-move solve.
        final b = s.board!;
        final l = s.hintBottles.toList();
        final from = b.engine.canPour(l[0], l[1]) ? l[0] : l[1];
        final to = from == l[0] ? l[1] : l[0];
        _play(b, from, to);
        // Following hints from here still solves it.
        for (var i = 0; i < 6 && s.status == SessionStatus.playing; i++) {
          await s.requestHint();
          if (s.hintBottles.isEmpty) break;
          final h = s.hintBottles.toList();
          final f = b.engine.canPour(h[0], h[1]) ? h[0] : h[1];
          _play(b, f, f == h[0] ? h[1] : h[0]);
        }
        expect(s.status, SessionStatus.completed);
      });

      test('shows loading, then clears it', () async {
        await setUpSession();
        await s.startLevel(3);
        final f = s.requestHint();
        expect(s.hintLoading, isTrue);
        await f;
        expect(s.hintLoading, isFalse);
      });

      test('an unsolvable position is explained, not guessed', () async {
        final dead = _custom([
          [1, 1, 2, 2],
          [2, 2, 1, 1],
        ]);
        await setUpSession(loader: (_) async => dead);
        await s.startLevel(900);
        await s.requestHint();
        expect(s.hintBottles, isEmpty);
        expect(s.notice, contains("can't be solved"));
        expect(s.moves, 0);
      });

      test('a search that runs out of budget says so honestly', () async {
        await setUpSession();
        // The limit is read when a level starts.
        s.hintConfig = const SolverConfig(maxNodes: 1);
        await s.startLevel(60);
        await s.requestHint();
        expect(s.hintLoading, isFalse);
        expect(s.hintBottles, isEmpty);
        expect(s.notice, isNotNull);
        expect(s.notice, contains('No hint found in time'));
        expect(s.status, SessionStatus.playing, reason: 'the game goes on');
      });

      test('is refused while paused or pouring, with a reason', () async {
        await setUpSession();
        await s.startLevel(3);
        final b = s.board!;
        final m = b.engine.getLegalMoves().first;
        b.tapBottle(m.source);
        b.tapBottle(m.destination);
        expect(
          s.whyUnavailable(GameAction.hint),
          'Wait for the pour to finish.',
        );
        await s.requestHint();
        expect(s.hintBottles, isEmpty);
        b.finishPour(b.activePour!.token);
        s.pause();
        expect(s.whyUnavailable(GameAction.hint), 'The game is paused.');
        await s.requestHint();
        expect(s.hintBottles, isEmpty);
      });

      test('is dropped the moment the board changes', () async {
        await setUpSession();
        await s.startLevel(3);
        await s.requestHint();
        expect(s.hintBottles, isNotEmpty);
        final m = s.board!.engine.getLegalMoves().first;
        _play2(s, m.source, m.destination);
        expect(s.hintBottles, isEmpty);
      });

      test('requested/shown counts are kept as statistics', () async {
        await setUpSession();
        await s.startLevel(3);
        await s.requestHint();
        await _settle();
        final h = repo.progress.hints[3]!;
        expect(h.requested, 1);
        expect(h.shown, 1);
      });
    });

    group('restart', () {
      test('keeps the level number and seed, restores the layout', () async {
        await setUpSession();
        await s.startLevel(5);
        final lv = s.level!;
        final start = s.board!.committedState;
        final m = s.board!.engine.getLegalMoves().first;
        _play2(s, m.source, m.destination);
        s.restart();
        expect(s.level!.levelNumber, 5);
        expect(s.level!.seed, lv.seed);
        expect(s.level!.fingerprint, lv.fingerprint);
        expect(s.board!.committedState, start);
        expect(s.moves, 0);
        expect(s.canUndo, isFalse);
        expect(s.status, SessionStatus.playing);
      });

      test('forgets the saved game so a later resume starts clean', () async {
        await setUpSession();
        await s.startLevel(5);
        final m = s.board!.engine.getLegalMoves().first;
        _play2(s, m.source, m.destination);
        await _settle();
        expect(repo.progress.saved.containsKey(5), isTrue);
        s.restart();
        await _settle();
        expect(repo.progress.saved.containsKey(5), isFalse);
      });

      test('clears the current hint', () async {
        await setUpSession();
        await s.startLevel(3);
        await s.requestHint();
        s.restart();
        expect(s.hintBottles, isEmpty);
      });

      test('never touches completed levels or stars', () async {
        await setUpSession(
          progress: PlayerProgress.empty.withCompletion(
            level: 1,
            stars: 3,
            moves: 3,
          ),
        );
        await s.startLevel(2);
        final m = s.board!.engine.getLegalMoves().first;
        _play2(s, m.source, m.destination);
        s.restart();
        await _settle();
        expect(repo.progress.recordOf(1)!.stars, 3);
      });
    });

    group('pause', () {
      test('stops new moves and resumes', () async {
        await setUpSession();
        await s.startLevel(1);
        s.pause();
        expect(s.isPaused, isTrue);
        expect(s.board!.tapBottle(0).kind, TapKind.busy);
        expect(s.moves, 0);
        s.resume();
        expect(s.isPaused, isFalse);
        expect(s.board!.tapBottle(0).kind, TapKind.selected);
      });

      test('every assist explains itself while paused', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(1);
        _play2(s, 0, 2);
        s.pause();
        for (final a in GameAction.values) {
          if (a == GameAction.restart) continue;
          expect(s.whyUnavailable(a), 'The game is paused.', reason: '$a');
        }
        expect(s.canUseBooster, isFalse);
      });
    });

    group('unavailable actions', () {
      test('explainUnavailable shows the reason and buzzes', () async {
        await setUpSession();
        await s.startLevel(1);
        fb.calls.clear();
        s.explainUnavailable(GameAction.undo);
        await _settle();
        expect(s.notice, 'Nothing to undo yet.');
        expect(fb.calls, contains('heavy'));
      });

      test('says nothing when the action is in fact available', () async {
        await setUpSession();
        await s.startLevel(1);
        s.explainUnavailable(GameAction.restart);
        expect(s.notice, isNull);
      });
    });

    group('extra bottle booster', () {
      test('is OFF by default and does nothing then', () async {
        expect(const AppSettings().extraBottleBooster, isFalse);
        await setUpSession();
        await s.startLevel(1);
        expect(s.boosterEnabled, isFalse);
        expect(s.canUseBooster, isFalse);
        final before = s.board!.committedState;
        expect(s.useBooster(), isFalse);
        expect(s.board!.committedState, before);
        expect(s.whyUnavailable(GameAction.booster), contains('switched off'));
      });

      test('standard play is exactly the same with the setting off', () async {
        await setUpSession();
        await s.startLevel(1);
        for (final m in _level1) {
          _play2(s, m.$1, m.$2);
        }
        expect(s.result!.moves, 3);
        expect(s.result!.stars, 3);
        expect(s.result!.assisted, isFalse);
        expect(s.board!.committedState.bottleCount, 3);
      });

      test('when enabled it adds one empty bottle', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(1);
        expect(s.canUseBooster, isTrue);
        expect(s.useBooster(), isTrue);
        expect(s.boosted, isTrue);
        expect(s.board!.committedState.bottleCount, 4);
        expect(s.board!.committedState.bottles.last.isEmpty, isTrue);
        expect(s.canUseBooster, isFalse);
        expect(s.useBooster(), isFalse);
        expect(s.whyUnavailable(GameAction.booster), contains('already'));
      });

      test('the setting is stored and read back', () {
        final j = const AppSettings(extraBottleBooster: true).toJson();
        expect(AppSettings.fromJson(j).extraBottleBooster, isTrue);
        expect(
          AppSettings.fromJson({'booster': 'yes'}).extraBottleBooster,
          isFalse,
        );
        expect(AppSettings.fromJson(null).extraBottleBooster, isFalse);
        expect(
          const AppSettings().copyWith(extraBottleBooster: true),
          isNot(const AppSettings()),
        );
      });

      test(
        'a boosted level is won by the normal rule; stars are capped',
        () async {
          await setUpSession(settings: boosterOn);
          await s.startLevel(1);
          s.useBooster();
          for (final m in _level1) {
            _play2(s, m.$1, m.$2);
          }
          expect(s.status, SessionStatus.completed);
          final r = s.result!;
          expect(r.assisted, isTrue);
          expect(r.moves, 3);
          expect(r.stars, GameSession.assistedStarCap);
          await _settle();
          expect(repo.progress.recordOf(1)!.stars, 1);
        },
      );

      test(
        'it cannot set a best-move record that standard play cannot reach',
        () async {
          // A short boosted solve is recorded no lower than par.
          await setUpSession(settings: boosterOn);
          await s.startLevel(1);
          s.useBooster();
          // Level 1: par is 3; any 2-move "win" would be impossible, so use a
          // custom level where the extra bottle genuinely shortens the solve.
          final shorter = _custom([
            [0, 0, 1, 1],
            [1, 1, 0, 0],
          ], par: 6);
          await setUpSession(settings: boosterOn, loader: (_) async => shorter);
          await s.startLevel(900);
          s.useBooster();
          _play2(s, 0, 2); // 1,1 -> extra
          _play2(s, 1, 0); // 0,0 -> bottle 0 (now 0,0,0,0)
          _play2(s, 2, 1); // 1,1 -> bottle 1 (now 1,1,1,1)
          expect(s.status, SessionStatus.completed);
          expect(s.result!.moves, 3);
          await _settle();
          expect(
            repo.progress.recordOf(900)!.bestMoves,
            6,
            reason: 'clamped to par',
          );
          expect(repo.progress.recordOf(900)!.stars, 1);
        },
      );

      test(
        'an earlier standard best is never lowered by a boosted run',
        () async {
          await setUpSession(
            settings: boosterOn,
            progress: PlayerProgress.empty.withCompletion(
              level: 1,
              stars: 3,
              moves: 3,
            ),
          );
          await s.startLevel(1, resume: false);
          s.useBooster();
          for (final m in _level1) {
            _play2(s, m.$1, m.$2);
          }
          await _settle();
          final rec = repo.progress.recordOf(1)!;
          expect(rec.stars, 3, reason: 'the 3 stars already earned stay');
          expect(rec.bestMoves, 3);
          expect(rec.completions, 2);
        },
      );

      test(
        'is saved, and restored with the same bottles after a restart',
        () async {
          await setUpSession(settings: boosterOn);
          await s.startLevel(3);
          final m = s.board!.engine.getLegalMoves().first;
          _play2(s, m.source, m.destination);
          s.useBooster();
          await _settle();
          final saved = repo.progress.saved[3]!;
          expect(saved.boosted, isTrue);
          expect(
            saved.originalPuzzle,
            s.level!.puzzle,
            reason: 'the dealt level is stored without the extra bottle',
          );
          final board = s.board!.committedState;

          final c2 = await readyContainer(
            repo: repo,
            feedback: RecordingFeedback(),
          );
          addTearDown(c2.dispose);
          final s2 = c2.read(gameSessionProvider);
          await s2.startLevel(3);
          expect(s2.boosted, isTrue);
          expect(s2.board!.committedState, board);
          expect(s2.moves, 1);
          expect(s2.canUndo, isTrue);
        },
      );

      test('using it before any move is still saved', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(3);
        s.useBooster();
        await _settle();
        expect(repo.progress.saved[3]!.boosted, isTrue);
        expect(repo.progress.saved[3]!.moves, isEmpty);
      });

      test('restart removes it and forgets the boosted save', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(3);
        s.useBooster();
        await _settle();
        s.restart();
        await _settle();
        expect(s.boosted, isFalse);
        expect(s.board!.committedState, s.level!.puzzle);
        expect(repo.progress.saved.containsKey(3), isFalse);
        expect(s.canUseBooster, isTrue);
      });

      test(
        'hints work on the boosted board and may use the new bottle',
        () async {
          await setUpSession(settings: boosterOn);
          await s.startLevel(3);
          s.useBooster();
          await s.requestHint();
          expect(s.hintBottles.length, 2);
          final [x, y] = s.hintBottles.toList();
          final b = s.board!;
          expect(b.engine.canPour(x, y) || b.engine.canPour(y, x), isTrue);
        },
      );

      test('a hint is dropped when the booster is used', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(3);
        await s.requestHint();
        expect(s.hintBottles, isNotEmpty);
        s.useBooster();
        expect(s.hintBottles, isEmpty);
      });

      test(
        'turning the setting off hides the booster but keeps a boosted game',
        () async {
          await setUpSession(settings: boosterOn);
          await s.startLevel(3);
          s.useBooster();
          expect(s.boosted, isTrue);
          // Settings change: the attempt in progress is not disturbed.
          await c
              .read(progressRepositoryProvider)
              .saveSettings(const AppSettings());
          expect(
            s.board!.committedState.bottleCount,
            s.level!.puzzle.bottleCount + 1,
          );
        },
      );

      test('is not available on a finished level', () async {
        await setUpSession(settings: boosterOn);
        await s.startLevel(1);
        for (final m in _level1) {
          _play2(s, m.$1, m.$2);
        }
        expect(s.canUseBooster, isFalse);
        expect(s.useBooster(), isFalse);
      });
    });

    group('does not add mandatory ads or payments', () {
      test(
        'every assist works with no purchase or ad state anywhere',
        () async {
          // The session has no notion of currency, purchases or ad gates: all
          // four assists are usable straight away on a fresh install.
          await setUpSession(settings: boosterOn);
          await s.startLevel(1);
          expect(s.whyUnavailable(GameAction.restart), isNull);
          expect(s.whyUnavailable(GameAction.hint), isNull);
          expect(s.whyUnavailable(GameAction.booster), isNull);
          _play2(s, 0, 2);
          expect(s.whyUnavailable(GameAction.undo), isNull);
        },
      );
    });
  });
}

GeneratedLevel _custom(List<List<int>> bottles, {int par = 1}) {
  final puzzle = PuzzleState.fromIds(bottles);
  final real = const LevelGenerator().generate(1);
  return GeneratedLevel(
    levelNumber: 900,
    seed: 5,
    variant: 0,
    generatorVersion: kGeneratorVersion,
    puzzle: puzzle,
    fingerprint: 'custom',
    metrics: real.metrics,
    difficulty: Difficulty.easy,
    solution: [for (var i = 0; i < par; i++) const MoveModel(0, 1)],
    method: GenerationMethod.fallback,
  );
}
