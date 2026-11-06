import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/game/animation/pour_board.dart';
import 'package:prism_pour/features/game/presentation/animation_lab_screen.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

Future<ProviderContainer> pumpLab(WidgetTester tester) async {
  final container = await readyContainer();
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(430, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AnimationLabScreen()),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

Future<void> leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('shows a board, scenarios, controls and readouts', (
    tester,
  ) async {
    await pumpLab(tester);
    expect(find.byType(PourBoard), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(find.byKey(Key('lab.scenario.$i')), findsOneWidget);
    }
    for (final k in [
      'lab.play',
      'lab.undo',
      'lab.reset',
      'lab.skip',
      'lab.pause',
      'lab.speed',
      'lab.motion',
      'lab.slow',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.textContaining('phase: idle'), findsOneWidget);
    expect(find.textContaining('Frame timing'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await leave(tester);
  });

  testWidgets('Play move: lift, then a pour; the readout shows the live plan', (
    tester,
  ) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('selected: 0'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('phase: pouring'), findsOneWidget);
    expect(find.textContaining('committed moves: 1'), findsOneWidget);
    expect(find.textContaining('quantity: 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('phase: idle'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await leave(tester);
  });

  testWidgets('Skip drops the animation but keeps the committed move', (
    tester,
  ) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('lab.skip')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.textContaining('phase: idle'), findsOneWidget);
    expect(find.textContaining('committed moves: 1'), findsOneWidget);
    expect(find.textContaining('last interruption: other'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('Undo and Reset interrupt a pour and report the reason', (
    tester,
  ) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('lab.undo')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.textContaining('committed moves: 0'), findsOneWidget);
    expect(find.textContaining('last interruption: undo'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(find.byKey(const Key('lab.reset')));
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.textContaining('committed moves: 0'), findsOneWidget);
    expect(find.textContaining('last interruption: reset'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('Pause locks the board and Resume unlocks it', (tester) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.pause')));
    await tester.pump();
    expect(find.textContaining('phase: paused'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      find.textContaining('committed moves: 0'),
      findsOneWidget,
      reason: 'paused: no move',
    );
    await tester.tap(find.byKey(const Key('lab.pause')));
    await tester.pump();
    expect(find.textContaining('phase: idle'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('speed and reduced-motion controls drive the shared settings', (
    tester,
  ) async {
    final c = await pumpLab(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('lab.speed')),
        matching: find.text('Fast'),
      ),
    );
    await tester.pump();
    expect(c.read(appSettingsProvider).speed, AnimationSpeed.fast);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('lab.motion')),
        matching: find.text('Reduced'),
      ),
    );
    await tester.pump();
    expect(c.read(appSettingsProvider).motion, MotionPreference.on);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.textContaining('reduced: true'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await leave(tester);
  });

  testWidgets('slow motion lengthens the animation', (tester) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    final normal = RegExp(r'duration: ([0-9.]+) s')
        .firstMatch(
          tester.widgetList<Text>(find.textContaining('duration:')).first.data!,
        )!
        .group(1)!;
    await tester.tap(find.byKey(const Key('lab.skip')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('lab.slow')),
        matching: find.text('4x slower'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab.undo')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    final slow = RegExp(r'duration: ([0-9.]+) s')
        .firstMatch(
          tester.widgetList<Text>(find.textContaining('duration:')).first.data!,
        )!
        .group(1)!;
    expect(double.parse(slow), closeTo(double.parse(normal) * 4, 0.05));
    await tester.tap(find.byKey(const Key('lab.skip')));
    await tester.pump(const Duration(milliseconds: 100));
    await leave(tester);
  });

  testWidgets('scrub mode freezes the animation and exposes a slider', (
    tester,
  ) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.scrubMode')));
    await tester.pump();
    expect(find.byKey(const Key('lab.scrub')), findsOneWidget);
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 5));
    expect(
      find.textContaining('phase: pouring'),
      findsOneWidget,
      reason: 'frozen while scrubbing',
    );
    await tester.drag(find.byKey(const Key('lab.scrub')), const Offset(120, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('lab.scrubMode'))); // release
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('phase: idle'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('geometry overlay and symbols toggles render without error', (
    tester,
  ) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.debug')));
    await tester.tap(find.byKey(const Key('lab.assist')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lab.play')));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await leave(tester);
  });

  testWidgets('every scenario loads and its suggested move plays to the end', (
    tester,
  ) async {
    await pumpLab(tester);
    for (var i = 0; i < 7; i++) {
      await tester.tap(find.byKey(Key('lab.scenario.$i')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lab.play')));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(
        find.textContaining('phase: idle'),
        findsOneWidget,
        reason: 'scenario $i',
      );
      expect(
        find.textContaining('committed moves: 1'),
        findsOneWidget,
        reason: 'scenario $i',
      );
      expect(tester.takeException(), isNull, reason: 'scenario $i');
    }
    await leave(tester);
  });

  testWidgets('the 12-bottle level scenario fits the screen', (tester) async {
    await pumpLab(tester);
    await tester.tap(find.byKey(const Key('lab.scenario.6')));
    await tester.pump();
    expect(find.byType(BottleView), findsNWidgets(12));
    await leave(tester);
  });

  testWidgets(
    'quantities 1, 2, 3 and 4 are animated for the matching scenarios',
    (tester) async {
      await pumpLab(tester);
      final expected = {0: 1, 1: 2, 2: 3, 4: 4};
      for (final e in expected.entries) {
        await tester.tap(find.byKey(Key('lab.scenario.${e.key}')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('lab.play')));
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          find.textContaining('quantity: ${e.value}'),
          findsOneWidget,
          reason: 'scenario ${e.key}',
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
      }
      await leave(tester);
    },
  );

  testWidgets('reachable from Settings > Developer tools', (tester) async {
    final c = await readyContainer();
    addTearDown(c.dispose);
    await pumpApp(
      tester,
      c,
      location: '/settings',
      size: const Size(430, 2600),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.animationLab')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('settings.animationLab')));
    await tester.tap(find.byKey(const Key('settings.animationLab')));
    await tester.pumpAndSettle();
    expect(find.byType(AnimationLabScreen), findsOneWidget);
    await leave(tester);
  });
}
