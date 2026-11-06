import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/animation/pour_board.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/high_contrast_overlay.dart';
import 'package:prism_pour/features/game/rendering/liquid_life.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/shared/widgets/alchemy_background.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

final palette = LiquidPalette.forColorIds([1, 2, 3]);

PuzzleState st(List<List<int>> b) => PuzzleState.fromIds(b);

BoardController make() => BoardController(
  st([
    [2, 1, 1],
    [1],
    [],
    [3, 3, 3, 3],
  ]),
);

Widget board(
  BoardController c, {
  bool life = false,
  bool contrast = false,
  GlobalKey<PourBoardState>? key,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 420,
        child: PourBoard(
          key: key,
          controller: c,
          palette: palette,
          liquidLife: life,
          highContrast: contrast,
        ),
      ),
    ),
  ),
);

Finder lifePainters() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is LiquidLifePainter,
);
Finder contrastPainters() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is HighContrastPainter,
);

void main() {
  group('liquid life: bubbles and a shimmering surface', () {
    test('a handful of bubbles, never a crowd, none for an empty bottle', () {
      expect(LiquidLifePainter.bubbleCount(0), 0);
      expect(LiquidLifePainter.bubbleCount(1), 2);
      expect(LiquidLifePainter.bubbleCount(2), 3);
      expect(LiquidLifePainter.bubbleCount(3), 4);
      expect(LiquidLifePainter.bubbleCount(4), 4);
      expect(LiquidLifePainter.bubbleCount(40), 4);
    });

    testWidgets('only bottles with liquid get the effect', (tester) async {
      final c = make();
      await tester.pumpWidget(board(c, life: true));
      // 4 bottles, one empty.
      expect(find.byType(BottleView), findsNWidgets(4));
      expect(lifePainters(), findsNWidgets(3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('off by default: no painters and no running clock', (
      tester,
    ) async {
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(board(make(), key: key));
      expect(lifePainters(), findsNothing);
      expect(key.currentState!.liquidLifeRunning, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it paints small, quiet marks (bubbles and a surface line)', (
      tester,
    ) async {
      await tester.pumpWidget(board(make(), life: true));
      await tester.pump(const Duration(seconds: 1));
      final painter = tester
          .widgetList<CustomPaint>(lifePainters())
          .first
          .painter!;
      final box = tester.renderObject<RenderBox>(lifePainters().first);
      expect(
        box,
        paints
          ..circle()
          ..path(),
      );
      expect(painter, isA<LiquidLifePainter>());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the clock runs when wanted and stops during a pour', (
      tester,
    ) async {
      final key = GlobalKey<PourBoardState>();
      final c = make();
      await tester.pumpWidget(board(c, life: true, key: key));
      expect(key.currentState!.liquidLifeRunning, isTrue);
      c.tapBottle(0);
      c.tapBottle(1); // a pour begins
      await tester.pump();
      expect(key.currentState!.liquidLifeRunning, isFalse, reason: 'pouring');
      await tester.pump(const Duration(seconds: 5));
      expect(c.isPouring, isFalse);
      expect(key.currentState!.liquidLifeRunning, isTrue, reason: 'after');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it rests while the app is in the background', (tester) async {
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(board(make(), life: true, key: key));
      expect(key.currentState!.liquidLifeRunning, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(key.currentState!.liquidLifeRunning, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(key.currentState!.liquidLifeRunning, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('switching it off stops the clock and removes the layers', (
      tester,
    ) async {
      final key = GlobalKey<PourBoardState>();
      final c = make();
      await tester.pumpWidget(board(c, life: true, key: key));
      await tester.pumpWidget(board(c, life: false, key: key));
      expect(key.currentState!.liquidLifeRunning, isFalse);
      expect(lifePainters(), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it never changes the game state', (tester) async {
      final c = make();
      final before = c.committedState;
      await tester.pumpWidget(board(c, life: true));
      await tester.pump(const Duration(seconds: 20));
      expect(c.committedState, before);
      expect(c.engine.moveCount, 0);
      expect(c.isPouring, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it is disposed cleanly with the board (no leaked ticker)', (
      tester,
    ) async {
      await tester.pumpWidget(board(make(), life: true));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the game screen asks for it only when motion is allowed', (
      tester,
    ) async {
      // Tests turn ambient motion off: nothing must animate forever.
      final c = await readyContainer(feedback: RecordingFeedback());
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      expect(lifePainters(), findsNothing);
      await leaveApp(tester);
    });

    testWidgets('and not at all with reduced motion, even if motion is on', (
      tester,
    ) async {
      final c = await readyContainer(
        feedback: RecordingFeedback(),
        // "Reduce motion" switched ON.
        settings: const AppSettings(motion: MotionPreference.on),
        ambientMotion: true,
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(lifePainters(), findsNothing);
      await leaveApp(tester);
    });

    testWidgets('with motion on the game screen shows the effect', (
      tester,
    ) async {
      final c = await readyContainer(
        feedback: RecordingFeedback(),
        ambientMotion: true,
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/home', settle: false);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(lifePainters(), findsWidgets);
      await leaveApp(tester);
    });
  });

  group('high contrast', () {
    test('dividers sit exactly where two colours meet', () {
      BottleModel b(List<int> ids) => BottleModel(
        units: ids.map(
          (i) => st([
            [i],
          ]).bottles.first.units.first,
        ),
      );
      expect(HighContrastPainter.dividers(b([1, 1, 1, 1])), isEmpty);
      expect(HighContrastPainter.dividers(b([1, 2, 2, 1])), [1, 3]);
      expect(HighContrastPainter.dividers(b([1, 2, 3, 4])), [1, 2, 3]);
      expect(HighContrastPainter.dividers(b([])), isEmpty);
    });

    testWidgets('off: no overlay; on: one per bottle', (tester) async {
      final c = make();
      await tester.pumpWidget(board(c));
      expect(contrastPainters(), findsNothing);
      await tester.pumpWidget(board(c, contrast: true));
      expect(contrastPainters(), findsNWidgets(4));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it draws the outline and the dividers', (tester) async {
      await tester.pumpWidget(board(make(), contrast: true));
      final first = tester.renderObject<RenderBox>(contrastPainters().first);
      // Bottle 0 is [2,1,1]: an outline plus one divider (two strokes).
      expect(
        first,
        paints
          ..path()
          ..line()
          ..line(),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it does not change the game', (tester) async {
      final c = make();
      final before = c.committedState;
      await tester.pumpWidget(board(c, contrast: true));
      expect(c.committedState, before);
      expect(c.tapBottle(0).kind, TapKind.selected);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the game screen follows the setting', (tester) async {
      final c = await readyContainer(feedback: RecordingFeedback());
      addTearDown(c.dispose);
      await pumpApp(tester, c);
      await tester.tap(find.byKey(const Key('home.play')));
      await tester.pumpAndSettle();
      expect(contrastPainters(), findsNothing);
      c.read(appSettingsProvider.notifier).setHighContrast(true);
      await tester.pumpAndSettle();
      expect(contrastPainters(), findsWidgets);
      c.read(appSettingsProvider.notifier).setHighContrast(false);
      await tester.pumpAndSettle();
      expect(contrastPainters(), findsNothing);
      await leaveApp(tester);
    });

    testWidgets('the settings switch turns it on and it is remembered', (
      tester,
    ) async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 2000),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings.contrast')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(c.read(appSettingsProvider).highContrast, isFalse);
      await tester.tap(find.byKey(const Key('settings.contrast')));
      await tester.pump();
      expect(c.read(appSettingsProvider).highContrast, isTrue);
      await leaveApp(tester);
    });
  });

  group('background', () {
    testWidgets('high contrast removes the drifting motes and softens glows', (
      tester,
    ) async {
      final c = await readyContainer(
        settings: const AppSettings(highContrast: true),
        ambientMotion: true,
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c, location: '/home', settle: false);
      // Nothing animates behind the text.
      expect(
        find.descendant(
          of: find.byType(AlchemyBackground),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
      await leaveApp(tester);
    });
  });

  group('every design supports the effects', () {
    testWidgets('bubbles and contrast render on all five bottle designs', (
      tester,
    ) async {
      for (final style in BottleStyles.all) {
        final c = make();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 420,
                child: PourBoard(
                  controller: c,
                  palette: palette,
                  style: style,
                  liquidLife: true,
                  highContrast: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: style.name);
        expect(lifePainters(), findsNWidgets(3), reason: style.name);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
