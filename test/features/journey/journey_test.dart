import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/router/app_router.dart';
import 'package:prism_pour/app/router/app_routes.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/journey/application/journey_providers.dart';
import 'package:prism_pour/features/journey/domain/journey.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/shared/widgets/alchemy_background.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

PlayerProgress completed(int n, {int stars = 3}) {
  var p = PlayerProgress.empty;
  for (var i = 1; i <= n; i++) {
    p = p.withCompletion(level: i, stars: stars, moves: 10);
  }
  return p;
}

void main() {
  group('the journey is data', () {
    test('the five required chapters exist, in order', () {
      expect(
        [for (final c in Journey.chapters) c.name],
        [
          'Midnight Lab',
          'Crystal Cavern',
          'Enchanted Garden',
          'Celestial Observatory',
          'Golden Laboratory',
        ],
      );
    });

    test('ids are unique, lengths positive, colour only ever increases', () {
      final ids = Journey.chapters.map((c) => c.id).toSet();
      expect(ids, hasLength(Journey.chapters.length));
      var last = -1.0;
      for (final c in Journey.chapters) {
        expect(c.levels, greaterThan(0));
        expect(c.motes, isNotEmpty);
        expect(c.tagline, isNotEmpty);
        expect(c.colorfulness, greaterThan(last), reason: c.name);
        last = c.colorfulness;
      }
      expect(Journey.chapters.first.colorfulness, 0);
      expect(Journey.chapters.last.colorfulness, 1);
    });

    test('the lap length is the sum of the chapters', () {
      expect(
        Journey.lapLength,
        Journey.chapters.fold<int>(0, (a, c) => a + c.levels),
      );
    });

    test('every chapter keeps the scene dark enough to read light text on', () {
      for (final c in Journey.chapters) {
        for (final colour in [c.top, c.mid, c.bottom]) {
          expect(
            HSLColor.fromColor(colour).lightness,
            lessThan(0.30),
            reason: '${c.name} background',
          );
        }
      }
    });
  });

  group('position by completed levels', () {
    test('level 0 is the start of Midnight Lab', () {
      final p = Journey.at(0);
      expect(p.stage.id, 'midnight_lab');
      expect(p.lap, 0);
      expect(p.doneInStage, 0);
      expect(p.chapter, 1);
      expect(p.title, 'Midnight Lab');
      expect(Journey.start, p);
    });

    test('chapters change exactly at the milestone levels', () {
      var edge = 0;
      for (var i = 0; i < Journey.chapters.length; i++) {
        final len = Journey.chapters[i].levels;
        expect(Journey.at(edge).stageIndex, i, reason: 'first of chapter $i');
        expect(Journey.at(edge + len - 1).stageIndex, i, reason: 'last');
        expect(Journey.at(edge + len - 1).levelsToNext, 1);
        edge += len;
      }
      expect(edge, Journey.lapLength);
      expect(Journey.at(9).stage.id, 'midnight_lab');
      expect(Journey.at(10).stage.id, 'crystal_cavern');
      expect(Journey.at(25).stage.id, 'enchanted_garden');
      expect(Journey.at(50).stage.id, 'celestial_observatory');
      expect(Journey.at(90).stage.id, 'golden_laboratory');
    });

    test(
      'progress within a chapter counts up and levelsToNext counts down',
      () {
        for (var done = 0; done < 10; done++) {
          final p = Journey.at(done);
          expect(p.doneInStage, done);
          expect(p.levelsToNext, 10 - done);
          expect(p.stageProgress, closeTo(done / 10, 1e-9));
        }
      },
    );

    test('the next chapter is named, and wraps after the last', () {
      expect(Journey.at(0).nextStage.name, 'Crystal Cavern');
      expect(Journey.at(Journey.lapLength - 1).nextStage.name, 'Midnight Lab');
    });

    test('chapter numbers rise by one at every boundary, with no limit', () {
      var last = 0;
      for (var done = 0; done < Journey.lapLength * 3; done++) {
        final c = Journey.at(done).chapter;
        expect(c, anyOf(last, last + 1));
        last = c;
      }
      expect(last, Journey.chapters.length * 3);
    });

    test('negative input is treated as the start', () {
      expect(Journey.at(-5), Journey.start);
    });
  });

  group('no level number is past the end', () {
    test('the journey repeats as numbered laps', () {
      final second = Journey.at(Journey.lapLength);
      expect(second.lap, 1);
      expect(second.stage.id, 'midnight_lab');
      expect(second.title, 'Midnight Lab II');
      expect(second.chapter, Journey.chapters.length + 1);
      expect(Journey.at(Journey.lapLength * 2).title, 'Midnight Lab III');
      expect(Journey.at(Journey.lapLength * 3).title, 'Midnight Lab IV');
      expect(Journey.at(Journey.lapLength * 9).title, 'Midnight Lab X');
      expect(Journey.at(Journey.lapLength * 39).title, 'Midnight Lab XL');
      expect(Journey.at(Journey.lapLength * 4000).title, 'Midnight Lab 4001');
    });

    test('later laps look different but stay readable', () {
      final first = Journey.at(0).stage;
      final second = Journey.at(Journey.lapLength).stage;
      expect(second.top, isNot(first.top));
      expect(second.glowA, isNot(first.glowA));
      expect(
        HSLColor.fromColor(second.top).lightness,
        closeTo(HSLColor.fromColor(first.top).lightness, 0.02),
      );
      // A lap that is a whole number of turns round the wheel is unchanged.
      expect(first.shifted(360), same(first));
    });

    test('huge level numbers work and are instant', () {
      for (final done in [
        1 << 20,
        1 << 40,
        1 << 62,
        9007199254740993,
        0x7fffffffffffffff - 1,
      ]) {
        final p = Journey.at(done);
        expect(p.doneInStage, inInclusiveRange(0, p.levelsInStage - 1));
        expect(p.stageIndex, inInclusiveRange(0, 4));
        expect(p.lap, done ~/ Journey.lapLength);
        expect(p.title, isNotEmpty);
        expect(p.levelsToNext, greaterThan(0));
      }
    });
  });

  group('palette blending', () {
    test('lerp reaches both ends and blends between', () {
      final a = Journey.chapters[0], b = Journey.chapters[3];
      expect(JourneyStage.lerp(a, b, 0), same(a));
      expect(JourneyStage.lerp(a, b, 1), same(b));
      final mid = JourneyStage.lerp(a, b, 0.5);
      expect(mid.top, Color.lerp(a.top, b.top, 0.5));
      expect(mid.id, b.id);
      expect(mid.motes, hasLength(b.motes.length));
    });
  });

  group('driven by the saved progress', () {
    test('before the progress has loaded the player is at the start', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(journeyProvider), Journey.start);
    });

    test('follows the first level not yet completed', () async {
      for (final (done, id) in const [
        (0, 'midnight_lab'),
        (9, 'midnight_lab'),
        (10, 'crystal_cavern'),
        (24, 'crystal_cavern'),
        (25, 'enchanted_garden'),
        (49, 'enchanted_garden'),
        (50, 'celestial_observatory'),
        (90, 'golden_laboratory'),
        (150, 'midnight_lab'),
      ]) {
        final c = await readyContainer(progress: completed(done));
        expect(c.read(journeyProvider).stage.id, id, reason: '$done done');
        c.dispose();
      }
    });

    test('moves on as levels are completed', () async {
      final c = await readyContainer(progress: completed(9));
      addTearDown(c.dispose);
      expect(c.read(journeyStageProvider).id, 'midnight_lab');
      await c
          .read(progressProvider.notifier)
          .recordCompletion(level: 10, stars: 2, moves: 12);
      expect(c.read(journeyStageProvider).id, 'crystal_cavern');
      expect(c.read(journeyProvider).chapter, 2);
    });
  });

  group('completing the level that reaches a milestone', () {
    Future<(ProviderContainer, GameSession)> sessionAt(int done) async {
      final c = await readyContainer(
        progress: completed(done),
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      return (c, c.read(gameSessionProvider));
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

    test('level 10 enters the Crystal Cavern', () async {
      final (_, s) = await sessionAt(9);
      await solve(s, 10);
      expect(s.status, SessionStatus.completed);
      final ch = s.result!.newChapter;
      expect(ch, isNotNull);
      expect(ch!.stage.id, 'crystal_cavern');
      expect(s.result!.hasReward, isTrue);
    });

    test('a level inside a chapter does not announce one', () async {
      final (_, s) = await sessionAt(4);
      await solve(s, 5);
      expect(s.result!.newChapter, isNull);
    });

    test('replaying a completed level never re-announces it', () async {
      final (_, s) = await sessionAt(12);
      await solve(s, 10);
      expect(s.result!.newChapter, isNull);
    });

    test('the Golden Laboratory leads into the next lap', () async {
      final (_, s) = await sessionAt(Journey.lapLength - 1);
      await solve(s, Journey.lapLength);
      final ch = s.result!.newChapter!;
      expect(ch.lap, 1);
      expect(ch.title, 'Midnight Lab II');
    });
  });

  group('on screen', () {
    testWidgets('home shows the chapter and what comes next', (tester) async {
      final c = await readyContainer(progress: completed(12));
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      expect(
        tester.widget<Text>(find.byKey(const Key('home.journey.title'))).data,
        'Crystal Cavern',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('home.journey.next'))).data,
        '13 levels to Enchanted Garden',
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('home.journey.progress')),
      );
      expect(bar.value, closeTo(2 / 15, 1e-9));
      await leaveApp(tester);
    });

    testWidgets('a new player starts in the Midnight Lab', (tester) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      expect(
        tester.widget<Text>(find.byKey(const Key('home.journey.title'))).data,
        'Midnight Lab',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('home.journey.next'))).data,
        '10 levels to Crystal Cavern',
      );
      await leaveApp(tester);
    });

    Color gradientTop(WidgetTester tester) {
      final box = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AlchemyBackground),
              matching: find.byType(DecoratedBox),
            ),
          )
          .firstWhere((d) {
            final dec = d.decoration;
            return dec is BoxDecoration && dec.gradient is LinearGradient;
          });
      return ((box.decoration as BoxDecoration).gradient as LinearGradient)
          .colors
          .first;
    }

    testWidgets('the backdrop takes the colours of the current chapter', (
      tester,
    ) async {
      for (final (done, stage) in const [
        (0, 0),
        (10, 1),
        (25, 2),
        (50, 3),
        (90, 4),
      ]) {
        final c = await readyContainer(progress: completed(done));
        await pumpApp(tester, c);
        expect(gradientTop(tester), Journey.chapters[stage].top);
        await leaveApp(tester);
        c.dispose();
      }
    });

    testWidgets('the backdrop changes when a new chapter is reached', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(9));
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      expect(gradientTop(tester), Journey.chapters[0].top);
      await c
          .read(progressProvider.notifier)
          .recordCompletion(level: 10, stars: 3, moves: 9);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(gradientTop(tester), Journey.chapters[1].top);
      await leaveApp(tester);
    });

    testWidgets('the completion screen announces a new chapter', (
      tester,
    ) async {
      final c = await readyContainer(
        progress: completed(9),
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      final s = c.read(gameSessionProvider);
      await tester.runAsync(() => s.startLevel(10, resume: false));
      for (final m in const LevelGenerator().generate(10).solution) {
        final b = s.board!;
        b.tapBottle(m.source);
        b.tapBottle(m.destination);
        b.finishPour(b.activePour!.token);
      }
      c.read(appRouterProvider).push(AppRoutes.complete);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete.chapter')), findsOneWidget);
      expect(find.textContaining('CRYSTAL CAVERN'), findsOneWidget);
      expect(find.byKey(const Key('complete.chapter.tagline')), findsOneWidget);
      await leaveApp(tester);
    });
  });
}
