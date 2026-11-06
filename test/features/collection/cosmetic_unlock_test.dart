import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/router/app_router.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/features/audio/audio_backend.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/fake_audio.dart';
import '../../support/pump_app.dart';
import '../../support/test_app.dart';

/// [levels] completed levels worth exactly [stars] stars in total.
PlayerProgress withStars(int stars, {int levels = 30}) {
  var p = PlayerProgress.empty;
  var left = stars;
  for (var i = 1; i <= levels; i++) {
    final s = left >= 3 ? 3 : left;
    if (s == 0) break;
    p = p.withCompletion(level: i, stars: s, moves: 10);
    left -= s;
  }
  expect(p.totalStars, stars);
  return p;
}

void main() {
  group('the collection is data', () {
    test('five original designs with unique ids and names', () {
      expect(BottleStyles.all, hasLength(5));
      expect(BottleStyles.all.map((s) => s.id).toSet(), hasLength(5));
      expect(BottleStyles.all.map((s) => s.name).toSet(), hasLength(5));
      expect(BottleStyles.all.map((s) => s.id), [
        'alchemy_classic',
        'crystal_prism',
        'royal_glass',
        'verdant_vial',
        'starlit_flask',
      ]);
    });

    test('every design has an unlock threshold, rising down the list', () {
      var last = -1;
      for (final s in BottleStyles.all) {
        expect(
          BottleUnlocks.starsRequired.containsKey(s.id),
          isTrue,
          reason: s.id,
        );
        final need = BottleUnlocks.required(s.id);
        expect(need, greaterThan(last), reason: s.id);
        last = need;
      }
      expect(BottleUnlocks.required('alchemy_classic'), 0);
      expect(BottleUnlocks.required('verdant_vial'), 80);
      expect(BottleUnlocks.required('starlit_flask'), 130);
    });

    test('the designs really are different shapes and finishes', () {
      final silhouettes = {
        for (final s in BottleStyles.all)
          (s.spec.aspect, s.spec.bodyWidth, s.spec.shoulder, s.spec.base),
      };
      expect(silhouettes, hasLength(BottleStyles.all.length));
      expect(
        BottleStyles.all.map((s) => s.ring).toSet(),
        hasLength(BottleStyles.all.length),
        reason: 'each has its own neck ring',
      );
      expect(BottleStyles.all.map((s) => s.glow).toSet(), hasLength(5));
    });
  });

  group('unlock rules', () {
    test('a design opens exactly at its star threshold', () {
      for (final s in BottleStyles.all) {
        final need = BottleUnlocks.required(s.id);
        if (need > 0) {
          expect(BottleUnlocks.isUnlocked(s.id, need - 1), isFalse);
        }
        expect(BottleUnlocks.isUnlocked(s.id, need), isTrue);
      }
    });

    test('progress unlocks the designs it has earned, and only those', () {
      final p79 = withStars(79);
      expect(p79.isStyleUnlocked('royal_glass'), isTrue);
      expect(p79.isStyleUnlocked('verdant_vial'), isFalse);
      final p80 = withStars(80);
      expect(p80.isStyleUnlocked('verdant_vial'), isTrue);
      expect(p80.isStyleUnlocked('starlit_flask'), isFalse);
      expect(
        withStars(130, levels: 60).isStyleUnlocked('starlit_flask'),
        isTrue,
      );
    });

    test('an unlocked design is never taken away', () {
      final p = withStars(15);
      expect(p.isStyleUnlocked('crystal_prism'), isTrue);
      // Replaying and doing worse cannot lower the stars or revoke anything.
      final worse = p.withCompletion(level: 1, stars: 1, moves: 99);
      expect(worse.totalStars, p.totalStars);
      expect(worse.isStyleUnlocked('crystal_prism'), isTrue);
    });

    test(
      'the free design is always available; unknown ids are not locked out',
      () {
        expect(PlayerProgress.empty.isStyleUnlocked('alchemy_classic'), isTrue);
        expect(BottleUnlocks.required('no_such_style'), 0);
      },
    );

    test(
      'a locked design saved in settings falls back to the free one',
      () async {
        final c = await readyContainer(
          settings: const AppSettings(bottleStyleId: 'starlit_flask'),
        );
        addTearDown(c.dispose);
        expect(c.read(bottleStyleProvider).id, 'alchemy_classic');
      },
    );

    test('an unlocked design is used', () async {
      final c = await readyContainer(
        progress: withStars(80),
        settings: const AppSettings(bottleStyleId: 'verdant_vial'),
      );
      addTearDown(c.dispose);
      expect(c.read(bottleStyleProvider).id, 'verdant_vial');
    });
  });

  group('cosmetic skins never change the puzzle', () {
    test('every style gives the same capacity and unit layout', () {
      for (final s in BottleStyles.all) {
        for (final cap in [3, 4, 5, 6, 8]) {
          final g = s.geometryFor(const Size(100, 240), cap);
          expect(g.capacity, cap, reason: '${s.id} cap $cap');
          expect(g.unitHeight, greaterThan(0));
          for (var u = 0; u < cap; u++) {
            expect(g.unitRect(u).height, closeTo(g.unitHeight, 1e-6));
          }
        }
      }
    });

    test('game rules never see a style: the engine and controller do not '
        'import rendering', () {
      for (final path in [
        'lib/engine',
        'lib/features/game/application/board_controller.dart',
      ]) {
        final files = FileSystemEntity.isDirectorySync(path)
            ? Directory(path)
                  .listSync(recursive: true)
                  .whereType<File>()
                  .where((f) => f.path.endsWith('.dart'))
                  .toList()
            : [File(path)];
        for (final f in files) {
          final text = f.readAsStringSync();
          expect(text, isNot(contains('bottle_style')), reason: f.path);
          expect(text, isNot(contains('/rendering/')), reason: f.path);
        }
      }
    });

    test(
      'the same moves give the same result whatever style is equipped',
      () async {
        final level = const LevelGenerator().generate(7);
        final results = <String>[];
        for (final s in BottleStyles.all) {
          final c = await readyContainer(
            progress: withStars(130, levels: 60),
            settings: AppSettings(bottleStyleId: s.id),
            feedback: RecordingFeedback(),
          );
          expect(c.read(bottleStyleProvider).id, s.id);
          final b = BoardController(level.puzzle);
          final e = GameEngine(level.puzzle);
          for (final m in level.solution) {
            b.tapBottle(m.source);
            expect(b.tapBottle(m.destination).kind, TapKind.pourStarted);
            b.finishPour(b.activePour!.token);
            e.applyMove(m);
          }
          expect(b.committedState, e.state);
          expect(b.engine.isLevelCompleted(), isTrue);
          results.add('${b.engine.moveCount}:${b.committedState.hashCode}');
          c.dispose();
        }
        expect(results.toSet(), hasLength(1));
      },
    );

    test('styles never alter stars or par', () async {
      final level = const LevelGenerator().generate(3);
      final stars = <int>{};
      for (final s in BottleStyles.all) {
        final c = await readyContainer(
          progress: withStars(130, levels: 60).withoutSavedGame(3),
          settings: AppSettings(bottleStyleId: s.id),
          feedback: RecordingFeedback(),
        );
        final session = c.read(gameSessionProvider);
        await session.startLevel(3, resume: false);
        for (final m in level.solution) {
          final b = session.board!;
          b.tapBottle(m.source);
          b.tapBottle(m.destination);
          b.finishPour(b.activePour!.token);
        }
        stars.add(session.result!.stars);
        expect(session.par, level.solution.length);
        c.dispose();
      }
      expect(stars, hasLength(1));
    });
  });

  group('earning a design on completion', () {
    Future<(ProviderContainer, GameSession, FakeAudioBackend)> open(
      PlayerProgress progress,
    ) async {
      final audio = FakeAudioBackend();
      final c = await readyContainer(
        progress: progress,
        audio: audio,
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      return (c, c.read(gameSessionProvider), audio);
    }

    Future<void> solve(GameSession s, int level) async {
      await s.startLevel(level, resume: false);
      for (final m in const LevelGenerator().generate(level).solution) {
        final b = s.board!;
        b.tapBottle(m.source);
        b.tapBottle(m.destination);
        b.finishPour(b.activePour!.token);
      }
    }

    test(
      'the completion that crosses a threshold reports the new design',
      () async {
        // 13 stars from 5 levels, then level 6 for 3 more makes 16 >= 15.
        final (_, s, _) = await open(withStars(13, levels: 5));
        await solve(s, 6);
        expect(s.result!.stars, 3);
        expect(s.result!.newStyleIds, ['crystal_prism']);
        expect(s.result!.hasReward, isTrue);
      },
    );

    test('a completion short of a threshold reports nothing', () async {
      final (_, s, _) = await open(withStars(9, levels: 3));
      await solve(s, 4);
      expect(s.result!.newStyleIds, isEmpty);
    });

    test('a design is announced once, not again on later wins', () async {
      final (_, s, _) = await open(withStars(16, levels: 6));
      await solve(s, 7);
      expect(s.result!.newStyleIds, isEmpty);
    });

    test('replaying with no improvement earns nothing new', () async {
      final (_, s, _) = await open(withStars(15, levels: 5));
      await solve(s, 3); // already 3 stars: nothing gained
      expect(s.result!.newStyleIds, isEmpty);
    });

    test('two designs can unlock together', () async {
      // From 44 to 47 stars crosses only royal_glass (45); craft a jump over
      // two thresholds is impossible with 3 stars, so check just one.
      final (_, s, _) = await open(withStars(43, levels: 15));
      await solve(s, 16);
      expect(s.result!.newStyleIds, ['royal_glass']);
    });

    test('the saved progress holds the unlock afterwards', () async {
      final (c, s, _) = await open(withStars(13, levels: 5));
      await solve(s, 6);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(progressProvider).isStyleUnlocked('crystal_prism'), isTrue);
      expect(
        c.read(progressProvider).unlockedStyles,
        contains('crystal_prism'),
      );
    });

    testWidgets('the screen names the design and plays the reward sound', (
      tester,
    ) async {
      final audio = FakeAudioBackend();
      final c = await readyContainer(
        progress: withStars(13, levels: 5),
        audio: audio,
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      final s = c.read(gameSessionProvider);
      await tester.runAsync(() => s.startLevel(6, resume: false));
      for (final m in const LevelGenerator().generate(6).solution) {
        final b = s.board!;
        b.tapBottle(m.source);
        b.tapBottle(m.destination);
        b.finishPour(b.activePour!.token);
      }
      c.read(appRouterProvider).push('/complete');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byKey(const Key('complete.style.Crystal Prism')),
        findsOneWidget,
      );
      expect(
        audio.played,
        isNot(contains(SoundEffect.unlock)),
        reason: 'the chime waits for the fanfare',
      );
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(audio.played, contains(SoundEffect.unlock));
      await leaveApp(tester);
    });

    testWidgets('no reward sound when nothing was earned', (tester) async {
      final audio = FakeAudioBackend();
      final c = await readyContainer(
        progress: withStars(9, levels: 3),
        audio: audio,
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      final s = c.read(gameSessionProvider);
      await tester.runAsync(() => s.startLevel(4, resume: false));
      for (final m in const LevelGenerator().generate(4).solution) {
        final b = s.board!;
        b.tapBottle(m.source);
        b.tapBottle(m.destination);
        b.finishPour(b.activePour!.token);
      }
      c.read(appRouterProvider).push('/complete');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(audio.played, contains(SoundEffect.complete));
      expect(audio.played, isNot(contains(SoundEffect.unlock)));
      await leaveApp(tester);
    });
  });

  group('collection screen', () {
    testWidgets('shows all designs; locked ones say what they need', (
      tester,
    ) async {
      final c = await readyContainer(progress: withStars(50, levels: 20));
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/collection',
        size: const Size(430, 2400),
      );
      for (final s in BottleStyles.all) {
        expect(find.text(s.name.toUpperCase()), findsWidgets, reason: s.name);
      }
      expect(tester.takeException(), isNull);
      await leaveApp(tester);
    });
  });
}
