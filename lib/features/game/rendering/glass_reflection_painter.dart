import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import 'bottle_geometry.dart';
import 'bottle_style.dart';

/// All glass drawing, split in two static halves that sit BEHIND and IN
/// FRONT of the liquid. Both depend only on (style, geometry), so they are
/// recorded once into Pictures by `BottleStaticLayers` and replayed.
abstract final class GlassPainting {
  static Color _a(Color c, double alpha) =>
      c.withValues(alpha: alpha.clamp(0.0, 1.0));

  /// Glow, floor light and the back wall of the glass.
  static void paintBack(Canvas canvas, BottleGeometry g, BottleStyle s) {
    final w = g.size.width, h = g.size.height;

    // Soft aura (depth).
    canvas.drawPath(
      g.outline,
      Paint()
        ..color = _a(s.glow, 0.20)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05),
    );

    // Light pooled on the surface under the bottle.
    final floor = Rect.fromCenter(
      center: Offset(w / 2, h * 0.975),
      width: w * 0.95,
      height: h * 0.05,
    );
    canvas.drawOval(
      floor,
      Paint()
        ..shader = RadialGradient(colors: [_a(s.glow, 0.40), _a(s.glow, 0.0)])
            .createShader(floor),
    );

    // Back glass: faint tint, darker toward the edges for volume.
    canvas.save();
    canvas.clipPath(g.cavity);
    final box = Offset.zero & g.size;
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _a(s.glassTint, 0.20),
            _a(s.glassTint, 0.04),
            _a(s.glassTint, 0.04),
            _a(s.glassTint, 0.16),
          ],
          stops: const [0, 0.22, 0.7, 1],
        ).createShader(box),
    );
    canvas.drawRect(
      box,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_a(s.glassTint, 0.0), _a(s.glassTint, 0.10)],
        ).createShader(box),
    );
    canvas.restore();
  }

  /// Glass walls, facets, reflections, rim and the neck ring.
  static void paintFront(Canvas canvas, BottleGeometry g, BottleStyle s) {
    final w = g.size.width, h = g.size.height;
    final box = Offset.zero & g.size;
    final liquid = g.liquidBounds;
    final cx = w / 2;

    // Glass wall = outline minus hollow. Thicker at the base automatically.
    final wall = Path.combine(PathOperation.difference, g.outline, g.cavity);
    canvas.drawPath(
      wall,
      Paint()
        ..shader = LinearGradient(
          colors: [
            _a(s.glassTint, 0.46),
            _a(s.glassTint, 0.20),
            _a(s.glassTint, 0.46),
          ],
        ).createShader(box),
    );
    // Thick base: a light lens along the floor.
    final baseBox = Rect.fromLTRB(0, liquid.bottom - h * 0.07, w, h);
    canvas.save();
    canvas.clipPath(wall);
    canvas.drawRect(
      baseBox,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_a(s.rimLight, 0.0), _a(s.rimLight, 0.42)],
        ).createShader(baseBox),
    );
    canvas.restore();

    // Facet shading (clipped to the silhouette): left facet lighter, right
    // facet darker. Subtle, to keep the liquid readable.
    canvas.save();
    canvas.clipPath(g.outline);
    final fx = g.facetEdges.first.$1.dx; // left facet edge x
    canvas.drawRect(
      Rect.fromLTRB(0, liquid.top, fx, h),
      Paint()..color = _a(const Color(0xFFFFFFFF), 0.05 * s.facetStrength),
    );
    canvas.drawRect(
      Rect.fromLTRB(w - fx, liquid.top, w, h),
      Paint()..color = _a(const Color(0xFF000000), 0.07 * s.facetStrength),
    );
    canvas.restore();

    // Facet edges.
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;
    if (s.prismatic) {
      edgePaint.shader = LinearGradient(
        colors: [
          _a(const Color(0xFF58F0FF), 0.75 * s.facetStrength),
          _a(const Color(0xFFFF6BE0), 0.75 * s.facetStrength),
          _a(const Color(0xFF9B7BFF), 0.75 * s.facetStrength),
        ],
      ).createShader(box);
    } else {
      edgePaint.color = _a(s.rimLight, 0.30 * s.facetStrength);
    }
    for (final (a, b) in g.facetEdges) {
      canvas.drawLine(a, b, edgePaint);
    }

    // Silhouette edge: bright outside, faint inside.
    canvas.drawPath(
      g.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = _a(s.rimLight, 0.62),
    );
    canvas.drawPath(
      g.cavity,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _a(s.rimLight, 0.22),
    );

    // Main specular streak on the left of the body.
    final bodyHalf = liquid.width / 2;
    final streak = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        cx - bodyHalf * 0.80,
        liquid.top + liquid.height * 0.06,
        math.max(2.0, bodyHalf * 0.13),
        liquid.height * 0.62,
      ),
      Radius.circular(bodyHalf * 0.08),
    );
    canvas.drawRRect(
      streak,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _a(const Color(0xFFFFFFFF), 0.55),
            _a(const Color(0xFFFFFFFF), 0.04),
          ],
        ).createShader(streak.outerRect),
    );
    // Fainter secondary streak on the right.
    final streak2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        cx + bodyHalf * 0.66,
        liquid.top + liquid.height * 0.18,
        math.max(1.5, bodyHalf * 0.07),
        liquid.height * 0.5,
      ),
      Radius.circular(bodyHalf * 0.05),
    );
    canvas.drawRRect(
      streak2,
      Paint()..color = _a(const Color(0xFFFFFFFF), 0.16),
    );

    // Shoulder gleam.
    final neckHalf = (g.ringRect.width / 2);
    canvas.drawPath(
      Path()
        ..moveTo(cx - neckHalf * 0.9, liquid.top - liquid.height * 0.16)
        ..quadraticBezierTo(
          cx - bodyHalf * 0.85,
          liquid.top - liquid.height * 0.10,
          cx - bodyHalf * 0.82,
          liquid.top + liquid.height * 0.02,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = _a(const Color(0xFFFFFFFF), 0.42),
    );

    // Caustic crescent in the thick base.
    final baseY = liquid.bottom + (h * 0.975 - liquid.bottom) * 0.55;
    canvas.drawPath(
      Path()
        ..moveTo(cx - bodyHalf * 0.55, baseY)
        ..quadraticBezierTo(
          cx,
          baseY + (h * 0.012),
          cx + bodyHalf * 0.55,
          baseY,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = _a(s.rimLight, 0.38),
    );

    _paintLip(canvas, g, s);
    _paintRing(canvas, g, s);
  }

  static void _paintLip(Canvas canvas, BottleGeometry g, BottleStyle s) {
    final spec = (s.spec);
    final w = g.size.width, h = g.size.height;
    final lip = Rect.fromCenter(
      center: Offset(w / 2, spec.lipTop * h + 1),
      width: spec.lipWidth * w,
      height: math.max(3.0, h * 0.02),
    );
    canvas.drawOval(lip, Paint()..color = _a(const Color(0xFF02060F), 0.45));
    canvas.drawOval(
      lip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _a(s.rimLight, 0.85),
    );
  }

  static void _paintRing(Canvas canvas, BottleGeometry g, BottleStyle s) {
    final r = g.ringRect;
    final rr = RRect.fromRectAndRadius(r, Radius.circular(r.height * 0.32));

    // Illumination (visible even at a glance).
    canvas.drawRRect(
      rr.inflate(r.height * 0.1),
      Paint()
        ..color = _a(s.accent, 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r.height * 0.55),
    );

    switch (s.ring) {
      case RingKind.brass:
        _metalBand(canvas, rr, const [
          Color(0xFFFFEFB8),
          Color(0xFFE0A93E),
          Color(0xFF8A5A12),
          Color(0xFFE0A93E),
          Color(0xFFFFEFB8),
        ]);
        // Rivets.
        for (final t in const [0.2, 0.5, 0.8]) {
          canvas.drawCircle(
            Offset(r.left + r.width * t, r.center.dy),
            math.max(0.9, r.height * 0.10),
            Paint()..color = _a(const Color(0xFF5B3A08), 0.85),
          );
        }
        break;
      case RingKind.prismatic:
        final paint = Paint()
          ..shader = LinearGradient(
            colors: [
              s.accent,
              const Color(0xFFFF6BE0),
              const Color(0xFF9B7BFF),
              s.accent,
            ],
          ).createShader(r);
        canvas.drawRRect(rr, paint);
        canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = _a(const Color(0xFFFFFFFF), 0.7),
        );
        break;
      case RingKind.royal:
        // Two gold bands with a jewel between them.
        final top = RRect.fromRectAndRadius(
          Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * 0.38),
          Radius.circular(r.height * 0.18),
        );
        final bottom = RRect.fromRectAndRadius(
          Rect.fromLTRB(r.left, r.bottom - r.height * 0.38, r.right, r.bottom),
          Radius.circular(r.height * 0.18),
        );
        const gold = [
          Color(0xFFFFF3C4),
          Color(0xFFE6B84A),
          Color(0xFF8F6212),
          Color(0xFFE6B84A),
          Color(0xFFFFF3C4),
        ];
        _metalBand(canvas, top, gold);
        _metalBand(canvas, bottom, gold);
        final c = r.center;
        final jr = r.height * 0.34;
        final gem = Path()
          ..moveTo(c.dx, c.dy - jr)
          ..lineTo(c.dx + jr * 0.8, c.dy)
          ..lineTo(c.dx, c.dy + jr)
          ..lineTo(c.dx - jr * 0.8, c.dy)
          ..close();
        canvas.drawPath(
          gem,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE5D4FF), Color(0xFF7B4DFF), Color(0xFF3A1FA8)],
            ).createShader(gem.getBounds()),
        );
        canvas.drawPath(
          gem,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = _a(const Color(0xFFFFE7A8), 0.9),
        );
        break;
      case RingKind.verdant:
        // An aged-copper band with two small leaves.
        _metalBand(canvas, rr, const [
          Color(0xFFD6FFC9),
          Color(0xFF58B36B),
          Color(0xFF1F5B33),
          Color(0xFF58B36B),
          Color(0xFFD6FFC9),
        ]);
        for (final dir in const [-1.0, 1.0]) {
          final c = Offset(r.center.dx + dir * r.width * 0.16, r.center.dy);
          canvas.save();
          canvas.translate(c.dx, c.dy);
          canvas.rotate(dir * 0.7);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: r.height * 0.95,
              height: r.height * 0.42,
            ),
            Paint()..color = _a(const Color(0xFFB9FF8C), 0.95),
          );
          canvas.restore();
        }
        break;
      case RingKind.celestial:
        // A silver band with a four-pointed star between two dots.
        _metalBand(canvas, rr, const [
          Color(0xFFFFFFFF),
          Color(0xFFB9C4E8),
          Color(0xFF4A557F),
          Color(0xFFB9C4E8),
          Color(0xFFFFFFFF),
        ]);
        final c = r.center;
        final sr = r.height * 0.42;
        final star = Path()
          ..moveTo(c.dx, c.dy - sr)
          ..lineTo(c.dx + sr * 0.28, c.dy - sr * 0.28)
          ..lineTo(c.dx + sr, c.dy)
          ..lineTo(c.dx + sr * 0.28, c.dy + sr * 0.28)
          ..lineTo(c.dx, c.dy + sr)
          ..lineTo(c.dx - sr * 0.28, c.dy + sr * 0.28)
          ..lineTo(c.dx - sr, c.dy)
          ..lineTo(c.dx - sr * 0.28, c.dy - sr * 0.28)
          ..close();
        canvas.drawPath(star, Paint()..color = _a(const Color(0xFFFFE08A), 1));
        for (final dir in const [-1.0, 1.0]) {
          canvas.drawCircle(
            Offset(c.dx + dir * r.width * 0.3, c.dy),
            math.max(0.8, r.height * 0.09),
            Paint()..color = _a(const Color(0xFF2B3566), 0.9),
          );
        }
        break;
    }
  }

  static void _metalBand(Canvas canvas, RRect rr, List<Color> colors) {
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rr.outerRect),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _a(const Color(0xFF4A3006), 0.7),
    );
  }
}

/// Paints the front glass (reflections, rim, ring) of a bottle.
class GlassReflectionPainter extends CustomPainter {
  const GlassReflectionPainter({required this.geometry, required this.style});

  final BottleGeometry geometry;
  final BottleStyle style;

  @override
  void paint(Canvas canvas, Size size) =>
      GlassPainting.paintFront(canvas, geometry, style);

  @override
  bool shouldRepaint(GlassReflectionPainter old) =>
      old.style != style || old.geometry.size != geometry.size;
}
