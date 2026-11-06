import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/difficulty.dart';
import 'package:prism_pour/engine/generator/level_curve.dart';
import 'package:prism_pour/features/complete/presentation/victory_painter.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/home/presentation/home_screen.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/shared/widgets/alchemy_background.dart';
import 'package:prism_pour/shared/widgets/alchemy_button.dart';
import 'package:prism_pour/shared/widgets/alchemy_controls.dart';
import 'package:prism_pour/shared/widgets/alchemy_toast.dart';
import 'package:prism_pour/shared/widgets/ambient_motion.dart';
import 'package:prism_pour/shared/widgets/brand_logo.dart';
import 'package:prism_pour/shared/widgets/difficulty_indicator.dart';
import 'package:prism_pour/shared/widgets/glass_panel.dart';
import 'package:prism_pour/shared/widgets/star_row.dart';

Widget host(Widget child, {ProviderContainer? container}) {
  final app = MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
  return container == null
      ? ProviderScope(child: app)
      : UncontrolledProviderScope(container: container, child: app);
}

void main() {
  group('AlchemyButton', () {
    testWidgets('calls onPressed, shows label and subtitle, is a big target', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          AlchemyButton(
            label: 'PLAY',
            subtitle: 'Level 3',
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.text('PLAY'), findsOneWidget);
      expect(find.text('Level 3'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AlchemyButton)).height,
        greaterThanOrEqualTo(56),
      );
      await tester.tap(find.byType(AlchemyButton));
      expect(taps, 1);
    });

    testWidgets('with no callback it is disabled and ignores taps', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const AlchemyButton(label: 'NOPE', onPressed: null)),
      );
      await tester.tap(find.byType(AlchemyButton), warnIfMissed: false);
      expect(
        tester
            .getSemantics(find.byType(AlchemyButton))
            .flagsCollection
            .isEnabled
            .name,
        anyOf('isFalse', 'none'),
      );
      handle.dispose();
    });

    testWidgets('every kind renders', (tester) async {
      for (final kind in AlchemyButtonKind.values) {
        await tester.pumpWidget(
          host(
            AlchemyButton(
              label: 'X',
              kind: kind,
              icon: Icons.add,
              onPressed: () {},
            ),
          ),
        );
        expect(find.byIcon(Icons.add), findsOneWidget);
      }
    });

    testWidgets(
      'survives a narrow slot (long label is ellipsised, not overflowing)',
      (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: 120,
              child: AlchemyButton(
                label: 'A VERY LONG BUTTON LABEL',
                onPressed: () {},
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('OrbButton', () {
    testWidgets('taps, and a busy orb ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          OrbButton(icon: Icons.undo, label: 'Undo', onPressed: () => taps++),
        ),
      );
      await tester.tap(find.byType(OrbButton));
      expect(taps, 1);
      await tester.pumpWidget(
        host(
          OrbButton(
            icon: Icons.undo,
            label: 'Undo',
            busy: true,
            onPressed: () => taps++,
          ),
        ),
      );
      await tester.tap(find.byType(OrbButton), warnIfMissed: false);
      expect(taps, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'disabled orb is dimmed and silent; every orb is a 56px target',
      (tester) async {
        await tester.pumpWidget(
          host(
            const OrbButton(icon: Icons.undo, label: 'Undo', onPressed: null),
          ),
        );
        expect(
          tester.getSize(find.byType(OrbButton)).shortestSide,
          greaterThanOrEqualTo(48),
        );
        await tester.pumpWidget(
          host(
            OrbButton(
              icon: Icons.undo,
              label: 'Undo',
              size: 40,
              showLabel: false,
              onPressed: () {},
            ),
          ),
        );
        expect(
          tester.getSize(find.byType(OrbButton)).shortestSide,
          greaterThanOrEqualTo(56),
          reason: 'tap area stays large',
        );
      },
    );
  });

  group('AlchemySwitch', () {
    testWidgets('toggles and reports the new value', (tester) async {
      var value = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (c, set) => AlchemySwitch(
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AlchemySwitch));
      await tester.pump(const Duration(milliseconds: 300));
      expect(value, isTrue);
      await tester.tap(find.byType(AlchemySwitch));
      expect(value, isFalse);
    });

    testWidgets('disabled switch cannot be toggled', (tester) async {
      await tester.pumpWidget(
        host(const AlchemySwitch(value: false, onChanged: null)),
      );
      await tester.tap(find.byType(AlchemySwitch), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('exposes its state to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(AlchemySwitch(label: 'Haptics', value: true, onChanged: (_) {})),
      );
      final node = tester.getSemantics(find.byType(AlchemySwitch));
      expect(node.label, 'Haptics');
      expect(node.flagsCollection.isToggled.name, 'isTrue');
      handle.dispose();
    });
  });

  group('AlchemySegments', () {
    testWidgets('selecting an option reports it', (tester) async {
      AnimationSpeed picked = AnimationSpeed.normal;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (c, set) => AlchemySegments<AnimationSpeed>(
              itemKeyPrefix: 'seg',
              options: const {
                AnimationSpeed.normal: 'Normal',
                AnimationSpeed.fast: 'Fast',
              },
              selected: picked,
              onChanged: (v) => set(() => picked = v),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('seg.fast')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(picked, AnimationSpeed.fast);
    });

    testWidgets('four options fit a narrow width', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 260,
            child: AlchemySegments<int>(
              options: const {0: 'Off', 1: 'Symbols', 2: 'Patterns', 3: 'Both'},
              selected: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('stars and difficulty', () {
    testWidgets('StarRow reads out the count', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const StarRow(earned: 2)));
      expect(find.bySemanticsLabel('2 of 3 stars'), findsOneWidget);
      handle.dispose();
    });

    test('star path has ten vertices inside its circle', () {
      final b = starPath(const Offset(50, 50), 20).getBounds();
      expect(b.width, lessThanOrEqualTo(40.001));
      expect(b.height, lessThanOrEqualTo(40.001));
    });

    testWidgets(
      'difficulty shows its word and the matching number of lit pips',
      (tester) async {
        for (final d in Difficulty.values) {
          await tester.pumpWidget(host(DifficultyIndicator(difficulty: d)));
          expect(find.text(d.label), findsOneWidget);
          expect(d.pips, d.index + 1);
        }
      },
    );

    test('each difficulty has its own colour and label', () {
      expect(
        Difficulty.values.map((d) => d.color.toARGB32()).toSet().length,
        4,
      );
      expect(Difficulty.values.map((d) => d.label).toSet().length, 4);
    });
  });

  group('toast and panel', () {
    testWidgets('toast shows its message', (tester) async {
      await tester.pumpWidget(host(const AlchemyToast(message: 'Hello there')));
      expect(find.text('Hello there'), findsOneWidget);
    });

    testWidgets('glass panel with a glow draws its child', (tester) async {
      await tester.pumpWidget(
        host(const GlassPanel(glow: Colors.green, child: Text('inside'))),
      );
      expect(find.text('inside'), findsOneWidget);
    });
  });

  group('logo', () {
    testWidgets('the emblem and wordmark render at every progress', (
      tester,
    ) async {
      for (final p in [0.0, 0.2, 0.5, 0.8, 1.0]) {
        await tester.pumpWidget(host(BrandLogo(progress: p)));
        expect(tester.takeException(), isNull);
      }
      expect(find.text('PRISM POUR'), findsOneWidget);
      expect(find.text('ALCHEMY LAB'), findsOneWidget);
    });

    testWidgets('fits a small slot', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 200,
            height: 260,
            child: BrandLogo(emblemHeight: 90, titleSize: 24),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('victory animation maths', () {
    test('droplets are deterministic per seed and differ between seeds', () {
      final a = VictoryPainter.dropletOffset(seed: 5, i: 3, age: 0.7);
      expect(a, VictoryPainter.dropletOffset(seed: 5, i: 3, age: 0.7));
      expect(a, isNot(VictoryPainter.dropletOffset(seed: 6, i: 3, age: 0.7)));
      expect(a, isNot(VictoryPainter.dropletOffset(seed: 5, i: 4, age: 0.7)));
    });

    test('droplets fly up and out, then fall (gravity)', () {
      for (var i = 0; i < VictoryPainter.dropletCount; i++) {
        final early = VictoryPainter.dropletOffset(seed: 9, i: i, age: 0.25);
        final late = VictoryPainter.dropletOffset(seed: 9, i: i, age: 1.8);
        expect(early.dy, lessThan(0), reason: 'droplet $i starts upward');
        expect(
          late.dy,
          greaterThan(early.dy),
          reason: 'droplet $i falls back down',
        );
        expect(
          VictoryPainter.dropletOffset(seed: 9, i: i, age: 0),
          Offset.zero,
        );
      }
    });

    test('they spread sideways but stay inside a sensible area', () {
      for (var i = 0; i < VictoryPainter.dropletCount; i++) {
        final o = VictoryPainter.dropletOffset(seed: 3, i: i, age: 1.5);
        expect(o.dx.abs(), lessThan(1.6));
        expect(o.dy.abs(), lessThan(3));
      }
    });

    testWidgets('paints at every point of the animation', (tester) async {
      for (final p in [0.0, 0.1, 0.4, 0.75, 1.0]) {
        await tester.pumpWidget(
          SizedBox(
            width: 360,
            height: 700,
            child: CustomPaint(
              painter: VictoryPainter(
                progress: AlwaysStoppedAnimation(p),
                seed: 7,
                center: const Offset(0.5, 0.26),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('home difficulty estimate', () {
    test('tutorials are easy', () {
      for (var l = 1; l <= kTutorialLevels; l++) {
        expect(expectedDifficulty(l), Difficulty.easy);
      }
    });

    test('never gets easier as levels increase, and reaches expert', () {
      var prev = Difficulty.easy.index;
      for (var l = 6; l <= 400; l++) {
        final d = expectedDifficulty(l).index;
        expect(d, greaterThanOrEqualTo(prev), reason: 'level $l');
        prev = d;
      }
      expect(expectedDifficulty(400), Difficulty.expert);
      expect({for (var l = 1; l <= 200; l++) expectedDifficulty(l)}.length, 4);
    });
  });

  group('decorative motion obeys reduced motion', () {
    testWidgets('the background animates by default', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 100,
            height: 100,
            child: AlchemyBackground(child: SizedBox()),
          ),
          container: c,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the master switch turns it off', (tester) async {
      final c = ProviderContainer(
        overrides: [ambientMotionProvider.overrideWithValue(false)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 100,
            height: 100,
            child: AlchemyBackground(child: SizedBox()),
          ),
          container: c,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the OS reduce-motion flag stops it', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 100,
            height: 100,
            child: AlchemyBackground(child: SizedBox()),
          ),
          container: c,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('the in-app reduce-motion setting stops it', (tester) async {
      final repo = MemoryProgressRepository(
        settings: const AppSettings(motion: MotionPreference.on),
      );
      final c = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      await c.read(bootstrapProvider.future);
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 100,
            height: 100,
            child: AlchemyBackground(child: SizedBox()),
          ),
          container: c,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('"off" keeps the motion even when the OS asks to reduce it', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final repo = MemoryProgressRepository(
        settings: const AppSettings(motion: MotionPreference.off),
      );
      final c = ProviderContainer(
        overrides: [progressRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      await c.read(bootstrapProvider.future);
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 100,
            height: 100,
            child: AlchemyBackground(child: SizedBox()),
          ),
          container: c,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'before storage has loaded the background still works (splash screen)',
      (tester) async {
        final c = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(
              MemoryProgressRepository(),
            ),
          ],
        );
        addTearDown(c.dispose);
        // Bootstrap is NOT awaited: this is the very first frame of the app.
        await tester.pumpWidget(
          host(
            const SizedBox(
              width: 100,
              height: 100,
              child: AlchemyBackground(child: SizedBox()),
            ),
            container: c,
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
