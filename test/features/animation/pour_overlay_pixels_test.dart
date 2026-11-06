import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/animation/board_layout.dart';
import 'package:prism_pour/features/game/animation/pour_overlay_painter.dart';
import 'package:prism_pour/features/game/animation/pour_plan.dart';
import 'package:prism_pour/features/game/rendering/bottle_static_layers.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer_painter.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';

const scale = 1.5;

class Scene {
  Scene(this.style, List<List<int>> bottles, this.move, {double width = 420}) {
    state = PuzzleState.fromIds(bottles);
    layout = BoardLayout.compute(
      count: state.bottleCount,
      width: width,
      aspect: style.spec.aspect,
    );
    g = style.geometryFor(layout.bottleSize, 4);
    result = GameEngine(state).applyMove(move);
    plan = PourPlan.build(
      result: result,
      geometry: g,
      sourceRect: layout.rects[move.source],
      destRect: layout.rects[move.destination],
      boardWidth: layout.size.width,
    );
    layers = BottleStaticLayers.record(g, style);
    palette = LiquidPalette.forColorIds(state.colorCounts.keys);
  }

  final BottleStyle style;
  final MoveModel move;
  late final PuzzleState state;
  late final BoardLayout layout;
  late final dynamic g;
  late final dynamic result;
  late final PourPlan plan;
  late final BottleStaticLayers layers;
  late final LiquidPalette palette;

  PourOverlayPainter overlay(double t, {bool debug = false}) =>
      PourOverlayPainter(
        plan: plan,
        style: style,
        layers: layers,
        palette: palette,
        assist: ColorAssist.off,
        repaint: ChangeNotifier(),
        seconds: () => t,
        debug: debug,
      );

  /// How the resting board draws the two bottles (same order as the overlay).
  void paintStatic(Canvas canvas) {
    final after = result.resultingState as PuzzleState;
    for (final i in [move.destination, move.source]) {
      final r = layout.rects[i];
      canvas.save();
      canvas.translate(r.left, r.top);
      canvas.drawPicture(layers.back);
      LiquidLayerPainter.paintLiquid(
        canvas,
        g,
        LiquidLayerSpan.fromUnits(after.bottles[i].units),
        palette,
        ColorAssist.off,
      );
      canvas.drawPicture(layers.front);
      canvas.restore();
    }
  }
}

Future<(Uint8List, int, int)> raster(
  Size size,
  void Function(Canvas) draw,
) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..scale(scale);
  draw(c);
  final w = (size.width * scale).ceil(), h = (size.height * scale).ceil();
  final img = await rec.endRecording().toImage(w, h);
  final bd = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return (bd.buffer.asUint8List(), w, h);
}

Color px((Uint8List, int, int) r, Offset p) {
  final x = (p.dx * scale).round().clamp(0, r.$2 - 1);
  final y = (p.dy * scale).round().clamp(0, r.$3 - 1);
  final i = (y * r.$2 + x) * 4;
  return Color.fromARGB(r.$1[i + 3], r.$1[i], r.$1[i + 1], r.$1[i + 2]);
}

