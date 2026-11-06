import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/difficulty.dart';
import 'package:prism_pour/engine/generator/generated_level.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/engine/progression/star_rating.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import 'package:prism_pour/features/audio/audio_backend.dart';

import '../../support/fake_audio.dart';
import '../../support/test_app.dart';

/// Taps source then destination and lets the pour animation "finish".
void play(GameSession s, int from, int to) {
  final b = s.board!;
  b.tapBottle(from);
  final o = b.tapBottle(to);
  expect(o.kind, TapKind.pourStarted, reason: '$from -> $to must be legal');
  b.finishPour(b.activePour!.token);
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

// Tutorial 1: [[0,0,0,1],[1,1,1,0],[]]  optimal: 0>2, 1>0, 1>2 (3 moves)
const level1Solution = [(0, 2), (1, 0), (1, 2)];

GeneratedLevel customLevel(List<List<int>> bottles, {int number = 900}) {
  final puzzle = PuzzleState.fromIds(bottles);
  return GeneratedLevel(
    levelNumber: number,
    seed: 5,
    variant: 0,
    generatorVersion: kGeneratorVersion,
    puzzle: puzzle,
    fingerprint: 'custom',
    metrics: DifficultyGrader.measure(
      puzzle,
      const [],
      storedLength: 0,
      storedIsOptimal: false,
    ),
    difficulty: Difficulty.easy,
    solution: const [MoveModel(0, 1)],
    method: GenerationMethod.fallback,
  );
}

void main() {
  late MemoryProgressRepository repo;
  late ProviderContainer c;
  late GameSession s;
  late RecordingFeedback fb;
  late FakeAudioBackend audio;

  Future<void> setUpSession({
    PlayerProgress? progress,
    LevelLoader? loader,
  }) async {
    repo = MemoryProgressRepository(progress: progress);
    fb = RecordingFeedback();
    audio = FakeAudioBackend();
    c = await readyContainer(
      repo: repo,
      feedback: fb,
      audio: audio,
      levelLoader: loader,
    );
    addTearDown(c.dispose);
    s = c.read(gameSessionProvider);
  }

  group('starting a level', () {
    test('loads the real level and shows its real data', () async {
      await setUpSession();
      expect(s.status, SessionStatus.idle);
      await s.startLevel(1);
      expect(s.status, SessionStatus.playing);
      expect(s.level!.levelNumber, 1);
      expect(s.board!.committedState, s.level!.puzzle);
      expect(s.moves, 0);
      expect(s.par, 3);
      expect(s.palette, isNotNull);
      expect(s.canUndo, isFalse);
      expect(s.runId, 1);
    });

    test('shows a loading state while the level is prepared', () async {
      await setUpSession();
      final f = s.startLevel(1);
      expect(s.status, SessionStatus.loading);
      expect(s.board, isNull);
      await f;
      expect(s.status, SessionStatus.playing);
    });

    test('remembers it as the last played level', () async {
      await setUpSession();
      await s.startLevel(4);
      await settle();
      expect(c.read(progressProvider).lastPlayedLevel, 4);
      expect(repo.progress.lastPlayedLevel, 4);
    });

    test('a failing loader gives a failed state, not a crash', () async {
      await setUpSession(loader: (_) async => throw StateError('boom'));
      await s.startLevel(1);
      expect(s.status, SessionStatus.failed);
      expect(s.board, isNull);
    });

    test(
      'starting another level while one loads: the LAST request wins',
      () async {
        await setUpSession();
        final a = s.startLevel(1);
        final b = s.startLevel(2);
        await Future.wait([a, b]);
        expect(s.level!.levelNumber, 2);
        expect(s.status, SessionStatus.playing);
      },
    );

    test('new board each time: runId changes', () async {
      await setUpSession();
      await s.startLevel(1);
      final first = s.runId;
      await s.startLevel(1);
      expect(s.runId, greaterThan(first));
    });

    test('disposing while loading is safe', () async {
      await setUpSession();
      final f = s.startLevel(1);
      c.dispose();
      await f;
    });
  });

  group('every committed move is saved', () {
    test('the move list is written after each pour', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      await settle();
      expect(s.moves, 1);
      expect(repo.progress.saved[1]!.moves, [const MoveModel(0, 2)]);
      expect(repo.progress.saved[1]!.generatorVersion, kGeneratorVersion);
      play(s, 1, 0);
      await settle();
      expect(repo.progress.saved[1]!.moves, [
        const MoveModel(0, 2),
        const MoveModel(1, 0),
      ]);
    });

    test(
      'a save taken mid-pour already contains the move (commit first)',
      () async {
        await setUpSession();
        await s.startLevel(1);
        s.board!.tapBottle(0);
        s.board!.tapBottle(2); // pour started, animation NOT finished
        await settle();
        expect(s.board!.isPouring, isTrue);
        expect(repo.progress.saved[1]!.moves, [const MoveModel(0, 2)]);
      },
    );

    test('undo updates the save; undoing everything clears it', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      play(s, 1, 0);
      s.undo();
      await settle();
      expect(s.moves, 1);
      expect(repo.progress.saved[1]!.moves.length, 1);
      s.undo();
      await settle();
      expect(s.moves, 0);
      expect(repo.progress.saved.containsKey(1), isFalse);
    });

    test('restart clears the saved game', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      await settle();
      s.restart();
      await settle();
      expect(s.moves, 0);
      expect(repo.progress.saved.containsKey(1), isFalse);
      expect(s.board!.committedState, s.level!.puzzle);
    });

    test('selecting bottles without pouring does not write anything', () async {
      await setUpSession();
      await s.startLevel(1);
      await settle();
      final writes = repo.progressWrites;
      s.board!.tapBottle(0);
      s.board!.tapBottle(0);
      await settle();
      expect(repo.progressWrites, writes);
    });
  });

  group('continue: restoring a game', () {
    test('replaying the saved moves restores the exact position', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      play(s, 1, 0);
      final before = s.board!.committedState;
      await settle();

      // A brand new session (as after restarting the app) with the same storage.
      final c2 = await readyContainer(repo: repo);
      addTearDown(c2.dispose);
      final s2 = c2.read(gameSessionProvider);
      await s2.startLevel(1);
      expect(s2.moves, 2);
      expect(s2.board!.committedState, before);
      expect(s2.canUndo, isTrue);
    });

    test('"start over" ignores and clears the save', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      await settle();
      await s.startLevel(1, resume: false);
      await settle();
      expect(s.moves, 0);
      expect(repo.progress.saved.containsKey(1), isFalse);
    });

    test('a save from another generator version is discarded safely', () async {
      final stale = SavedGame(
        level: 1,
        variant: 0,
        generatorVersion: kGeneratorVersion + 1,
        moves: const [MoveModel(0, 2)],
      );
      await setUpSession(progress: PlayerProgress.empty.withSavedGame(stale));
      await s.startLevel(1);
      await settle();
      expect(s.moves, 0);
      expect(s.board!.committedState, s.level!.puzzle);
      expect(repo.progress.saved.containsKey(1), isFalse);
    });

    test('a save with an illegal move is discarded, not crashed on', () async {
      final bad = SavedGame(
        level: 1,
        variant: 0,
        generatorVersion: kGeneratorVersion,
        moves: const [MoveModel(2, 0)],
      );
      await setUpSession(progress: PlayerProgress.empty.withSavedGame(bad));
      await s.startLevel(1);
      await settle();
      expect(s.status, SessionStatus.playing);
      expect(s.moves, 0);
      expect(repo.progress.saved.containsKey(1), isFalse);
    });

    test(
      'a save that already solves the level completes it on restore',
      () async {
        final solved = SavedGame(
          level: 1,
          variant: 0,
          generatorVersion: kGeneratorVersion,
          moves: [for (final m in level1Solution) MoveModel(m.$1, m.$2)],
        );
        await setUpSession(
          progress: PlayerProgress.empty.withSavedGame(solved),
        );
        await s.startLevel(1);
        await settle();
        expect(s.status, SessionStatus.completed);
        expect(s.result!.moves, 3);
        expect(c.read(progressProvider).isCompleted(1), isTrue);
      },
    );
  });

  group('completing a level', () {
    test('only after the last pour finishes animating', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      play(s, 1, 0);
      s.board!.tapBottle(1);
      s.board!.tapBottle(2); // winning pour starts
      expect(s.board!.engine.isLevelCompleted(), isTrue);
      expect(s.status, SessionStatus.playing, reason: 'still pouring');
      s.board!.finishPour(s.board!.activePour!.token);
      expect(s.status, SessionStatus.completed);
    });

    test('stars, moves and par come from the real play', () async {
      await setUpSession();
      await s.startLevel(1);
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      final r = s.result!;
      expect(r.level, 1);
      expect(r.moves, 3);
      expect(r.par, 3);
      expect(r.stars, StarRating.starsFor(moves: 3, par: 3));
      expect(r.stars, 3);
      expect(r.thresholds.three, StarRating.thresholds(3).three);
      expect(r.previousBest, isNull);
      expect(r.isNewBest, isTrue);
    });

    test('progress is recorded and the next level unlocks', () async {
      await setUpSession();
      await s.startLevel(1);
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      await settle();
      final p = c.read(progressProvider);
      expect(p.recordOf(1)!.stars, 3);
      expect(p.recordOf(1)!.bestMoves, 3);
      expect(p.currentLevel, 2);
      expect(p.isUnlocked(2), isTrue);
      expect(p.saved.containsKey(1), isFalse);
      expect(repo.progress.currentLevel, 2, reason: 'persisted');
    });

    test('more moves, fewer stars (documented rules)', () async {
      await setUpSession();
      await s.startLevel(2); // par 4: 3*<=5, 2*<=7
      // Waste moves by shuffling the pair of 1s between the two empty bottles.
      for (final m in const [(0, 3), (3, 4), (4, 3), (3, 4)]) {
        play(s, m.$1, m.$2);
      }
      for (final m in const [(2, 0), (1, 2), (1, 4)]) {
        play(s, m.$1, m.$2);
      }
      expect(s.status, SessionStatus.completed);
      expect(s.result!.moves, 7);
      expect(s.result!.stars, 2);
    });

    test('very wasteful play still finishes with 1 star', () async {
      await setUpSession();
      await s.startLevel(2);
      play(s, 0, 3); // the pair of 1s goes into the first empty bottle
      for (var i = 0; i < 7; i++) {
        play(s, 3, 4); // ... and is shuffled back and forth
        play(s, 4, 3);
      }
      for (final m in const [(2, 0), (1, 2), (1, 3)]) {
        play(s, m.$1, m.$2);
      }
      expect(s.status, SessionStatus.completed);
      expect(s.result!.stars, 1);
      expect(s.result!.moves, greaterThan(StarRating.thresholds(4).two));
    });

    test('an undone pour is not counted in the moves', () async {
      await setUpSession();
      await s.startLevel(1);
      play(s, 0, 2);
      play(s, 1, 0);
      s.undo();
      s.board!.interruptPour(); // let the undo animation go
      s.undo();
      s.board!.interruptPour();
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      expect(s.result!.moves, 3);
      expect(s.result!.stars, 3);
    });

    test('replaying keeps the best result and reports a new best', () async {
      final prior = PlayerProgress.empty
          .withCompletion(level: 2, stars: 1, moves: 12)
          .withCompletion(level: 1, stars: 3, moves: 3);
      await setUpSession(progress: prior);
      await s.startLevel(2, resume: false);
      for (final m in const [(0, 3), (2, 0), (1, 2), (1, 3)]) {
        play(s, m.$1, m.$2);
      }
      final r = s.result!;
      expect(r.previousBest!.bestMoves, 12);
      expect(r.isNewBest, isTrue);
      expect(r.starsImproved, isTrue);
      await settle();
      expect(c.read(progressProvider).recordOf(2)!.stars, 3);
      expect(c.read(progressProvider).recordOf(2)!.bestMoves, 4);
    });

    test('a worse replay never lowers the saved result', () async {
      final prior = PlayerProgress.empty
          .withCompletion(level: 1, stars: 3, moves: 3)
          .withCompletion(level: 2, stars: 3, moves: 4);
      await setUpSession(progress: prior);
      await s.startLevel(2, resume: false);
      for (final m in const [
        (0, 3),
        (3, 4),
        (4, 3),
        (3, 4),
        (2, 0),
        (1, 2),
        (1, 4),
      ]) {
        play(s, m.$1, m.$2);
      }
      await settle();
      expect(s.status, SessionStatus.completed);
      expect(s.result!.moves, 7);
      expect(s.result!.stars, 2);
      expect(s.result!.isNewBest, isFalse);
      expect(s.result!.starsImproved, isFalse);
      expect(c.read(progressProvider).recordOf(2)!.stars, 3);
      expect(c.read(progressProvider).recordOf(2)!.bestMoves, 4);
    });

    test('completion happens exactly once', () async {
      await setUpSession();
      await s.startLevel(1);
      var notifications = 0;
      s.addListener(() {
        if (s.status == SessionStatus.completed) notifications++;
      });
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      await settle();
      final writes = repo.progressWrites;
      s
          .board!
          .notifyListeners; // touching the board again must not complete twice
      s.board!.tapBottle(0);
      await settle();
      expect(repo.progressWrites, writes);
      expect(s.result!.level, 1);
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test('the finishing cue is played once', () async {
      await setUpSession();
      await s.startLevel(1);
      fb.calls.clear();
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      expect(fb.calls.where((x) => x == 'heavy').length, 1);
    });
  });

  group('hints use the real solver', () {
    test('a hint is a legal move from the CURRENT position', () async {
      await setUpSession();
      await s.startLevel(3);
      await s.requestHint();
      expect(s.hintLoading, isFalse);
      expect(s.hintBottles.length, 2);
      final [from, to] = s.hintBottles.toList();
      final b = s.board!;
      final legal = b.engine.canPour(from, to) || b.engine.canPour(to, from);
      expect(legal, isTrue);
    });

    test('following hints solves the level', () async {
      await setUpSession();
      await s.startLevel(3);
      var guard = 0;
      while (s.status == SessionStatus.playing && guard++ < 40) {
        await s.requestHint();
        expect(s.hintBottles, isNotEmpty);
        // The hint set is {source, destination}; find which order is legal.
        final l = s.hintBottles.toList();
        final b = s.board!;
        final from = b.engine.canPour(l[0], l[1]) ? l[0] : l[1];
        final to = from == l[0] ? l[1] : l[0];
        play(s, from, to);
      }
      expect(s.status, SessionStatus.completed);
    });

    test('a hint disappears as soon as the player moves', () async {
      await setUpSession();
      await s.startLevel(3);
      await s.requestHint();
      expect(s.hintBottles, isNotEmpty);
      final b = s.board!;
      final m = b.engine.getLegalMoves().first;
      play(s, m.source, m.destination);
      expect(s.hintBottles, isEmpty);
    });

    test('tapping a bottle clears the highlight', () async {
      await setUpSession();
      await s.startLevel(3);
      await s.requestHint();
      expect(s.hintBottles, isNotEmpty);
      s.onTap(s.board!.tapBottle(0));
      expect(s.hintBottles, isEmpty);
    });

    test('no hint while a pour is animating or the game is paused', () async {
      await setUpSession();
      await s.startLevel(3);
      final b = s.board!;
      final m = b.engine.getLegalMoves().first;
      b.tapBottle(m.source);
      b.tapBottle(m.destination);
      expect(b.isPouring, isTrue);
      await s.requestHint();
      expect(s.hintBottles, isEmpty);
      expect(s.hintLoading, isFalse);
      b.finishPour(b.activePour!.token);
      s.pause();
      await s.requestHint();
      expect(s.hintBottles, isEmpty);
    });

    test('an unsolvable position says so instead of guessing', () async {
      final dead = customLevel([
        [1, 1, 2, 2],
        [2, 2, 1, 1],
      ]);
      await setUpSession(loader: (_) async => dead);
      await s.startLevel(900);
      await s.requestHint();
      expect(s.hintBottles, isEmpty);
      expect(s.notice, contains("can't be solved"));
    });

    test('hints are free: they never change moves or stars', () async {
      await setUpSession();
      await s.startLevel(1);
      await s.requestHint();
      await s.requestHint();
      expect(s.moves, 0);
      for (final m in level1Solution) {
        play(s, m.$1, m.$2);
      }
      expect(s.result!.stars, 3);
    });
  });

  group('notices', () {
    test('show and dismiss by id', () async {
      await setUpSession();
      await s.startLevel(1);
      s.showNotice('hello');
      final id = s.noticeId;
      expect(s.notice, 'hello');
      s.dismissNotice(id + 5); // stale id
      expect(s.notice, 'hello');
      s.dismissNotice(id);
      expect(s.notice, isNull);
    });
  });

  group('feedback', () {
    test('taps map to the right haptics and sounds', () async {
      await setUpSession();
      await s.startLevel(1);
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(s.board!.tapBottle(0)); // select
      await settle();
      expect(fb.calls, ['selectionClick']);
      expect(audio.played, [SoundEffect.select]);
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(s.board!.tapBottle(2)); // pour
      await settle();
      expect(fb.calls, ['light']);
      expect(audio.played, [SoundEffect.glassMove, SoundEffect.pour]);
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(s.board!.tapBottle(0)); // busy: no cue
      await settle();
      expect(fb.calls, isEmpty);
      expect(audio.played, isEmpty);
    });

    test('a bottle that cannot pour gives the rejection cue', () async {
      await setUpSession();
      await s.startLevel(1);
      final b = s.board!;
      b.tapBottle(0);
      final o = b.tapBottle(1); // colour mismatch: reselects
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(o);
      await settle();
      expect(fb.calls, ['heavy']);
      expect(audio.played, [SoundEffect.invalid]);
    });

    test('haptics and sound can be switched off', () async {
      await setUpSession();
      await s.startLevel(1);
      c.read(appSettingsProvider.notifier).setHaptics(false);
      c.read(appSettingsProvider.notifier).setSoundEffects(false);
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(s.board!.tapBottle(0));
      s.onTap(s.board!.tapBottle(2));
      await settle();
      expect(fb.calls, isEmpty);
      expect(audio.played, isEmpty);
    });

    test('each can be switched off independently', () async {
      await setUpSession();
      await s.startLevel(1);
      c.read(appSettingsProvider.notifier).setSoundEffects(false);
      fb.calls.clear();
      audio.calls.clear();
      s.onTap(s.board!.tapBottle(0));
      await settle();
      expect(fb.calls, ['selectionClick']);
      expect(audio.played, isEmpty);
    });
  });

  group('app settings reach the board', () {
    test('settings stay as stored', () async {
      await setUpSession(progress: null);
      expect(c.read(appSettingsProvider), const AppSettings());
    });
  });
}
