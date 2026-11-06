import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/features/game/rendering/bottle_geometry.dart';
import 'package:prism_pour/features/game/rendering/bottle_static_layers.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/custom_bottle_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';

const scale = 2.0;
const size = Size(84, 200);

/// A rasterised painter output (straight RGBA).
final class Raster {
  Raster(this.w, this.h, this.data);
  final int w, h;
  final ByteData data;

  int alpha(int x, int y) => data.getUint8((y * w + x) * 4 + 3);
  Color pixel(int x, int y) {
    final i = (y * w + x) * 4;
    return Color.fromARGB(
      data.getUint8(i + 3),
      data.getUint8(i),
      data.getUint8(i + 1),
      data.getUint8(i + 2),
    );
  }
}

Future<Raster> raster(CustomPainter painter, [Size s = size]) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec)..scale(scale);
  painter.paint(canvas, s);
  final img = await rec.endRecording().toImage(
    (s.width * scale).ceil(),
    (s.height * scale).ceil(),
  );
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return Raster(img.width, img.height, bd);
}

LiquidLayerSpan span(int id, double from, double to) =>
    LiquidLayerSpan(id, from, to);

LiquidLayerPainter liquidPainter(
  BottleGeometry g,
  List<LiquidLayerSpan> spans, {
  ColorAssist assist = ColorAssist.off,
}) => LiquidLayerPainter(
  geometry: g,
  spans: spans,
  palette: LiquidPalette.catalogue,
  assist: assist,
);

/// Inside the hollow, tolerating the anti-aliased edge pixels.
bool insideHollow(BottleGeometry g, int px, int py) {
  final x = (px + 0.5) / scale, y = (py + 0.5) / scale;
  for (final d in const [
    Offset(0, 0),
    Offset(0.8, 0),
    Offset(-0.8, 0),
    Offset(0, 0.8),
    Offset(0, -0.8),
  ]) {
    if (g.cavity.contains(Offset(x, y) + d)) return true;
  }
  return false;
}

