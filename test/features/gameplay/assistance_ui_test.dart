import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/complete/presentation/level_complete_screen.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

Text textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key)));

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

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump(const Duration(milliseconds: 100));
}

const _level1 = [(0, 2), (1, 0), (1, 2)];

void main() {
  Future<ProviderContainer> openLevel1(
    WidgetTester tester, {
    AppSettings? settings,
    Size size = const Size(393, 873),
    RecordingFeedback? feedback,
  }) async {
    final c = await readyContainer(
      settings: settings,
      feedback: feedback ?? RecordingFeedback(),
    );
    addTearDown(c.dispose);
    await pumpApp(tester, c, size: size);
    await tester.tap(find.byKey(const Key('home.play')));
    await tester.pumpAndSettle();
    return c;
  }

  const boosterOn = AppSettings(extraBottleBooster: true);

  group('buttons', () {
    testWidgets('undo, hint and restart are there; the booster is not', (
      tester,
    ) async {
      await openLevel1(tester);
      expect(find.byKey(const Key('game.undo')), findsOneWidget);
      expect(find.byKey(const Key('game.hint')), findsOneWidget);
      expect(find.byKey(const Key('game.restart')), findsOneWidget);
      expect(find.byKey(const Key('game.pause')), findsOneWidget);
      expect(
        find.byKey(const Key('game.booster')),
        findsNothing,
        reason: 'disabled by default',
      );
      await leaveApp(tester);
    });

    testWidgets('every control is an accessible touch target', (tester) async {
      await openLevel1(tester, settings: boosterOn);
      for (final k in const [
        'game.undo',
        'game.hint',
        'game.restart',
        'game.booster',
        'game.pause',
      ]) {
        final size = tester.getSize(find.byKey(Key(k)));
        expect(size.width, greaterThanOrEqualTo(48), reason: '$k width');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$k height');
      }
      await leaveApp(tester);
    });

    testWidgets('controls carry spoken labels', (tester) async {
      final handle = tester.ensureSemantics();
      await openLevel1(tester, settings: boosterOn);
      for (final label in const [
        'Undo',
        'Hint',
        'Restart',
        'Bottle',
        'Pause',
      ]) {
        expect(
          find.bySemanticsLabel(RegExp(label)),
          findsWidgets,
          reason: label,
        );
      }
      handle.dispose();
      await leaveApp(tester);
    });

    testWidgets('everything fits a small phone with the booster on', (
      tester,
    ) async {
      await openLevel1(tester, settings: boosterOn, size: const Size(320, 568));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('game.booster')), findsOneWidget);
      await leaveApp(tester);
    });
  });

  group('unavailable actions explain themselves', () {
    testWidgets('undo with nothing to undo says so and buzzes', (tester) async {
      final fb = RecordingFeedback();
      await openLevel1(tester, feedback: fb);
      fb.calls.clear();
      await tapKey(tester, 'game.undo');
      expect(find.text('Nothing to undo yet.'), findsOneWidget);
      expect(fb.calls, contains('heavy'));
      expect(textOf(tester, 'game.moves').data, '0');
      await tester.pump(const Duration(seconds: 4)); // the toast fades
      await leaveApp(tester);
    });

    testWidgets('hint during a pour says to wait', (tester) async {
      await openLevel1(tester);
      await tapBottle(tester, 0);
      await tapBottle(tester, 2); // pouring
      await tapKey(tester, 'game.hint');
      expect(find.text('Wait for the pour to finish.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await leaveApp(tester);
    });

    testWidgets('the used booster explains why it is greyed out', (
      tester,
    ) async {
      await openLevel1(tester, settings: boosterOn);
      await tapKey(tester, 'game.booster');
      await tester.tap(find.byKey(const Key('confirm.booster')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'game.booster');
      expect(find.text('The extra bottle is already in play.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await leaveApp(tester);
    });
  });

  group('undo', () {
    testWidgets('takes the move back and animates the liquid returning', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      final s = c.read(gameSessionProvider);
      final start = s.board!.committedState;
      await pour(tester, 0, 2);
      expect(textOf(tester, 'game.moves').data, '1');
      await tapKey(tester, 'game.undo');
      // Counter and board are back immediately; the picture follows.
      expect(textOf(tester, 'game.moves').data, '0');
      expect(s.board!.committedState, start);
      expect(s.board!.activePour?.isUndo, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(s.board!.isPouring, isFalse);
      expect(s.board!.committedState, start);
      await leaveApp(tester);
    });

    testWidgets('several undos in a row, even while one is animating', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      final s = c.read(gameSessionProvider);
      await pour(tester, 0, 2);
      await pour(tester, 1, 0);
      expect(textOf(tester, 'game.moves').data, '2');
      await tapKey(tester, 'game.undo');
      await tapKey(tester, 'game.undo'); // first still animating
      expect(textOf(tester, 'game.moves').data, '0');
      expect(s.board!.committedState, s.level!.puzzle);
      await tester.pump(const Duration(seconds: 4));
      await tapKey(tester, 'game.undo');
      expect(find.text('Nothing to undo yet.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await leaveApp(tester);
    });

    testWidgets('the board is playable again after an undo', (tester) async {
      await openLevel1(tester);
      await pour(tester, 0, 2);
      await tapKey(tester, 'game.undo');
      await tester.pump(const Duration(seconds: 4));
      await pour(tester, 0, 2);
      expect(textOf(tester, 'game.moves').data, '1');
      await leaveApp(tester);
    });
  });

  group('move counter', () {
    testWidgets('invalid taps do not count', (tester) async {
      await openLevel1(tester);
      await tapBottle(tester, 2); // empty bottle
      await tapBottle(tester, 0); // select
      await tapBottle(tester, 1); // colour mismatch -> reselect
      await tapBottle(tester, 1); // deselect
      expect(textOf(tester, 'game.moves').data, '0');
      await pour(tester, 0, 2);
      expect(textOf(tester, 'game.moves').data, '1');
      await leaveApp(tester);
    });
  });

  group('hint', () {
    testWidgets('highlights two bottles and does not move anything', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      final s = c.read(gameSessionProvider);
      await tester.runAsync(() async {
        await s.requestHint();
      });
      await tester.pump(const Duration(milliseconds: 300));
      final hinted = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .where((b) => b.hint)
          .length;
      expect(hinted, 2);
      expect(textOf(tester, 'game.moves').data, '0');
      expect(s.board!.committedState, s.level!.puzzle);
      await tester.pump(const Duration(seconds: 2));
      expect(s.moves, 0, reason: 'never plays by itself');
      await leaveApp(tester);
    });

    testWidgets('tapping the hint button shows a hint', (tester) async {
      await openLevel1(tester);
      await tester.tap(find.byKey(const Key('game.hint')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final hinted = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .where((b) => b.hint)
          .length;
      expect(hinted, 2);
      await leaveApp(tester);
    });
  });

  group('restart', () {
    testWidgets('with no moves it restarts at once, no question', (
      tester,
    ) async {
      await openLevel1(tester);
      await tapKey(tester, 'game.restart');
      expect(find.byKey(const Key('confirm.restart')), findsNothing);
      expect(textOf(tester, 'game.level').data, 'LEVEL 1');
      await leaveApp(tester);
    });

    testWidgets('after moves it asks; keep playing changes nothing', (
      tester,
    ) async {
      await openLevel1(tester);
      await pour(tester, 0, 2);
      await tapKey(tester, 'game.restart');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm.restart')), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm.cancel')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '1');
      await leaveApp(tester);
    });

    testWidgets('confirming restores the original layout, same level', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      final s = c.read(gameSessionProvider);
      final seed = s.level!.seed;
      await pour(tester, 0, 2);
      await pour(tester, 1, 0);
      await tapKey(tester, 'game.restart');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.restart')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '0');
      expect(textOf(tester, 'game.level').data, 'LEVEL 1');
      expect(s.board!.committedState, s.level!.puzzle);
      expect(s.level!.seed, seed);
      await leaveApp(tester);
    });
  });

  group('pause', () {
    testWidgets('the menu stops play; resume continues where it was', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      final s = c.read(gameSessionProvider);
      await pour(tester, 0, 2);
      await tapKey(tester, 'game.pause');
      await tester.pumpAndSettle();
      expect(s.isPaused, isTrue);
      expect(find.byKey(const Key('pause.resume')), findsOneWidget);
      expect(s.board!.tapBottle(1).kind.name, 'busy');
      await tester.tap(find.byKey(const Key('pause.resume')));
      await tester.pumpAndSettle();
      expect(s.isPaused, isFalse);
      expect(textOf(tester, 'game.moves').data, '1');
      await pour(tester, 1, 0);
      expect(textOf(tester, 'game.moves').data, '2');
      await leaveApp(tester);
    });
  });

  group('extra bottle booster', () {
    testWidgets('appears only when switched on and asks before adding', (
      tester,
    ) async {
      final c = await openLevel1(tester, settings: boosterOn);
      expect(find.byType(BottleView), findsNWidgets(3));
      await tapKey(tester, 'game.booster');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm.booster')), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm.booster.cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(BottleView), findsNWidgets(3), reason: 'declined');
      expect(c.read(gameSessionProvider).boosted, isFalse);

      await tapKey(tester, 'game.booster');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.booster')));
      await tester.pumpAndSettle();
      expect(find.byType(BottleView), findsNWidgets(4));
      expect(c.read(gameSessionProvider).boosted, isTrue);
      await leaveApp(tester);
    });

    testWidgets('a move made before the booster is kept', (tester) async {
      await openLevel1(tester, settings: boosterOn);
      await pour(tester, 0, 2);
      await tapKey(tester, 'game.booster');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.booster')));
      await tester.pumpAndSettle();
      expect(textOf(tester, 'game.moves').data, '1');
      expect(find.byType(BottleView), findsNWidgets(4));
      await leaveApp(tester);
    });

    testWidgets('the extra bottle takes part and the level is still won', (
      tester,
    ) async {
      final c = await openLevel1(tester, settings: boosterOn);
      await tapKey(tester, 'game.booster');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.booster')));
      await tester.pumpAndSettle();
      for (final m in _level1) {
        await pour(tester, m.$1, m.$2);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(LevelCompleteScreen), findsOneWidget);
      expect(find.byKey(const Key('complete.assisted')), findsOneWidget);
      expect(c.read(gameSessionProvider).result!.stars, 1);
      await leaveApp(tester);
    });

    testWidgets('a standard win shows no assisted badge, full stars', (
      tester,
    ) async {
      final c = await openLevel1(tester);
      for (final m in _level1) {
        await pour(tester, m.$1, m.$2);
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('complete.assisted')), findsNothing);
      expect(c.read(gameSessionProvider).result!.stars, 3);
      await leaveApp(tester);
    });

    testWidgets('restart takes the extra bottle away again', (tester) async {
      await openLevel1(tester, settings: boosterOn);
      await tapKey(tester, 'game.booster');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm.booster')));
      await tester.pumpAndSettle();
      expect(find.byType(BottleView), findsNWidgets(4));
      await tapKey(tester, 'game.restart');
      await tester.pumpAndSettle();
      expect(find.byType(BottleView), findsNWidgets(3));
      await leaveApp(tester);
    });
  });

  group('settings switch', () {
    testWidgets('is off by default and turning it on is remembered', (
      tester,
    ) async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo, feedback: RecordingFeedback());
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(430, 2600),
      );
      expect(c.read(appSettingsProvider).extraBottleBooster, isFalse);
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.booster')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('settings.booster')));
      await tester.pumpAndSettle();
      expect(c.read(appSettingsProvider).extraBottleBooster, isTrue);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(repo.settings.extraBottleBooster, isTrue);
      await leaveApp(tester);
    });
  });
}
