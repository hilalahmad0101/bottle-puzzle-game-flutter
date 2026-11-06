import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/app.dart';
import 'package:prism_pour/app/router/app_router.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/progression/star_rating.dart';
import 'package:prism_pour/features/collection/presentation/collection_screen.dart';
import 'package:prism_pour/features/complete/presentation/level_complete_screen.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/presentation/game_screen.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/home/presentation/home_screen.dart';
import 'package:prism_pour/features/levels/presentation/level_select_screen.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/features/settings/presentation/settings_screen.dart';
import 'package:prism_pour/features/splash/presentation/splash_screen.dart';

import 'package:prism_pour/shared/widgets/ambient_motion.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

PlayerProgress completed(int upTo, {int stars = 3}) => PlayerProgress(
  records: {
    for (var l = 1; l <= upTo; l++) l: LevelRecord(stars: stars, bestMoves: 20),
  },
);

Text textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

/// Taps bottle [i] (counted among the bottles currently on screen).
Future<void> tapBottle(WidgetTester tester, int i) async {
  await tester.tap(find.byType(BottleView).at(i));
  await tester.pump(const Duration(milliseconds: 50));
}

/// A whole pour: select, destination, wait for the animation to finish.
Future<void> pour(WidgetTester tester, int from, int to) async {
  await tapBottle(tester, from);
  await tapBottle(tester, to);
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

const level1 = [(0, 2), (1, 0), (1, 2)];

void main() {
  group('splash', () {
    testWidgets('shows the animated logo at once and moves on when ready', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      setScreen(tester, const Size(393, 873));
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PrismPourApp()),
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byType(SplashScreen),
        findsOneWidget,
        reason: 'animation still running',
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets('with reduced motion it leaves as soon as the data is ready', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      setScreen(tester, const Size(393, 873));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PrismPourApp()),
      );
      await tester.pump(); // post-frame
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets('a storage failure offers to try again instead of hanging', (
      tester,
    ) async {
      final broken = _FlakyRepo();
      final c = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(broken),
          ambientMotionProvider.overrideWithValue(false),
        ],
      );
      addTearDown(c.dispose);
      setScreen(tester, const Size(393, 873));
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const PrismPourApp()),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('TRY AGAIN'), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      broken.fail = false;
      await tester.tap(find.text('TRY AGAIN'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await leaveApp(tester);
    });
  });

  group('home', () {
    testWidgets(
      'a new player: PLAY on level 1, no stars, nothing to continue',
      (tester) async {
        final c = await readyContainer();
        addTearDown(c.dispose);
        await pumpApp(tester, c);
        expect(textOf(tester, 'home.level').data, '1');
        expect(textOf(tester, 'home.stars').data, '0');
        expect(textOf(tester, 'home.completed').data, '0 done');
        expect(find.text('PLAY'), findsOneWidget);
        expect(find.text('CONTINUE'), findsNothing);
        expect(find.byKey(const Key('home.startOver')), findsNothing);
        await leaveApp(tester);
      },
    );

    testWidgets('shows the real current level, stars and completed count', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(6, stars: 2));
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      expect(textOf(tester, 'home.level').data, '7');
      expect(textOf(tester, 'home.stars').data, '12');
      expect(textOf(tester, 'home.completed').data, '6 done');
      expect(find.text('Level 7'), findsWidgets);
      await leaveApp(tester);
    });

    testWidgets('PLAY starts the current level and opens the play screen', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(2));
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
      expect(c.read(gameSessionProvider).level!.levelNumber, 3);
      expect(textOf(tester, 'game.level').data, 'LEVEL 3');
      await leaveApp(tester);
    });

    testWidgets(
      'with an unfinished game: CONTINUE resumes it, START OVER discards it',
      (tester) async {
        final saved = SavedGame(
          level: 1,
          variant: 0,
          generatorVersion: 1,
          moves: const [MoveModel(0, 2)],
        );
        final c = await readyContainer(
          progress: PlayerProgress.empty.withSavedGame(saved),
        );
        addTearDown(c.dispose);
        await pumpApp(tester, c);
        expect(find.text('CONTINUE'), findsOneWidget);
        expect(find.textContaining('1 move made'), findsOneWidget);
        expect(find.byKey(const Key('home.startOver')), findsOneWidget);

        await tester.tap(find.byKey(const Key('home.play')));
        await tester.pumpAndSettle();
        expect(
          textOf(tester, 'game.moves').data,
          '1',
          reason: 'the saved move was replayed',
        );
        await leaveApp(tester);

        // Start over instead.
        final c2 = await readyContainer(
          progress: PlayerProgress.empty.withSavedGame(saved),
        );
        addTearDown(c2.dispose);
        await pumpApp(tester, c2);
        await tester.tap(find.byKey(const Key('home.startOver')));
        await tester.pumpAndSettle();
        expect(textOf(tester, 'game.moves').data, '0');
        expect(c2.read(progressProvider).saved.containsKey(1), isFalse);
        await leaveApp(tester);
      },
    );

    testWidgets('levels, collection and settings are reachable', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      for (final (key, type) in [
        ('home.levels', LevelSelectScreen),
        ('home.collection', CollectionScreen),
        ('home.settings', SettingsScreen),
      ]) {
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        expect(find.byType(type), findsOneWidget, reason: key);
        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(
          find.byType(HomeScreen),
          findsOneWidget,
          reason: 'back from $key',
        );
      }
      await leaveApp(tester);
    });
  });

  group('level selection', () {
    testWidgets(
      'completed, current and locked levels are distinguishable and labelled',
      (tester) async {
        final c = await readyContainer(
          progress: completed(3).withCompletion(level: 4, stars: 1, moves: 30),
        );
        addTearDown(c.dispose);
        final sem = tester.ensureSemantics();
        await pumpApp(tester, c, location: '/levels');
        expect(
          find.bySemanticsLabel(RegExp(r'^Level 1, completed, 3 stars')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(r'^Level 4, completed, 1 stars')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel('Level 5, current level'), findsOneWidget);
        expect(find.bySemanticsLabel('Level 6, locked'), findsOneWidget);
        expect(find.bySemanticsLabel('Level 10, locked'), findsOneWidget);
        sem.dispose();
        await leaveApp(tester);
      },
    );

    testWidgets('the summary shows the real totals', (tester) async {
      final c = await readyContainer(progress: completed(4, stars: 2));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      expect(textOf(tester, 'levels.stars').data, '8');
      expect(textOf(tester, 'levels.completed').data, '4');
      expect(textOf(tester, 'levels.current').data, '5');
      expect(find.text('CHAPTER 1'), findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets('tapping a locked level explains why and starts nothing', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(2));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      await tester.tap(find.byKey(const Key('level.8')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Complete level 3 to unlock level 8'), findsOneWidget);
      expect(c.read(gameSessionProvider).status, SessionStatus.idle);
      expect(find.byType(LevelSelectScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Complete level 3 to unlock level 8'), findsNothing);
      await leaveApp(tester);
    });

    testWidgets('tapping the current level plays it', (tester) async {
      final c = await readyContainer(progress: completed(2));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      await tester.tap(find.byKey(const Key('level.3')));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
      expect(textOf(tester, 'game.level').data, 'LEVEL 3');
      await leaveApp(tester);
    });

    testWidgets('a completed level can be replayed', (tester) async {
      final c = await readyContainer(progress: completed(5));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      await tester.tap(find.byKey(const Key('level.2')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.level').data, 'LEVEL 2');
      expect(
        c.read(progressProvider).currentLevel,
        6,
        reason: 'replaying does not move the current level',
      );
      await leaveApp(tester);
    });

    testWidgets('opens on the current chapter even at a very high level', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(56, stars: 1));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      expect(find.byKey(const Key('level.57')), findsOneWidget);
      expect(
        find.byKey(const Key('level.3')),
        findsNothing,
        reason: 'early levels are not even built',
      );
      await leaveApp(tester);
    });

    testWidgets('there is no last level: scrolling keeps producing chapters', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/levels');
      int highestBuilt() {
        var best = 0;
        for (final e
            in find
                .byWidgetPredicate(
                  (w) =>
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith('level.'),
                )
                .evaluate()) {
          best = [
            best,
            int.parse((e.widget.key! as ValueKey<String>).value.substring(6)),
          ].reduce((a, b) => a > b ? a : b);
        }
        return best;
      }

      expect(highestBuilt(), lessThan(100));
      for (var i = 0; i < 40; i++) {
        await tester.drag(
          find.byKey(const Key('levels.list')),
          const Offset(0, -900),
        );
        await tester.pump();
      }
      expect(
        highestBuilt(),
        greaterThan(700),
        reason: 'chapters keep appearing',
      );
      await leaveApp(tester);
    });

    testWidgets('a level with a game in progress is marked', (tester) async {
      final saved = SavedGame(
        level: 1,
        variant: 0,
        generatorVersion: 1,
        moves: const [MoveModel(0, 2)],
      );
      final c = await readyContainer(
        progress: PlayerProgress.empty.withSavedGame(saved),
      );
      addTearDown(c.dispose);
      final sem = tester.ensureSemantics();
      await pumpApp(tester, c, location: '/levels');
      expect(
        find.bySemanticsLabel('Level 1, current level, game in progress'),
        findsOneWidget,
      );
      sem.dispose();
      await leaveApp(tester);
    });
  });

  group('playing', () {
    Future<ProviderContainer> openLevel1(
      WidgetTester tester, {
      PlayerProgress? progress,
      Size? size,
    }) async {
      final c = await readyContainer(progress: progress);
      addTearDown(c.dispose);
      await pumpApp(tester, c, size: size ?? const Size(393, 873));
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('the HUD shows the real level, difficulty, moves and par', (
      tester,
    ) async {
      await openLevel1(tester);
      expect(textOf(tester, 'game.level').data, 'LEVEL 1');
      expect(textOf(tester, 'game.moves').data, '0');
      expect(textOf(tester, 'game.par').data, 'par 3');
      expect(find.text('Easy'), findsOneWidget);
      expect(find.byType(BottleView), findsNWidgets(3));
      await leaveApp(tester);
    });

    testWidgets('pouring updates the move counter; undo takes it back', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      await pour(tester, 0, 2);
      expect(textOf(tester, 'game.moves').data, '1');
      expect(c.read(gameSessionProvider).board!.committedMoves, [
        const MoveModel(0, 2),
      ]);
      await tester.tap(find.byKey(const Key('game.undo')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(textOf(tester, 'game.moves').data, '0');
      await leaveApp(tester);
    });

    testWidgets('undo is disabled until there is a move to undo', (
      tester,
    ) async {
      await openLevel1(tester);
      await tester.tap(find.byKey(const Key('game.undo')));
      await tester.pump();
      expect(textOf(tester, 'game.moves').data, '0');
      await pour(tester, 0, 2);
      final orb = find.byKey(const Key('game.undo'));
      expect(orb, findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets('the game is saved after every move and Continue finds it', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      await pour(tester, 0, 2);
      expect(c.read(progressProvider).saved[1]!.moves, [const MoveModel(0, 2)]);
      await tester.tap(find.byKey(const Key('game.pause')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pause.home')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.textContaining('1 move made'), findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets('restart with moves asks first; cancelling keeps them', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      await pour(tester, 0, 2);
      await tester.tap(find.byKey(const Key('game.restart')));
      await tester.pumpAndSettle();
      expect(find.text('RESTART LEVEL?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm.cancel')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '1');
      expect(c.read(gameSessionProvider).board!.isPaused, isFalse);

      await tester.tap(find.byKey(const Key('game.restart')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.restart')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '0');
      expect(c.read(progressProvider).saved, isEmpty);
      await leaveApp(tester);
    });

    testWidgets('restart with no moves needs no confirmation', (tester) async {
      await openLevel1(tester);
      await tester.tap(find.byKey(const Key('game.restart')));
      await tester.pumpAndSettle();
      expect(find.text('RESTART LEVEL?'), findsNothing);
      await leaveApp(tester);
    });

    testWidgets('a hint highlights exactly the two bottles to use', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      await tester.tap(find.byKey(const Key('game.hint')));
      var views = <BottleView>[];
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        views = tester.widgetList<BottleView>(find.byType(BottleView)).toList();
        if (views.any((v) => v.hint)) break;
      }
      expect(views.where((v) => v.hint).length, 2);
      final s = c.read(gameSessionProvider);
      expect(s.hintBottles.length, 2);
      // Tapping a bottle clears it.
      await tapBottle(tester, 0);
      expect(
        tester
            .widgetList<BottleView>(find.byType(BottleView))
            .any((v) => v.hint),
        isFalse,
      );
      await tapBottle(tester, 0);
      await tester.pump(const Duration(milliseconds: 500));
      await leaveApp(tester);
    });

    testWidgets('a selected bottle can be put down again', (tester) async {
      await openLevel1(tester);
      await tapBottle(tester, 0);
      expect(
        tester.widgetList<BottleView>(find.byType(BottleView)).first.selected,
        isTrue,
      );
      await tapBottle(tester, 0);
      expect(
        tester
            .widgetList<BottleView>(find.byType(BottleView))
            .any((v) => v.selected),
        isFalse,
      );
      await tester.pump(const Duration(milliseconds: 500));
      await leaveApp(tester);
    });
  });

  group('pause menu', () {
    Future<ProviderContainer> start(WidgetTester tester) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('game.pause')));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets(
      'shows resume, restart, settings and home; the board is locked',
      (tester) async {
        final c = await start(tester);
        expect(find.text('PAUSED'), findsOneWidget);
        for (final k in [
          'pause.resume',
          'pause.restart',
          'pause.settings',
          'pause.home',
        ]) {
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(c.read(gameSessionProvider).board!.isPaused, isTrue);
        expect(find.textContaining('Level 1'), findsWidgets);
        await leaveApp(tester);
      },
    );

    testWidgets('resume unlocks the board', (tester) async {
      final c = await start(tester);
      await tester.tap(find.byKey(const Key('pause.resume')));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsNothing);
      expect(c.read(gameSessionProvider).board!.isPaused, isFalse);
      await leaveApp(tester);
    });

    testWidgets('restart from the menu restarts the level', (tester) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      await pour(tester, 0, 2);
      await tester.tap(find.byKey(const Key('game.pause')));
      await tester.pumpAndSettle();
      expect(find.text('Level 1 · 1 move'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pause.restart')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '0');
      await leaveApp(tester);
    });

    testWidgets('settings opens, and returning brings the pause menu back', (
      tester,
    ) async {
      final c = await start(tester);
      await tester.tap(find.byKey(const Key('pause.settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(c.read(gameSessionProvider).board!.isPaused, isTrue);
      await tester.tap(find.byKey(const Key('pause.resume')));
      await tester.pumpAndSettle();
      await leaveApp(tester);
    });

    testWidgets('home leaves the game (it stays saved)', (tester) async {
      final c = await start(tester);
      await tester.tap(find.byKey(const Key('pause.home')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(c.read(gameSessionProvider).board!.isPaused, isFalse);
      await leaveApp(tester);
    });

    testWidgets(
      'the system back button opens the pause menu instead of leaving',
      (tester) async {
        await readyContainer().then((c) async {
          addTearDown(c.dispose);
          await pumpApp(tester, c);
          await tester.tap(find.byKey(const Key('home.play')));
          await tester.pumpAndSettle();
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byType(GameScreen), findsOneWidget);
          expect(find.text('PAUSED'), findsOneWidget);
        });
        await leaveApp(tester);
      },
    );

    testWidgets('tapping outside the menu resumes', (tester) async {
      final c = await start(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('PAUSED'), findsNothing);
      expect(c.read(gameSessionProvider).board!.isPaused, isFalse);
      await leaveApp(tester);
    });
  });

  group('completing a level, end to end', () {
    Future<ProviderContainer> solveLevel1(
      WidgetTester tester, {
      PlayerProgress? progress,
    }) async {
      final c = await readyContainer(progress: progress);
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      for (final m in level1) {
        await pour(tester, m.$1, m.$2);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('solving opens the completion screen with the real result', (
      tester,
    ) async {
      final c = await solveLevel1(tester);
      expect(find.byType(LevelCompleteScreen), findsOneWidget);
      expect(find.byKey(const Key('complete.title')), findsOneWidget);
      expect(textOf(tester, 'complete.level').data, 'Level 1');
      expect(textOf(tester, 'complete.moves').data, '3');
      expect(textOf(tester, 'complete.par').data, '3');
      expect(find.bySemanticsLabel('3 of 3 stars'), findsOneWidget);
      expect(find.byKey(const Key('complete.unlocked')), findsOneWidget);
      expect(find.text('LEVEL 2 UNLOCKED'), findsOneWidget);
      final p = c.read(progressProvider);
      expect(p.recordOf(1)!.stars, 3);
      expect(p.currentLevel, 2);
      await leaveApp(tester);
    });

    testWidgets(
      'the documented star rules are shown with this level\'s numbers',
      (tester) async {
        await solveLevel1(tester);
        final t = StarRating.thresholds(3);
        final rules = textOf(tester, 'complete.rules').data!;
        expect(rules, contains('${t.three} moves or fewer'));
        expect(rules, contains('${t.two} moves or fewer'));
        expect(rules, contains('finish the level'));
        await leaveApp(tester);
      },
    );

    testWidgets('NEXT LEVEL starts the next level', (tester) async {
      final c = await solveLevel1(tester);
      await tester.tap(find.byKey(const Key('complete.next')));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);
      expect(textOf(tester, 'game.level').data, 'LEVEL 2');
      expect(c.read(gameSessionProvider).moves, 0);
      await leaveApp(tester);
    });

    testWidgets('REPLAY starts the same level again, results are kept', (
      tester,
    ) async {
      final c = await solveLevel1(tester);
      await tester.tap(find.byKey(const Key('complete.replay')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.level').data, 'LEVEL 1');
      expect(textOf(tester, 'game.moves').data, '0');
      expect(c.read(progressProvider).recordOf(1)!.stars, 3);
      await leaveApp(tester);
    });

    testWidgets('HOME and LEVELS leave the screen', (tester) async {
      await solveLevel1(tester);
      await tester.tap(find.byKey(const Key('complete.home')));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LevelCompleteScreen), findsNothing);
      await leaveApp(tester);

      await solveLevel1(tester);
      await tester.tap(find.byKey(const Key('complete.levels')));
      await tester.pumpAndSettle();
      expect(find.byType(LevelSelectScreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await leaveApp(tester);
    });

    testWidgets(
      'there is no dead end: system back stays on the completion screen',
      (tester) async {
        await solveLevel1(tester);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(LevelCompleteScreen), findsOneWidget);
        await leaveApp(tester);
      },
    );

    testWidgets('earning stars that unlock a bottle style says so', (
      tester,
    ) async {
      // 12 stars from other levels; level 1 adds 3 => 15 = Crystal Prism.
      final others = PlayerProgress(
        records: {
          for (var l = 2; l <= 5; l++)
            l: const LevelRecord(stars: 3, bestMoves: 9),
        },
      );
      await solveLevel1(tester, progress: others);
      expect(
        find.byKey(const Key('complete.style.Crystal Prism')),
        findsOneWidget,
      );
      expect(find.text('NEW BOTTLE: CRYSTAL PRISM'), findsOneWidget);
      // Level 2 was already completed, so it is NOT "newly unlocked".
      expect(find.byKey(const Key('complete.unlocked')), findsNothing);
      await leaveApp(tester);
    });

    testWidgets(
      'replaying a level shows the previous best and flags improvements',
      (tester) async {
        final prior = PlayerProgress.empty.withCompletion(
          level: 1,
          stars: 1,
          moves: 9,
        );
        final c = await readyContainer(progress: prior);
        addTearDown(c.dispose);
        await pumpApp(tester, c, location: '/levels');
        await tester.tap(find.byKey(const Key('level.1')));
        await tester.pumpAndSettle();
        expect(textOf(tester, 'game.level').data, 'LEVEL 1');
        for (final m in level1) {
          await pour(tester, m.$1, m.$2);
        }
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('complete.newBest')), findsOneWidget);
        expect(textOf(tester, 'complete.best').data, '3');
        expect(
          find.byKey(const Key('complete.unlocked')),
          findsNothing,
          reason: 'level 1 was done before',
        );
        expect(c.read(progressProvider).recordOf(1)!.stars, 3);
        await leaveApp(tester);
      },
    );
  });

  group('collection', () {
    testWidgets('the free style is equipped; the others show what they need', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(2, stars: 2));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/collection');
      expect(textOf(tester, 'collection.stars').data, '4 stars earned');
      expect(
        find.byKey(const Key('style.alchemy_classic.equipped')),
        findsOneWidget,
      );
      expect(
        textOf(tester, 'style.crystal_prism.progress').data,
        '4 / 15 stars',
      );
      expect(textOf(tester, 'style.royal_glass.progress').data, '4 / 45 stars');
      await leaveApp(tester);
    });

    testWidgets('tapping a locked style says how many stars are missing', (
      tester,
    ) async {
      final c = await readyContainer(progress: completed(2, stars: 2));
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/collection');
      await tester.ensureVisible(
        find.byKey(const Key('style.crystal_prism.locked')),
      );
      await tester.tap(find.byKey(const Key('style.crystal_prism.locked')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Earn 11 more stars to unlock Crystal Prism'),
        findsOneWidget,
      );
      expect(c.read(appSettingsProvider).bottleStyleId, 'alchemy_classic');
      await tester.pump(const Duration(seconds: 3));
      await leaveApp(tester);
    });

    testWidgets(
      'an unlocked style can be equipped, is saved, and is used while playing',
      (tester) async {
        final repo = MemoryProgressRepository(progress: completed(5));
        final c = await readyContainer(repo: repo);
        addTearDown(c.dispose);
        await pumpApp(tester, c, location: '/collection');
        await tester.ensureVisible(
          find.byKey(const Key('style.crystal_prism.equip')),
        );
        await tester.tap(find.byKey(const Key('style.crystal_prism.equip')));
        await tester.pump();
        expect(
          find.byKey(const Key('style.crystal_prism.equipped')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('style.alchemy_classic.equip')),
          findsOneWidget,
        );
        expect(repo.settings.bottleStyleId, 'crystal_prism');

        c.read(appRouterProvider).go('/home');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('home.play')));
        await tester.pumpAndSettle();
        final styles = tester
            .widgetList<BottleView>(find.byType(BottleView))
            .map((v) => v.style.id)
            .toSet();
        expect(styles, {'crystal_prism'});
        await leaveApp(tester);
      },
    );

    testWidgets('unlocking exactly at the threshold works', (tester) async {
      final c = await readyContainer(
        progress: PlayerProgress(
          records: {
            for (var l = 1; l <= 5; l++)
              l: const LevelRecord(stars: 3, bestMoves: 9),
          },
        ),
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/collection');
      expect(
        find.byKey(const Key('style.crystal_prism.equip')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('style.royal_glass.locked')), findsOneWidget);
      await leaveApp(tester);
    });
  });

  group('settings', () {
    testWidgets('sound effects and haptics switch and persist', (tester) async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/settings');
      await tester.tap(find.byKey(const Key('settings.sfx')));
      await tester.pump();
      expect(c.read(appSettingsProvider).soundEffects, isFalse);
      expect(repo.settings.soundEffects, isFalse);
      await tester.tap(find.byKey(const Key('settings.haptics')));
      await tester.pump();
      expect(repo.settings.haptics, isFalse);
      await tester.tap(find.byKey(const Key('settings.haptics')));
      await tester.pump();
      expect(repo.settings.haptics, isTrue);
      await leaveApp(tester);
    });

    testWidgets('music is off by default and the switch works', (tester) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/settings');
      expect(c.read(appSettingsProvider).musicEnabled, isFalse);
      await tester.tap(find.byKey(const Key('settings.music')));
      await tester.pump();
      expect(c.read(appSettingsProvider).musicEnabled, isTrue);
      await tester.tap(find.byKey(const Key('settings.music')));
      await tester.pump();
      expect(c.read(appSettingsProvider).musicEnabled, isFalse);
      await leaveApp(tester);
    });

    testWidgets('animation speed and reduced motion', (tester) async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/settings');
      await tester.tap(find.byKey(const Key('settings.speed.fast')));
      await tester.pump();
      expect(repo.settings.speed.name, 'fast');
      await tester.tap(find.byKey(const Key('settings.motion.on')));
      await tester.pump();
      expect(repo.settings.motion.name, 'on');
      expect(c.read(animationSettingsProvider).motion.name, 'on');
      await tester.tap(find.byKey(const Key('settings.motion.off')));
      await tester.pump();
      expect(repo.settings.motion.name, 'off');
      await leaveApp(tester);
    });

    testWidgets('colour-blind mode changes the live preview bottles', (
      tester,
    ) async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 1400),
      );
      Iterable<String> assists() => [
        for (var i = 0; i < 4; i++)
          tester
              .widget<BottleView>(find.byKey(Key('settings.preview.$i')))
              .assist
              .name,
      ];
      expect(assists().toSet(), {'off'});
      for (final mode in ['symbols', 'patterns', 'both', 'off']) {
        await tester.ensureVisible(find.byKey(Key('settings.assist.$mode')));
        await tester.tap(find.byKey(Key('settings.assist.$mode')));
        await tester.pump();
        expect(assists().toSet(), {mode});
        expect(repo.settings.colorAssist.name, mode);
      }
      await leaveApp(tester);
    });

    testWidgets('colour-blind mode reaches the playing board', (tester) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier).setColorAssist(ColorAssist.both);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      final modes = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .map((v) => v.assist.name)
          .toSet();
      expect(modes, {'both'});
      await leaveApp(tester);
    });

    testWidgets('the star rules shown match the real constants', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 2400),
      );
      final rules = textOf(tester, 'settings.rules').data!;
      expect(rules, contains('${(StarRating.threeStarFactor * 100).round()}%'));
      expect(rules, contains('${(StarRating.twoStarFactor * 100).round()}%'));
      await leaveApp(tester);
    });

    testWidgets(
      'settings survive an app restart (same storage, new container)',
      (tester) async {
        final repo = MemoryProgressRepository();
        final c = await readyContainer(repo: repo);
        c.read(appSettingsProvider.notifier).setHaptics(false);
        c.read(appSettingsProvider.notifier).setSpeed(AnimationSpeed.fast);
        c.dispose();
        final c2 = await readyContainer(repo: repo);
        addTearDown(c2.dispose);
        expect(c2.read(appSettingsProvider).haptics, isFalse);
        expect(c2.read(appSettingsProvider).speed, AnimationSpeed.fast);
      },
    );
  });
}

class _FlakyRepo implements ProgressRepository {
  bool fail = true;
  final _mem = MemoryProgressRepository();

  @override
  Future<PlayerProgress> loadProgress() async {
    if (fail) throw StateError('storage unavailable');
    return _mem.loadProgress();
  }

  @override
  Future<void> saveProgress(PlayerProgress p) => _mem.saveProgress(p);

  @override
  Future<AppSettings> loadSettings() async {
    if (fail) throw StateError('storage unavailable');
    return _mem.loadSettings();
  }

  @override
  Future<void> saveSettings(AppSettings s) => _mem.saveSettings(s);

  @override
  Future<void> flush() => _mem.flush();

  @override
  Future<void> close() => _mem.close();

  @override
  List<String> takeNotices() => _mem.takeNotices();
}
