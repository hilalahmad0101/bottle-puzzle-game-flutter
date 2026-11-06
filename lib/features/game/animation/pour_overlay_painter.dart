import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rendering/bottle_static_layers.dart';
import '../rendering/bottle_style.dart';
import '../rendering/liquid_layer_painter.dart';
import '../rendering/liquid_palette.dart';
import 'pour_plan.dart';

/// Draws the two bottles that take part in a pour, plus the stream and
/// particles, in board coordinates. It is repainted by the animation
/// ([repaint]) without any widget rebuilds, and reuses the same cached glass
/// pictures as the resting bottles, so the last frame is pixel-identical to
/// the settled board.
///
/// Draw order (back to front): destination glass + liquid, stream, destination
/// front glass (so the stream is visible INSIDE the glass), splash, source.
class PourOverlayPainter extends CustomPainter {
  PourOverlayPainter({
    required this.plan,
    required this.style,
    required this.layers,
    required this.palette,
    required this.assist,
    required Listenable repaint,
    required this.seconds,
    this.debug = false,
  }) : super(repaint: repaint);

  final PourPlan plan;
  final BottleStyle style;
  final BottleStaticLayers layers;
  final LiquidPalette palette;
  final ColorAssist assist;

  /// Current time in the plan, in seconds.
  final double Function() seconds;
  final bool debug;

  @override
  void paint(Canvas canvas, Size size) {
    final f = plan.frameAt(seconds());
    final g = plan.geometry;
    final dst = plan.destRect;

    // Destination: back glass, liquid, bubbles.
    canvas.save();
    canvas.translate(dst.left, dst.top);
    canvas.drawPicture(layers.back);
    LiquidLayerPainter.paintLiquid(
      canvas,
      g,
      f.destSpans,
      palette,
      assist,
      surface: f.destSurface,
    );
    _bubbles(canvas, f);
    canvas.restore();

    _stream(canvas, f);

    canvas.save();
    canvas.translate(dst.left, dst.top);
    canvas.drawPicture(layers.front);
    canvas.restore();

    _droplets(canvas, f);

    // Source bottle, posed by its mouth anchor and rotation.
    canvas.save();
    if (f.sourceAngle == 0 && f.sourceAnchor == plan.homeAnchor) {
      // Resting: use the slot's own origin (no anchor round trip), so the
      // hand-over to the static bottle is bit-exact.
      canvas.translate(plan.sourceRect.left, plan.sourceRect.top);
    } else {
      canvas.translate(f.sourceAnchor.dx, f.sourceAnchor.dy);
      canvas.rotate(f.sourceAngle);
      canvas.translate(-g.mouth.dx, -g.mouth.dy);
    }
    if (f.glow > 0.01) {
      canvas.drawPath(
        g.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = g.size.width * 0.07
          ..color = style.accent.withValues(alpha: 0.7 * f.glow)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.size.width * 0.06),
      );
    }
    canvas.drawPicture(layers.back);
    LiquidLayerPainter.paintLiquid(
      canvas,
      g,
      f.sourceSpans,
      palette,
      assist,
      surface: f.sourceSurface,
    );
    canvas.drawPicture(layers.front);
    if (f.glow > 0.01) {
      canvas.drawPath(
        g.outline,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = style.accent.withValues(alpha: 0.95 * f.glow),
      );
    }
    canvas.restore();