void main() {
  for (final style in BottleStyles.all) {
    group('liquid pixels - ${style.name}', () {
      final g = style.geometryFor(size, 4);

      testWidgets('an empty bottle paints no liquid at all (clean glass)', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final r = await raster(liquidPainter(g, const []));
          for (var y = 0; y < r.h; y++) {
            for (var x = 0; x < r.w; x++) {
              expect(r.alpha(x, y), 0);
            }
          }
        });
      });

      testWidgets(
        'a FULL bottle never draws outside the hollow or above the body',
        (tester) async {
          await tester.runAsync(() async {
            final r = await raster(liquidPainter(g, [span(0, 0, 4)]));
            var painted = 0;
            for (var y = 0; y < r.h; y++) {
              for (var x = 0; x < r.w; x++) {
                if (r.alpha(x, y) <= 20) continue;
                painted++;
                expect(insideHollow(g, x, y), isTrue, reason: 'leak at $x,$y');
                // Not a single pixel above the top of the liquid column.
                expect(
                  y / scale,
                  greaterThanOrEqualTo(g.liquidBounds.top - 1),
                  reason: 'overflow at $x,$y',
                );
              }
            }
            expect(painted, greaterThan(500));
          });
        },
      );

      testWidgets('even absurdly over-full spans are clipped to the glass', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final r = await raster(liquidPainter(g, [span(0, 0, 9)]));
          for (var y = 0; y < r.h; y++) {
            for (var x = 0; x < r.w; x++) {
              if (r.alpha(x, y) > 20) {
                expect(insideHollow(g, x, y), isTrue, reason: 'leak at $x,$y');
                expect(y / scale, greaterThanOrEqualTo(g.liquidBounds.top - 1));
              }
            }
          }
        });
      });

      testWidgets('a partial bottle fills only as high as its units', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final r = await raster(liquidPainter(g, [span(3, 0, 2)]));
          final topOfLiquid = g.liquidBounds.bottom - 2 * g.unitHeight;
          // Surface ellipse may rise slightly above the line (perspective).
          final slack = g.liquidBounds.width * 0.14;
          var lowest = 0;
          for (var y = 0; y < r.h; y++) {
            for (var x = 0; x < r.w; x++) {
              if (r.alpha(x, y) > 20) {
                expect(y / scale, greaterThanOrEqualTo(topOfLiquid - slack));
                if (y > lowest) lowest = y;
              }
            }
          }
          // Reaches the floor of the glass.
          expect(lowest / scale, greaterThan(g.liquidBounds.bottom - 3));
        });
      });

      testWidgets('layer boundaries are exactly one unit apart', (
        tester,
      ) async {
        // Cyan / Deep Orange / Lime: far apart in colour, easy to classify.
        const ids = [0, 11, 7];
        final r0 = await tester.runAsync(
          () => raster(
            liquidPainter(g, [span(0, 0, 1), span(11, 1, 2), span(7, 2, 3)]),
          ),
        );
        final r = r0!;
        final cat = LiquidPalette.catalogue;

        int classify(Color c) {
          var best = 0;
          var bestD = double.infinity;
          for (var k = 0; k < ids.length; k++) {
            final lc = cat.colorFor(ids[k]);
            for (final v in [lc.base, lc.light, lc.dark]) {
              final d = ColorMath.deltaE(c, v);
              if (d < bestD) {
                bestD = d;
                best = k;
              }
            }
          }
          return best;
        }

        // Sample down a column right of the highlight band.
        final px =
            ((g.liquidBounds.center.dx + g.liquidBounds.width * 0.22) * scale)
                .round();
        final transitions = <double>[];
        var prev = -1;
        for (
          var py = ((g.liquidBounds.top + 4) * scale).round();
          py < (g.liquidBounds.bottom - 6) * scale;
          py++
        ) {
          if (r.alpha(px, py) < 200) continue;
          final cls = classify(r.pixel(px, py));
          if (prev != -1 && cls != prev) transitions.add(py / scale);
          prev = cls;
        }
        expect(transitions.length, 2, reason: '$transitions');
        final h = g.unitHeight;
        // top transition = boundary between unit 2|1 at bottom - 2h
        expect(transitions[0], closeTo(g.liquidBounds.bottom - 2 * h, 1.5));
        expect(transitions[1], closeTo(g.liquidBounds.bottom - 1 * h, 1.5));
        expect(transitions[1] - transitions[0], closeTo(h, 1.5));
      });

      testWidgets('different colours produce clearly different pixels', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final ids = [0, 11, 7, 1, 6, 2];
          final cx = (g.liquidBounds.center.dx * scale).round();
          final cy = ((g.liquidBounds.bottom - 0.5 * g.unitHeight) * scale)
              .round();
          final samples = <Color>[];
          for (final id in ids) {
            final r = await raster(liquidPainter(g, [span(id, 0, 4)]));
            // Same row as the unit centre, right of the highlight band.
            expect(r.alpha(cx + 14, cy), 255, reason: 'sample must be liquid');
            samples.add(r.pixel(cx + 14, cy));
          }
          for (var i = 0; i < samples.length; i++) {
            for (var j = i + 1; j < samples.length; j++) {
              expect(
                ColorMath.deltaE(samples[i], samples[j]),
                greaterThan(20),
                reason: 'ids ${ids[i]} vs ${ids[j]}',
              );
            }
          }
        });
      });
    });
  }

  group('colour-blind assistance', () {
    final g = BottleStyles.alchemyClassic.geometryFor(size, 4);

    testWidgets('symbols and patterns change the picture; off does not', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final spans = [span(0, 0, 2), span(1, 2, 4)];
        final off = await raster(liquidPainter(g, spans));
        final off2 = await raster(liquidPainter(g, spans));
        int diff(Raster a, Raster b) {
          var n = 0;
          for (var i = 0; i < a.w * a.h * 4; i++) {
            if (a.data.getUint8(i) != b.data.getUint8(i)) n++;
          }
          return n;
        }

        expect(diff(off, off2), 0, reason: 'deterministic');
        for (final mode in [
          ColorAssist.symbols,
          ColorAssist.patterns,
          ColorAssist.both,
        ]) {
          final r = await raster(liquidPainter(g, spans, assist: mode));
          expect(diff(off, r), greaterThan(100), reason: mode.name);
        }
      });
    });

    testWidgets('a symbol sits in the centre of every unit (near white)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final r = await raster(
          liquidPainter(g, [
            span(0, 0, 1),
            span(2, 1, 2),
            span(5, 2, 3),
            span(9, 3, 4),
          ], assist: ColorAssist.symbols),
        );
        for (var i = 0; i < 4; i++) {
          final c = g.unitRect(i).center;
          final p = r.pixel((c.dx * scale).round(), (c.dy * scale).round());
          expect(p.r, greaterThan(0.8), reason: 'unit $i');
          expect(p.g, greaterThan(0.8), reason: 'unit $i');
        }
      });
    });

    testWidgets('symbol count equals the number of whole units', (
      tester,
    ) async {
      // Two bottles with the same colour but 1 vs 3 units: more symbols
      // means more near-white pixels.
      await tester.runAsync(() async {
        int whites(Raster r) {
          var n = 0;
          for (var y = 0; y < r.h; y++) {
            for (var x = 0; x < r.w; x++) {
              final p = r.pixel(x, y);
              if (p.a > 0.9 && p.r > 0.93 && p.g > 0.93 && p.b > 0.93) n++;
            }
          }
          return n;
        }

        final one = await raster(
          liquidPainter(g, [span(2, 0, 1)], assist: ColorAssist.symbols),
        );
        final three = await raster(
          liquidPainter(g, [span(2, 0, 3)], assist: ColorAssist.symbols),
        );
        expect(whites(three), greaterThan(whites(one) * 2));
      });
    });
  });

  group('composed bottle', () {
    for (final style in BottleStyles.all) {
      testWidgets('${style.name}: glass + liquid composite renders', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final g = style.geometryFor(size, 4);
          final layers = BottleStaticLayers.record(g, style);
          final spans = LiquidLayerSpan.fromUnits(const [
            ColorUnit(0),
            ColorUnit(0),
            ColorUnit(1),
            ColorUnit(2),
          ]);
          final r = await raster(
            CustomBottlePainter(
              geometry: g,
              style: style,
              layers: layers,
              spans: spans,
              palette: LiquidPalette.catalogue,
            ),
          );
          // Liquid colour is still readable through the front glass.
          final bottomUnit = g.unitRect(0).center;
          final px = r.pixel(
            ((bottomUnit.dx + 12) * scale).round(),
            (bottomUnit.dy * scale).round(),
          );
          expect(
            ColorMath.deltaE(px, LiquidPalette.catalogue.colorFor(0).base),
            lessThan(45),
            reason: 'liquid must stay readable under glass reflections',
          );
          // Glass is drawn: wall pixels exist outside the hollow.
          final wall = Offset(
            g.outline.getBounds().left + 1.5,
            g.unitRect(1).center.dy,
          );
          expect(
            r.alpha((wall.dx * scale).round(), (wall.dy * scale).round()),
            greaterThan(40),
          );
        });
      });

      testWidgets(
        '${style.name}: an empty bottle shows transparent glass (liquid area mostly see-through)',
        (tester) async {
          await tester.runAsync(() async {
            final g = style.geometryFor(size, 4);
            final r = await raster(
              CustomBottlePainter(
                geometry: g,
                style: style,
                layers: BottleStaticLayers.record(g, style),
                spans: const [],
                palette: LiquidPalette.catalogue,
              ),
            );
            final c = g.unitRect(2).center;
            // Centre of the hollow is faint glass tint, nowhere near opaque.
            expect(
              r.alpha((c.dx * scale).round(), (c.dy * scale).round()),
              lessThan(90),
            );
          });
        },
      );
    }
  });
}