void main() {
  final boards = {
    '1 unit': (
      [
        [2, 2, 0, 1],
        [1, 3, 3],
        [0, 0, 1, 2],
        [3, 1],
        <int>[],
        <int>[],
      ],
      const MoveModel(0, 3),
    ),
    '3 units': (
      [
        [2, 1, 1, 1],
        [0, 3, 0, 3],
        [2, 0, 3, 2],
        <int>[],
        <int>[],
      ],
      const MoveModel(0, 3),
    ),
    'pour left': (
      [
        [0, 2, 1],
        [1, 3, 3, 2],
        [3, 2, 1, 1],
        [3, 1, 2, 1],
        <int>[],
        <int>[],
      ],
      const MoveModel(3, 0),
    ),
  };

  for (final style in BottleStyles.all) {
    for (final e in boards.entries) {
      testWidgets(
        '${style.name} / ${e.key}: the LAST frame is pixel-identical to the settled board',
        (tester) async {
          await tester.runAsync(() async {
            final s = Scene(style, e.value.$1, e.value.$2);
            final overlay = await raster(
              s.layout.size,
              (c) => s.overlay(s.plan.duration).paint(c, s.layout.size),
            );
            final settled = await raster(s.layout.size, s.paintStatic);
            var diff = 0;
            for (var i = 0; i < overlay.$1.length; i++) {
              if ((overlay.$1[i] - settled.$1[i]).abs() > 1) diff++;
            }
            // No pop when the overlay hands over to the static bottles.
            expect(diff, 0, reason: '$diff differing channel values');
          });
        },
      );
    }
  }

  testWidgets(
    'mid-pour: the stream is really drawn along its path, in the poured colour',
    (tester) async {
      await tester.runAsync(() async {
        final s = Scene(
          BottleStyles.alchemyClassic,
          boards['3 units']!.$1,
          boards['3 units']!.$2,
        );
        final t = (s.plan.tApproachEnd + s.plan.tPourEnd) / 2;
        final f = s.plan.frameAt(t);
        final stream = f.stream!;
        final r = await raster(
          s.layout.size,
          (c) => s.overlay(t).paint(c, s.layout.size),
        );
        final liquid = s.palette.colorFor(stream.color.id);
        // Only open-air stretches: the first part is under the source's lip
        // glass and the last part is inside (tinted by) the destination glass.
        var hits = 0;
        for (var u = 0.1; u <= 0.9; u += 0.05) {
          final p = stream.at(u);
          if (s.plan.destRect.inflate(3).contains(p)) continue;
          if ((p - s.plan.lipTarget).distance <
              s.layout.bottleSize.width * 0.32) {
            continue;
          }
          final c = px(r, p);
          expect(c.a, greaterThan(0.9), reason: 'stream at $u');
          final d = [
            liquid.base,
            liquid.light,
            liquid.dark,
          ].map((v) => ColorMath.deltaE(c, v)).reduce((a, b) => a < b ? a : b);
          expect(d, lessThan(40), reason: 'stream colour at $u');
          hits++;
        }
        expect(hits, greaterThanOrEqualTo(3));
        // And nothing is drawn far from the action.
        expect(
          px(r, Offset(s.layout.size.width - 4, s.layout.size.height - 3)).a,
          0,
        );
      });
    },
  );

  testWidgets('the stream is visible INSIDE the destination glass', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = Scene(
        BottleStyles.royalGlass,
        boards['3 units']!.$1,
        boards['3 units']!.$2,
      );
      final t = (s.plan.tApproachEnd + s.plan.tPourEnd) / 2;
      final stream = s.plan.frameAt(t).stream!;
      final r = await raster(
        s.layout.size,
        (c) => s.overlay(t).paint(c, s.layout.size),
      );
      // A point of the stream that lies within the destination bottle's box.
      Offset? inside;
      for (var u = 0.0; u <= 1; u += 0.02) {
        final p = stream.at(u);
        if (s.plan.destRect.deflate(4).contains(p) &&
            s.g.cavity.contains(p - s.plan.destRect.topLeft)) {
          inside = p;
        }
      }
      expect(inside, isNotNull, reason: 'the stream must enter the neck');
      expect(px(r, inside!).a, greaterThan(0.9));
    });
  });

  testWidgets(
    'the source bottle is where the plan says (tilted over the destination)',
    (tester) async {
      await tester.runAsync(() async {
        final s = Scene(
          BottleStyles.crystalPrism,
          boards['1 unit']!.$1,
          boards['1 unit']!.$2,
        );
        final t = (s.plan.tApproachEnd + s.plan.tPourEnd) / 2;
        final f = s.plan.frameAt(t);
        final r = await raster(
          s.layout.size,
          (c) => s.overlay(t).paint(c, s.layout.size),
        );
        // A point on the rotated source's body is painted; its home spot is empty glass-free.
        final body = s.plan.worldPoint(
          f.sourceAnchor,
          f.sourceAngle,
          s.g.pivot,
        );
        expect(px(r, body).a, greaterThan(0.05));
        final home = s.layout.rects[s.move.source].center;
        expect(
          px(r, home).a,
          lessThan(0.05),
          reason: 'source has left its slot',
        );
      });
    },
  );

  testWidgets('debug overlay paints without error at every phase', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final s = Scene(
        BottleStyles.alchemyClassic,
        boards['1 unit']!.$1,
        boards['1 unit']!.$2,
      );
      for (var i = 0; i <= 20; i++) {
        final t = s.plan.duration * i / 20;
        await raster(
          s.layout.size,
          (c) => s.overlay(t, debug: true).paint(c, s.layout.size),
        );
      }
    });
  });

  testWidgets('every frame of every style renders without exceptions', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final style in BottleStyles.all) {
        final s = Scene(style, boards['3 units']!.$1, boards['3 units']!.$2);
        for (var i = 0; i <= 40; i++) {
          final t = s.plan.duration * i / 40;
          await raster(
            s.layout.size,
            (c) => s.overlay(t).paint(c, s.layout.size),
          );
        }
      }
    });
  });

  test('painter repaint rules', () {
    final s = Scene(
      BottleStyles.alchemyClassic,
      boards['1 unit']!.$1,
      boards['1 unit']!.$2,
    );
    final a = s.overlay(0.2);
    expect(
      a.shouldRepaint(s.overlay(0.9)),
      isFalse,
      reason: 'time comes from the repaint listenable',
    );
    final other = Scene(
      BottleStyles.alchemyClassic,
      boards['3 units']!.$1,
      boards['3 units']!.$2,
    );
    expect(a.shouldRepaint(other.overlay(0.2)), isTrue);
    expect(a.shouldRepaint(s.overlay(0.2, debug: true)), isTrue);
  });
}