    if (debug) _debug(canvas, f);
  }

  void _stream(Canvas canvas, PourFrame f) {
    final s = f.stream;
    if (s == null) return;
    final c = palette.colorFor(s.color.id);
    const n = 24;
    final left = <Offset>[], right = <Offset>[], center = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final u = s.tail + (s.head - s.tail) * i / n;
      final p = s.at(u);
      final tan = s.tangent(u);
      final len = tan.distance;
      final nrm = len == 0 ? const Offset(1, 0) : Offset(-tan.dy, tan.dx) / len;
      // Thinner as it accelerates, rounded at the leading tip.
      final tip = i > n - 3 ? (n - i) / 3 : 1.0;
      final half = s.width * (1 - 0.35 * u) * 0.5 * math.max(0.25, tip);
      left.add(p + nrm * half);
      right.add(p - nrm * half);
      center.add(p);
    }
    final ribbon = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      ribbon.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      ribbon.lineTo(p.dx, p.dy);
    }
    ribbon.close();
    canvas.drawPath(
      ribbon,
      Paint()
        ..color = Color.lerp(c.base, c.light, 0.25)!.withValues(alpha: 0.96),
    );
    canvas.drawPath(
      ribbon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = c.light.withValues(alpha: 0.7),
    );

    // Specular line and light streaks that travel down the stream.
    final line = Path()..moveTo(center.first.dx, center.first.dy);
    for (final p in center.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, s.width * 0.22)
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.28),
    );
    for (var k = 0; k < 3; k++) {
      final phase = (f.time * 1.9 + k / 3) % 1.0;
      final a = s.tail + (s.head - s.tail) * phase;
      final b = math.min(s.head, a + 0.07);
      canvas.drawLine(
        s.at(a),
        s.at(b),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.0, s.width * 0.28)
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.5),
      );
    }
  }

  void _bubbles(Canvas canvas, PourFrame f) {
    final list = plan.bubbles(f);
    if (list.isEmpty) return;
    final g = plan.geometry;
    final surface = f.impact - plan.destRect.topLeft;
    canvas.save();
    canvas.clipPath(g.cavity);
    for (final b in list) {
      final p = Offset(surface.dx + b.dx, surface.dy + b.depth);
      if (p.dy < surface.dy) continue;
      canvas.drawCircle(
        p,
        b.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0xFFFFFFFF).withValues(alpha: b.alpha),
      );
      canvas.drawCircle(
        p.translate(-b.radius * 0.3, -b.radius * 0.3),
        b.radius * 0.25,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: b.alpha),
      );
    }
    canvas.restore();
  }

  void _droplets(Canvas canvas, PourFrame f) {
    final s = f.stream;
    final list = plan.splash(f);
    if (list.isEmpty) return;
    final color = palette.colorFor(s?.color.id ?? plan.result.color!.id).light;
    for (final d in list) {
      canvas.drawCircle(
        d.position,
        d.radius,
        Paint()..color = color.withValues(alpha: d.alpha.clamp(0.0, 1.0)),
      );
    }
  }

  void _debug(Canvas canvas, PourFrame f) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    void cross(Offset o, Color c) {
      p.color = c;
      canvas.drawLine(o.translate(-6, 0), o.translate(6, 0), p);
      canvas.drawLine(o.translate(0, -6), o.translate(0, 6), p);
    }

    cross(plan.lipTarget, const Color(0xFFFF4D4D)); // held lip position
    cross(f.impact, const Color(0xFF4DFF88)); // stream landing point
    cross(f.sourceAnchor, const Color(0xFFFFE04D)); // source mouth anchor
    final lip = plan.worldPoint(
      f.sourceAnchor,
      f.sourceAngle,
      plan.geometry.pourLip(plan.side.toDouble()),
    );
    cross(lip, const Color(0xFFFF4DFF)); // actual lip (should match red)
    final s = f.stream;
    if (s != null) {
      p.color = const Color(0xFF4DD2FF);
      canvas.drawLine(s.p0, s.p1, p);
      canvas.drawLine(s.p1, s.p2, p);
      canvas.drawLine(s.p2, s.p3, p);
    }
    // Hollow of the source, as the model sees it.
    final poly = plan.geometry.cavityPolygon;
    final path = Path();
    for (var i = 0; i < poly.length; i++) {
      final w = plan.worldPoint(f.sourceAnchor, f.sourceAngle, poly[i]);
      i == 0 ? path.moveTo(w.dx, w.dy) : path.lineTo(w.dx, w.dy);
    }
    path.close();
    p.color = const Color(0x8800FFFF);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(PourOverlayPainter old) =>
      !identical(old.plan, plan) ||
      old.palette != palette ||
      old.assist != assist ||
      old.debug != debug ||
      !identical(old.layers, layers);
}
