import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/rendering/bottle_geometry.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/game/rendering/liquid_volume_model.dart';

const size = Size(84, 200);
const scale = 2.0;

void forAll(
  void Function(BottleStyle s, int cap, BottleGeometry g, LiquidVolumeModel m)
  f,
) {
  for (final s in BottleStyles.all) {
    for (final cap in [4, 5, 6]) {
      final g = s.geometryFor(size, cap);
      f(s, cap, g, LiquidVolumeModel.of(g));
    }
  }
}

void main() {
  group('cavity polygon', () {
    test('is a closed, finite, non-degenerate sampling of the hollow', () {
      forAll((s, cap, g, m) {
        expect(g.cavityPolygon.length, greaterThan(100));
        final b = g.cavity.getBounds();
        for (final p in g.cavityPolygon) {
          expect(b.inflate(0.01).contains(p), isTrue);
        }
        expect(m.totalArea, greaterThan(size.width * size.height * 0.2));
        // Polygon area close to the path's true area (pixel count check below).
      });
    });

    test('polygon area agrees with the rendered hollow within 1.5%', () async {
      final g = BottleStyles.royalGlass.geometryFor(size, 4);
      final m = LiquidVolumeModel.of(g);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(scale);
      c.drawPath(g.cavity, Paint()..color = const Color(0xFFFFFFFF));
      final img = await rec.endRecording().toImage(
        (size.width * scale).ceil(),
        (size.height * scale).ceil(),
      );
      final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var px = 0;
      for (var i = 3; i < bd.lengthInBytes; i += 4) {
        px += bd.getUint8(i);
      }
      final pixelArea = px / 255 / (scale * scale);
      expect((m.totalArea - pixelArea).abs() / pixelArea, lessThan(0.015));
    });
  });

  group('volume and height', () {
    test('volume grows with the fill and is zero when empty', () {
      forAll((s, cap, g, m) {
        expect(m.fillVolume(0), closeTo(0, 1e-9));
        var prev = 0.0;
        for (var f = 1; f <= cap; f++) {
          final v = m.fillVolume(f.toDouble());
          expect(v, greaterThan(prev));
          prev = v;
        }
        expect(m.fillVolume(cap.toDouble()), lessThan(m.totalArea));
      });
    });

    test('height <-> area round-trips at every tilt', () {
      forAll((s, cap, g, m) {
        for (final fill in [0.5, 1.0, 2.0, cap - 0.25]) {
          final v = m.fillVolume(fill);
          for (final a in [-0.9, -0.3, 0.0, 0.2, 0.6, 1.0]) {
            final h = m.heightFor(a, v);
            expect(
              (m.areaBelow(a, h) - v).abs() / v,
              lessThan(1e-4),
              reason: '${s.id} cap=$cap fill=$fill a=$a',
            );
          }
        }
      });
    });

    test('volume is conserved by tilting (the surface just rotates)', () {
      forAll((s, cap, g, m) {
        final v = m.fillVolume(2);
        for (final a in [0.0, 0.4, 0.8, -0.8]) {
          final inside = m.areaBelow(a, m.heightFor(a, v));
          expect(inside, closeTo(v, v * 1e-4));
        }
      });
    });

    test(
      'the surface is symmetric: tilting left or right gives the same height',
      () {
        forAll((s, cap, g, m) {
          final v = m.fillVolume(2);
          // Heights are measured from the origin, so compare relative to the
          // bottle's centre line.
          final cx = g.size.width / 2;
          double rel(double a) =>
              m.heightFor(a, v) - LiquidVolumeModel.up(a).dx * cx;
          expect(rel(0.7), closeTo(rel(-0.7), 0.05));
        });
      },
    );

    test('a chord lies on the hollow and the surface plane', () {
      forAll((s, cap, g, m) {
        for (final a in [0.0, 0.5, -0.5]) {
          final h = m.heightForFill(a, 2);
          final chord = m.chord(a, h);
          expect(chord, isNotNull);
          final u = LiquidVolumeModel.up(a);
          for (final p in [chord!.$1, chord.$2]) {
            expect(u.dx * p.dx + u.dy * p.dy, closeTo(h, 1e-2));
          }
          expect((chord.$1 - chord.$2).distance, greaterThan(5));
        }
      });
    });
  });

  group('how far to tilt before it pours', () {
    test('more tilt is needed as the bottle empties (strictly)', () {
      forAll((s, cap, g, m) {
        var prev = -1.0;
        for (var fill = cap.toDouble(); fill >= 1; fill -= 1) {
          final t = m.requiredTilt(fill);
          expect(t, greaterThan(prev), reason: '${s.id} cap=$cap fill=$fill');
          prev = t;
        }
      });
    });

    test('angles are physical: between 45 deg and the cap', () {
      forAll((s, cap, g, m) {
        for (var fill = cap.toDouble(); fill >= 1; fill -= 1) {
          final t = m.requiredTilt(fill);
          expect(t, greaterThan(45 * math.pi / 180));
          expect(t, lessThanOrEqualTo(2.1));
        }
      });
    });

    test('at exactly the required tilt the surface meets the opening rim', () {
      forAll((s, cap, g, m) {
        for (final fill in [cap.toDouble(), 2.0, 1.0]) {
          final t = m.requiredTilt(fill);
          if (t >= 2.1) continue;
          final v = m.fillVolume(fill);
          final rim = g.mouthRim(1);
          double gap(double a) {
            final u = LiquidVolumeModel.up(a);
            return m.heightFor(a, v) - (u.dx * rim.dx + u.dy * rim.dy);
          }

          expect(
            gap(t),
            closeTo(0, 0.5),
            reason: '${s.id} cap=$cap fill=$fill',
          );
          expect(
            gap(t - 0.08),
            lessThan(0),
            reason: 'not yet pouring slightly earlier',
          );
          expect(
            gap(t + 0.08),
            greaterThan(0),
            reason: 'pouring slightly later',
          );
        }
      });
    });

    test('an empty bottle never reaches the rim (capped)', () {
      forAll((s, cap, g, m) => expect(m.requiredTilt(0), 2.1));
    });

    test('results are memoised and stable', () {
      final g = BottleStyles.alchemyClassic.geometryFor(size, 4);
      final m = LiquidVolumeModel.of(g);
      expect(identical(m, LiquidVolumeModel.of(g)), isTrue);
      expect(m.requiredTilt(3), m.requiredTilt(3));
    });
  });

  group('tilted liquid pixels', () {
    Future<(Uint8List, int, int)> raster(
      BottleGeometry g,
      List<LiquidLayerSpan> spans,
      double angle,
    ) async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec)..scale(scale);
      LiquidLayerPainter.paintLiquid(
        c,
        g,
        spans,
        LiquidPalette.catalogue,
        ColorAssist.off,
        surface: LiquidSurface(angle: angle),
      );
      final w = (size.width * scale).ceil(), h = (size.height * scale).ceil();
      final img = await rec.endRecording().toImage(w, h);
      final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      return (bd.buffer.asUint8List(), w, h);
    }

    int count((Uint8List, int, int) r) {
      var n = 0;
      for (var i = 3; i < r.$1.length; i += 4) {
        if (r.$1[i] > 128) n++;
      }
      return n;
    }

    for (final style in BottleStyles.all) {
      testWidgets('${style.name}: never leaks outside the hollow at any tilt', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final g = style.geometryFor(size, 4);
          for (final a in [-1.2, -0.5, 0.3, 0.9, 1.5, 2.0]) {
            final r = await raster(g, const [
              LiquidLayerSpan(0, 0, 2),
              LiquidLayerSpan(1, 2, 3.5),
            ], a);
            for (var y = 0; y < r.$3; y++) {
              for (var x = 0; x < r.$2; x++) {
                if (r.$1[(y * r.$2 + x) * 4 + 3] <= 20) continue;
                final p = Offset((x + 0.5) / scale, (y + 0.5) / scale);
                final inside = [
                  Offset.zero,
                  const Offset(0.8, 0),
                  const Offset(-0.8, 0),
                  const Offset(0, 0.8),
                  const Offset(0, -0.8),
                ].any((d) => g.cavity.contains(p + d));
                expect(inside, isTrue, reason: 'leak at $x,$y angle=$a');
              }
            }
          }
        });
      });

      testWidgets(
        '${style.name}: the amount of liquid is the same at every tilt',
        (tester) async {
          await tester.runAsync(() async {
            final g = style.geometryFor(size, 4);
            const spans = [LiquidLayerSpan(2, 0, 2)];
            final base = count(await raster(g, spans, 1e-9));
            for (final a in [0.3, 0.6, 0.9, -0.6]) {
              final n = count(await raster(g, spans, a));
              // Exact conservation is proven on the model above. Pixels also
              // include the surface ellipse, whose area grows with the longer
              // chord at high tilt, so this only guards against gross errors
              // (liquid vanishing, doubling or spilling out).
              expect(
                (n - base).abs() / base,
                lessThan(0.2),
                reason: 'angle $a: $n vs $base',
              );
            }
          });
        },
      );

      testWidgets('${style.name}: the surface stays level in the WORLD', (
        tester,
      ) async {
        await tester.runAsync(() async {
          final g = style.geometryFor(size, 4);
          for (final a in [0.4, 0.7, -0.5]) {
            final r = await raster(g, const [LiquidLayerSpan(2, 0, 2)], a);
            // Top-most opaque pixel in two columns well inside the hollow.
            int topOf(double xLocal) {
              final x = (xLocal * scale).round();
              for (var y = 0; y < r.$3; y++) {
                if (r.$1[(y * r.$2 + x) * 4 + 3] > 200) return y;
              }
              return -1;
            }

            final cx = g.liquidBounds.center.dx;
            final dxLocal = g.liquidBounds.width * 0.28;
            final yL = topOf(cx - dxLocal) / scale;
            final yR = topOf(cx + dxLocal) / scale;
            expect(yL, greaterThan(0));
            expect(yR, greaterThan(0));
            // World-horizontal surface: slope in bottle coordinates is -tan(angle).
            final slope = (yR - yL) / (2 * dxLocal);
            expect(
              slope,
              closeTo(-math.tan(a), 0.18),
              reason: '${style.id} angle=$a slope=$slope',
            );
            // Clockwise tilt: surface is higher (smaller y) on the right.
            if (a > 0) expect(yR, lessThan(yL));
            if (a < 0) expect(yR, greaterThan(yL));
          }
        });
      });
    }

    testWidgets(
      'layers stay ordered and both colours are visible when tilted',
      (tester) async {
        await tester.runAsync(() async {
          final g = BottleStyles.alchemyClassic.geometryFor(size, 4);
          final r = await raster(g, const [
            LiquidLayerSpan(0, 0, 1.5),
            LiquidLayerSpan(11, 1.5, 3),
          ], 0.5);
          final seen = <int>{};
          for (var i = 0; i < r.$1.length; i += 4) {
            if (r.$1[i + 3] < 250) continue;
            final c = Color.fromARGB(255, r.$1[i], r.$1[i + 1], r.$1[i + 2]);
            final cyan = ColorMath.deltaE(
              c,
              LiquidPalette.catalogue.colorFor(0).base,
            );
            final orange = ColorMath.deltaE(
              c,
              LiquidPalette.catalogue.colorFor(11).base,
            );
            if (cyan < 25) seen.add(0);
            if (orange < 25) seen.add(11);
          }
          expect(seen, {0, 11});
        });
      },
    );

    testWidgets('rest and a zero angle use the identical classic renderer', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final g = BottleStyles.royalGlass.geometryFor(size, 4);
        final rest = await raster(g, const [LiquidLayerSpan(3, 0, 3)], 0);
        final rec = ui.PictureRecorder();
        final c = Canvas(rec)..scale(scale);
        LiquidLayerPainter.paintLiquid(
          c,
          g,
          const [LiquidLayerSpan(3, 0, 3)],
          LiquidPalette.catalogue,
          ColorAssist.off,
        );
        final img = await rec.endRecording().toImage(rest.$2, rest.$3);
        final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        expect(bd.buffer.asUint8List(), rest.$1);
      });
    });
  });

  test('LiquidSurface value semantics', () {
    expect(const LiquidSurface(), LiquidSurface.rest);
    expect(LiquidSurface.rest.isRest, isTrue);
    expect(const LiquidSurface(angle: 0.1).isRest, isFalse);
    expect(const LiquidSurface(rippleAmp: 0.1).isRest, isFalse);
    expect(const LiquidSurface(angle: 0.1), const LiquidSurface(angle: 0.1));
  });
}
