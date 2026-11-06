import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/bottle_model.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/features/game/rendering/bottle_selection_effect.dart';
import 'package:prism_pour/features/game/rendering/bottle_static_layers.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/completed_bottle_effect.dart';
import 'package:prism_pour/features/game/rendering/custom_bottle_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';

BottleModel bottle(List<int> ids, {int cap = 4}) =>
    BottleModel(capacity: cap, units: ids.map(ColorUnit.new));

final palette = LiquidPalette.forColorIds(List.generate(8, (i) => i));

Widget host(
  Widget child, {
  Size size = const Size(120, 260),
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    ),
  );
}

void main() {
  final states = <String, BottleModel>{
    'empty': bottle([]),
    'partial': bottle([1, 1]),
    'mixed': bottle([0, 1, 2, 3]),
    'full': bottle([4, 4, 4, 4]),
  };

  group('renders every style in every state', () {
    for (final style in BottleStyles.all) {
      for (final e in states.entries) {
        for (final assist in ColorAssist.values) {
          testWidgets('${style.name} / ${e.key} / ${assist.name}', (
            tester,
          ) async {
            await tester.pumpWidget(
              host(
                BottleView(
                  bottle: e.value,
                  palette: palette,
                  style: style,
                  assist: assist,
                  cache: BottleLayerCache(),
                ),
              ),
            );
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
            expect(find.byType(BottleView), findsOneWidget);
          });
        }
      }
    }
  });

  group('layout', () {
    testWidgets('keeps the bottle aspect ratio and fits tight boxes', (
      tester,
    ) async {
      for (final style in BottleStyles.all) {
        for (final box in const [
          Size(60, 300),
          Size(200, 100),
          Size(80, 190),
        ]) {
          await tester.pumpWidget(
            host(
              BottleView(
                bottle: bottle([0, 1]),
                palette: palette,
                style: style,
                cache: BottleLayerCache(),
              ),
              size: box,
            ),
          );
          final s = tester.getSize(
            find
                .descendant(
                  of: find.byType(BottleView),
                  matching: find.byType(CustomPaint),
                )
                .first,
          );
          expect(s.width / s.height, closeTo(style.spec.aspect, 0.01));
          expect(s.width, lessThanOrEqualTo(box.width + 0.01));
          expect(s.height, lessThanOrEqualTo(box.height + 0.01));
        }
      }
    });

    testWidgets(
      'a full 12-bottle board fits a small phone width without overflow',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final cache = BottleLayerCache();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(8),
                child: GridView.count(
                  crossAxisCount: 6,
                  childAspectRatio: 0.42,
                  children: [
                    for (var i = 0; i < 12; i++)
                      BottleView(
                        bottle: i < 10
                            ? bottle([i % 8, (i + 1) % 8, (i + 2) % 8, i % 8])
                            : bottle([]),
                        palette: palette,
                        cache: cache,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(BottleView), findsNWidgets(12));
      },
    );
  });

  group('caching and repaint isolation', () {
    testWidgets('identical bottles share ONE recorded glass', (tester) async {
      final cache = BottleLayerCache();
      await tester.pumpWidget(
        host(
          Row(
            children: [
              for (var i = 0; i < 6; i++)
                Expanded(
                  child: BottleView(
                    bottle: bottle([i]),
                    palette: palette,
                    cache: cache,
                  ),
                ),
            ],
          ),
          size: const Size(480, 200),
        ),
      );
      expect(cache.recordCount, 1);
      expect(cache.length, 1);
    });

    testWidgets(
      'a different style or size records a new glass; same one is reused',
      (tester) async {
        final cache = BottleLayerCache();
        Widget build(BottleStyle s, Size size) => host(
          BottleView(
            bottle: bottle([0]),
            palette: palette,
            style: s,
            cache: cache,
          ),
          size: size,
        );
        await tester.pumpWidget(
          build(BottleStyles.alchemyClassic, const Size(100, 240)),
        );
        await tester.pumpWidget(
          build(BottleStyles.crystalPrism, const Size(100, 240)),
        );
        expect(cache.recordCount, 2);
        await tester.pumpWidget(
          build(BottleStyles.alchemyClassic, const Size(100, 240)),
        );
        expect(cache.recordCount, 2, reason: 'served from cache');
        await tester.pumpWidget(
          build(BottleStyles.alchemyClassic, const Size(60, 150)),
        );
        expect(cache.recordCount, 3);
      },
    );

    test('cache is a bounded LRU and returns identical objects on hits', () {
      final cache = BottleLayerCache(maxEntries: 3);
      const s = BottleStyles.alchemyClassic;
      final first = cache.obtain(s, const Size(50, 119), 4);
      expect(identical(first, cache.obtain(s, const Size(50, 119), 4)), isTrue);
      for (var w = 60; w < 100; w += 5) {
        cache.obtain(s, Size(w.toDouble(), w / 0.42), 4);
      }
      expect(cache.length, lessThanOrEqualTo(3));
      cache.clear();
      expect(cache.length, 0);
    });

    testWidgets(
      'selection, completion and the bottle are separate repaint layers',
      (tester) async {
        await tester.pumpWidget(
          host(
            BottleView(
              bottle: bottle([2, 2, 2, 2]),
              palette: palette,
              selected: true,
              cache: BottleLayerCache(),
            ),
          ),
        );
        final bottleBoundaries = find.descendant(
          of: find.byType(BottleView),
          matching: find.byType(RepaintBoundary),
        );
        // glass+liquid, selection halo, completion effect
        expect(bottleBoundaries, findsAtLeastNWidgets(3));
        expect(
          find.byType(BottleSelectionEffect),
          findsNWidgets(2),
        ); // selection + hint
        expect(find.byType(CompletedBottleEffect), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
      },
    );

    test(
      'the bottle painter repaints only when the liquid or glass changes',
      () {
        const style = BottleStyles.alchemyClassic;
        final g = style.geometryFor(const Size(84, 200), 4);
        final layers = BottleStaticLayers.record(g, style);
        CustomBottlePainter make({
          List<LiquidLayerSpan>? spans,
          LiquidPalette? pal,
          ColorAssist assist = ColorAssist.off,
          BottleStaticLayers? l,
        }) => CustomBottlePainter(
          geometry: g,
          style: style,
          layers: l ?? layers,
          spans: spans ?? const [LiquidLayerSpan(0, 0, 2)],
          palette: pal ?? palette,
          assist: assist,
        );

        final base = make();
        // A rebuild with equal-but-not-identical inputs must NOT repaint.
        expect(
          base.shouldRepaint(make(spans: const [LiquidLayerSpan(0, 0, 2)])),
          isFalse,
        );
        expect(
          base.shouldRepaint(
            make(pal: LiquidPalette.forColorIds(List.generate(8, (i) => i))),
          ),
          isFalse,
        );
        // Real changes do.
        expect(
          base.shouldRepaint(make(spans: const [LiquidLayerSpan(0, 0, 3)])),
          isTrue,
        );
        expect(
          base.shouldRepaint(make(spans: const [LiquidLayerSpan(1, 0, 2)])),
          isTrue,
        );
        expect(base.shouldRepaint(make(assist: ColorAssist.symbols)), isTrue);
        expect(
          base.shouldRepaint(make(pal: LiquidPalette.forColorIds([5, 6, 7]))),
          isTrue,
        );
        expect(
          base.shouldRepaint(make(l: BottleStaticLayers.record(g, style))),
          isTrue,
        );
      },
    );

    test('the standalone liquid painter has the same repaint discipline', () {
      final g = BottleStyles.royalGlass.geometryFor(const Size(84, 200), 4);
      LiquidLayerPainter make(List<LiquidLayerSpan> s) =>
          LiquidLayerPainter(geometry: g, spans: s, palette: palette);
      expect(
        make(const [LiquidLayerSpan(0, 0, 1)])
            .shouldRepaint(make(const [LiquidLayerSpan(0, 0, 1)])),
        isFalse,
      );
      expect(
        make(const [LiquidLayerSpan(0, 0, 1)])
            .shouldRepaint(make(const [LiquidLayerSpan(0, 0, 1.5)])),
        isTrue,
      );
    });
  });

  group('effects only animate when needed', () {
    testWidgets('idle bottle has no running animations (nothing repaints)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          BottleView(
            bottle: bottle([0, 1]),
            palette: palette,
            cache: BottleLayerCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a selected bottle pulses; deselecting stops the animation', (
      tester,
    ) async {
      Widget build(bool sel) => host(
        BottleView(
          bottle: bottle([0, 1]),
          palette: palette,
          selected: sel,
          cache: BottleLayerCache(),
        ),
      );
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('selection lifts the bottle without repainting it', (
      tester,
    ) async {
      final cache = BottleLayerCache(); // shared: same glass between builds
      Widget build(bool sel) => host(
        BottleView(
          bottle: bottle([0, 1]),
          palette: palette,
          selected: sel,
          cache: cache,
        ),
      );
      await tester.pumpWidget(build(false));
      final before = tester.getTopLeft(find.byType(BottleView));
      final glassBefore =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(BottleView),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as CustomBottlePainter;
      await tester.pumpWidget(build(true));
      await tester.pump(const Duration(milliseconds: 400));
      final glassAfter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(BottleView),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter
              as CustomBottlePainter;
      // The lift is a pure transform: the painter's inputs are unchanged.
      expect(glassAfter.shouldRepaint(glassBefore), isFalse);
      final moved = tester.getRect(find.byType(CustomPaint).first).top;
      expect(moved, lessThan(before.dy));
      await tester.pumpWidget(build(false));
      await tester.pumpAndSettle();
    });

    testWidgets('completion plays once then settles (no endless ticker)', (
      tester,
    ) async {
      Widget build(List<int> ids) => host(
        BottleView(
          bottle: bottle(ids),
          palette: palette,
          cache: BottleLayerCache(),
        ),
      );
      await tester.pumpWidget(build([1, 1, 1, 0]));
      expect(find.byType(CompletedBottleEffect), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CompletedBottleEffect),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      await tester.pumpWidget(build([1, 1, 1, 1])); // solved!
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(
        find.descendant(
          of: find.byType(CompletedBottleEffect),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'an already-solved bottle shows the settled glow with no animation',
      (tester) async {
        await tester.pumpWidget(
          host(
            BottleView(
              bottle: bottle([3, 3, 3, 3]),
              palette: palette,
              cache: BottleLayerCache(),
            ),
          ),
        );
        await tester.pump();
        expect(tester.hasRunningAnimations, isFalse);
      },
    );

    testWidgets('completed can be overridden to off', (tester) async {
      await tester.pumpWidget(
        host(
          BottleView(
            bottle: bottle([3, 3, 3, 3]),
            palette: palette,
            completed: false,
            cache: BottleLayerCache(),
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(CompletedBottleEffect),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });

    testWidgets('reduce-motion: selection and completion do not loop', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          BottleView(
            bottle: bottle([2, 2, 2, 2]),
            palette: palette,
            selected: true,
            cache: BottleLayerCache(),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pumpAndSettle(); // would time out if a repeating ticker ran
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('animation-engine compatibility', () {
    testWidgets(
      'fractional layer overrides render (what a pour animation will feed)',
      (tester) async {
        for (final style in BottleStyles.all) {
          await tester.pumpWidget(
            host(
              BottleView(
                bottle: bottle([0, 1, 1]),
                palette: palette,
                style: style,
                layers: const [
                  LiquidLayerSpan(0, 0, 1.0),
                  LiquidLayerSpan(1, 1.0, 2.37),
                ],
                assist: ColorAssist.both,
                cache: BottleLayerCache(),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets('the bottle exposes the same geometry for every style', (
      tester,
    ) async {
      for (final style in BottleStyles.all) {
        final g = style.geometryFor(const Size(84, 200), 4);
        expect(g.unitRect(0).bottom, g.liquidBounds.bottom);
        expect(g.mouth.dy, lessThan(g.liquidBounds.top));
      }
    });
  });

  group('accessibility semantics', () {
    testWidgets('describes fill level and top colour', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          BottleView(
            bottle: bottle([0, 1, 1]),
            palette: LiquidPalette.catalogue,
            cache: BottleLayerCache(),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Bottle, 3 of 4 units, top Magenta'),
        findsOneWidget,
      );
      await tester.pumpWidget(
        host(
          BottleView(
            bottle: bottle([]),
            palette: LiquidPalette.catalogue,
            cache: BottleLayerCache(),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Empty bottle'), findsOneWidget);
      handle.dispose();
    });
  });
}
