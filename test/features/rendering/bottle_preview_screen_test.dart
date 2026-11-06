import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/presentation/bottle_preview_screen.dart';
import 'package:prism_pour/features/game/rendering/bottle_selection_effect.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

Future<void> pumpPreview(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(420, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: BottlePreviewScreen()));
  await tester.pump(const Duration(seconds: 2));
}

BottleStyle activeStyle(WidgetTester tester) =>
    tester.widget<BottleView>(find.byType(BottleView).first).style;

void main() {
  testWidgets('shows empty, partial, mixed and full sample bottles', (
    tester,
  ) async {
    await pumpPreview(tester);
    expect(tester.takeException(), isNull);
    final views = tester
        .widgetList<BottleView>(find.byType(BottleView))
        .toList();
    expect(views.length, 7);
    final fills = views.map((v) => v.bottle.length).toList();
    expect(fills.first, 0, reason: 'an empty bottle');
    expect(fills.where((n) => n > 0 && n < 4), isNotEmpty, reason: 'partial');
    expect(
      views.any(
        (v) =>
            v.bottle.length == 4 &&
            v.bottle.units.map((u) => u.id).toSet().length > 2,
      ),
      isTrue,
      reason: 'a mixed bottle',
    );
    expect(
      views.any((v) => v.bottle.isSolvedBottle),
      isTrue,
      reason: 'a full bottle',
    );
    expect(
      views.any((v) => v.bottle.capacity != 4),
      isTrue,
      reason: 'other capacity',
    );
  });

  testWidgets('switching style re-renders every bottle in that style', (
    tester,
  ) async {
    await pumpPreview(tester);
    expect(activeStyle(tester), BottleStyles.alchemyClassic);
    for (final s in [
      BottleStyles.crystalPrism,
      BottleStyles.royalGlass,
      BottleStyles.alchemyClassic,
    ]) {
      await tester.tap(find.text(s.name));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      for (final v in tester.widgetList<BottleView>(find.byType(BottleView))) {
        expect(v.style, s);
      }
    }
  });

  testWidgets('colour-assist chips change every bottle', (tester) async {
    await pumpPreview(tester);
    await tester.tap(find.byKey(const Key('preview.assist.both')));
    await tester.pump();
    for (final v in tester.widgetList<BottleView>(find.byType(BottleView))) {
      expect(v.assist.showSymbols && v.assist.showPatterns, isTrue);
    }
    await tester.tap(find.byKey(const Key('preview.assist.off')));
    await tester.pump();
    for (final v in tester.widgetList<BottleView>(find.byType(BottleView))) {
      expect(v.assist.showSymbols || v.assist.showPatterns, isFalse);
    }
  });

  testWidgets(
    'tapping a bottle selects it (one at a time) and again deselects',
    (tester) async {
      await pumpPreview(tester);
      int selectedCount() => tester
          .widgetList<BottleView>(find.byType(BottleView))
          .where((v) => v.selected)
          .length;
      expect(selectedCount(), 0);
      await tester.tap(find.byKey(const Key('preview.bottle.3')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(selectedCount(), 1);
      expect(
        find.byType(BottleSelectionEffect),
        findsNWidgets(14), // a selection and a hint effect per bottle
      ); // one per bottle, only one draws
      await tester.tap(find.byKey(const Key('preview.bottle.5')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(selectedCount(), 1);
      expect(
        tester.widget<BottleView>(find.byType(BottleView).at(5)).selected,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('preview.bottle.5')));
      await tester.pumpAndSettle();
      expect(selectedCount(), 0);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('completed-glow switch turns the effect off on the full bottle', (
    tester,
  ) async {
    await pumpPreview(tester);
    final full = find.byType(BottleView).at(5);
    expect(tester.widget<BottleView>(full).completed, isNull); // auto
    await tester.tap(find.byKey(const Key('preview.completed')));
    await tester.pump();
    expect(tester.widget<BottleView>(full).completed, isFalse);
  });

  testWidgets('colour-count slider keeps rendering valid at the extremes', (
    tester,
  ) async {
    await pumpPreview(tester);
    final slider = find.byKey(const Key('preview.colors'));
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Colours in level: 3'), findsOneWidget);
    await tester.drag(slider, const Offset(800, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Colours in level: 10'), findsOneWidget);
  });

  testWidgets('reachable from Settings > Developer tools', (tester) async {
    final c = await readyContainer();
    addTearDown(c.dispose);
    await pumpApp(
      tester,
      c,
      location: '/settings',
      size: const Size(420, 2600),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.bottleLab')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('settings.bottleLab')));
    await tester.pumpAndSettle();
    expect(find.byType(BottlePreviewScreen), findsOneWidget);
    expect(find.text('Bottle Lab'), findsWidgets);
    await leaveApp(tester);
  });
}
