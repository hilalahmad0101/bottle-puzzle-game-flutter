import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';

import '../../support/pump_app.dart';
import '../../support/sqlite_support.dart';
import '../../support/test_app.dart';

Text textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

/// One launch of the real app on the database [path].
Future<(ProviderContainer, RealZoneRepo)> launch(
  WidgetTester tester,
  String path,
) async {
  final repo = RealZoneRepo(repoAt(path));
  final c = (await tester.runAsync(
    () => readyContainer(repo: repo, feedback: RecordingFeedback()),
  ))!;
  return (c, repo);
}

/// Ends a launch: lets queued writes finish, then closes the database.
Future<void> shutdown(
  WidgetTester tester,
  ProviderContainer c,
  RealZoneRepo repo,
) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await leaveApp(tester);
  await tester.runAsync(() async {
    await repo.settle();
    c.dispose();
    await repo.close();
  });
}

Future<void> tapBottle(WidgetTester tester, int i) async {
  await tester.tap(find.byType(BottleView).at(i));
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> pour(WidgetTester tester, int from, int to) async {
  await tapBottle(tester, from);
  await tapBottle(tester, to);
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
}

void main() {
  testWidgets(
    'play, move, close the app, reopen: Continue resumes exactly there',
    (tester) async {
      final path = dbPathIn(tempDir());
      var (c, repo) = await launch(tester, path);
      await pumpApp(tester, c);
      expect(find.text('PLAY'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      await pour(tester, 0, 2);
      expect(textOf(tester, 'game.moves').data, '1');
      await shutdown(tester, c, repo);

      // ---- the app is started again ----
      (c, repo) = await launch(tester, path);
      await pumpApp(tester, c);
      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.textContaining('1 move made'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.level').data, 'LEVEL 1');
      expect(textOf(tester, 'game.moves').data, '1');
      // And it can be finished from there.
      await pour(tester, 1, 0);
      await pour(tester, 1, 2);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete.title')), findsOneWidget);
      await shutdown(tester, c, repo);
    },
  );

  testWidgets(
    'winning, closing and reopening continues with the NEXT numbered level',
    (tester) async {
      final path = dbPathIn(tempDir());
      var (c, repo) = await launch(tester, path);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      for (final m in const [(0, 2), (1, 0), (1, 2)]) {
        await pour(tester, m.$1, m.$2);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete.title')), findsOneWidget);
      await shutdown(tester, c, repo);

      (c, repo) = await launch(tester, path);
      await pumpApp(tester, c);
      expect(textOf(tester, 'home.level').data, '2');
      expect(textOf(tester, 'home.stars').data, '3');
      expect(textOf(tester, 'home.completed').data, '1 done');
      expect(
        find.text('PLAY'),
        findsOneWidget,
        reason: 'nothing to continue: the finished game is gone',
      );
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.level').data, 'LEVEL 2');
      await shutdown(tester, c, repo);
    },
  );

  group('level selection after a restart', () {
    late String path;
    setUp(() async {
      path = dbPathIn(tempDir());
      final seed = repoAt(path);
      final p0 = await seed.loadProgress();
      await seed.saveProgress(
        p0
            .withCompletion(level: 1, stars: 3, moves: 3)
            .withCompletion(level: 2, stars: 1, moves: 12),
      );
      await seed.close();
    });

    testWidgets('shows the persisted progress', (tester) async {
      final (c, repo) = await launch(tester, path);
      final sem = tester.ensureSemantics();
      await pumpApp(tester, c, location: '/levels');
      expect(
        find.bySemanticsLabel(RegExp(r'^Level 1, completed, 3 stars')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Level 2, completed, 1 stars')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Level 3, current level'), findsOneWidget);
      expect(find.bySemanticsLabel('Level 4, locked'), findsOneWidget);
      expect(textOf(tester, 'levels.stars').data, '4');
      sem.dispose();
      await shutdown(tester, c, repo);
    });
  });

  group('bottle styles after a restart', () {
    late String path;
    setUp(() async {
      path = dbPathIn(tempDir());
      final seed = repoAt(path);
      var p = await seed.loadProgress();
      for (var l = 1; l <= 5; l++) {
        p = p.withCompletion(level: l, stars: 3, moves: 10);
      }
      await seed.saveProgress(p);
      await seed.close();
    });

    testWidgets('earned styles are unlocked and the chosen one is remembered', (
      tester,
    ) async {
      final (c, repo) = await launch(tester, path);
      await pumpApp(tester, c, location: '/collection');
      expect(
        find.byKey(const Key('style.crystal_prism.equip')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('style.royal_glass.locked')), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const Key('style.crystal_prism.equip')),
      );
      await tester.tap(find.byKey(const Key('style.crystal_prism.equip')));
      await tester.pump();
      await shutdown(tester, c, repo);

      final (c2, repo2) = await launch(tester, path);
      await pumpApp(tester, c2, location: '/collection');
      expect(
        find.byKey(const Key('style.crystal_prism.equipped')),
        findsOneWidget,
        reason: 'the choice was remembered',
      );
      await shutdown(tester, c2, repo2);
    });
  });

  group('statistics', () {
    late String path;
    setUp(() async {
      path = dbPathIn(tempDir());
      final seed = repoAt(path);
      final p0 = await seed.loadProgress();
      await seed.saveProgress(
        p0
            .withCompletion(level: 1, stars: 3, moves: 3)
            .withCompletion(level: 2, stars: 2, moves: 6)
            .withHint(2, requested: 3, shown: 2)
            .withHint(5, requested: 1, shown: 1),
      );
      await seed.close();
    });

    testWidgets('the panel shows real saved numbers', (tester) async {
      final (c, repo) = await launch(tester, path);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 2600),
      );
      expect(textOf(tester, 'settings.stats.completed').data, '2');
      expect(textOf(tester, 'settings.stats.stars').data, '5');
      expect(textOf(tester, 'settings.stats.current').data, '3');
      expect(textOf(tester, 'settings.stats.hints').data, '3');
      expect(
        textOf(tester, 'settings.stats.styles').data,
        '1 / ${BottleStyles.all.length}',
      );
      await shutdown(tester, c, repo);
    });
  });

  testWidgets(
    'a damaged save file: the app still opens, says so once, and keeps a backup',
    (tester) async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      File(path).writeAsBytesSync(List<int>.filled(6000, 9));
      final (c, repo) = await launch(tester, path);
      await pumpApp(tester, c);
      expect(find.byKey(const Key('home.notice')), findsOneWidget);
      expect(find.textContaining('damaged'), findsOneWidget);
      expect(textOf(tester, 'home.level').data, '1');
      await tester.tap(find.byKey(const Key('home.notice')));
      await tester.pump();
      expect(find.byKey(const Key('home.notice')), findsNothing);
      expect(dir.listSync().any((f) => f.path.contains('.corrupt-1')), isTrue);
      await shutdown(tester, c, repo);
    },
  );

  testWidgets('an undamaged start shows no notice', (tester) async {
    final (c, repo) = await launch(tester, dbPathIn(tempDir()));
    await pumpApp(tester, c);
    expect(find.byKey(const Key('home.notice')), findsNothing);
    await shutdown(tester, c, repo);
  });

  group('going to the background', () {
    testWidgets(
      'pending data is flushed when the app is paused, hidden or inactive',
      (tester) async {
        final repo = MemoryProgressRepository();
        final c = await readyContainer(
          repo: repo,
          feedback: RecordingFeedback(),
        );
        addTearDown(c.dispose);
        await pumpApp(tester, c);
        expect(repo.flushes, 0);
        for (final (i, state) in [
          AppLifecycleState.inactive,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
        ].indexed) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
          expect(repo.flushes, i + 1, reason: '$state');
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(repo.flushes, 3, reason: 'coming back needs no flush');
        await leaveApp(tester);
      },
    );

    testWidgets('a flush that fails does not crash the app', (tester) async {
      final c = await readyContainer(
        repo: _FailingFlush(),
        feedback: RecordingFeedback(),
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await leaveApp(tester);
    });

    testWidgets(
      'backgrounding mid-pour: the move is already saved and the animation is dropped',
      (tester) async {
        final path = dbPathIn(tempDir());
        var (c, repo) = await launch(tester, path);
        await pumpApp(tester, c);
        await tester.tap(find.byKey(const Key('home.play')));
        await tester.pumpAndSettle();
        await tapBottle(tester, 0);
        await tapBottle(tester, 2); // a pour is now animating
        await tester.pump(const Duration(milliseconds: 300));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(c.read(gameSessionProvider).board!.isPouring, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await shutdown(tester, c, repo);

        (c, repo) = await launch(tester, path);
        expect(c.read(progressProvider).continueGame!.moves.length, 1);
        await pumpApp(tester, c);
        await tester.tap(find.byKey(const Key('home.play')));
        await tester.pumpAndSettle();
        expect(textOf(tester, 'game.moves').data, '1');
        await shutdown(tester, c, repo);
      },
    );
  });

  testWidgets('settings changed in one session are still set in the next', (
    tester,
  ) async {
    final path = dbPathIn(tempDir());
    var (c, repo) = await launch(tester, path);
    await pumpApp(tester, c, location: '/settings');
    await tester.tap(find.byKey(const Key('settings.haptics')));
    await tester.tap(find.byKey(const Key('settings.speed.fast')));
    await tester.pump();
    await shutdown(tester, c, repo);
    (c, repo) = await launch(tester, path);
    expect(c.read(appSettingsProvider).haptics, isFalse);
    expect(c.read(appSettingsProvider).speed.name, 'fast');
    await shutdown(tester, c, repo);
  });
}

class _FailingFlush extends MemoryProgressRepository {
  @override
  Future<void> flush() async => throw StateError('disk gone');
}
