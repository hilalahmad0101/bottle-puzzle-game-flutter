import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'bottle_geometry.dart';
import 'liquid_layer.dart';
import 'liquid_palette.dart';
import 'liquid_volume_model.dart';

/// How the liquid surface is posed. At rest everything is zero and the
/// classic upright renderer is used, so a settled bottle looks exactly like
/// a bottle that was never animated.
@immutable
final class LiquidSurface {
  const LiquidSurface({this.angle = 0, this.rippleAmp = 0, this.rippleAge = 0});

  static const rest = LiquidSurface();

  /// Rotation of the BOTTLE in radians, clockwise positive (plus any small
  /// slosh). Liquid planes stay horizontal in the world, so inside the
  /// bottle they are rotated by the opposite angle.
  final double angle;

  /// 0..1 strength of expanding ripple rings on the top surface.
  final double rippleAmp;

  /// Seconds driving the ripple rings.
  final double rippleAge;

  bool get isRest => angle == 0 && rippleAmp == 0;

  @override
  bool operator ==(Object other) =>
      other is LiquidSurface &&
      other.angle == angle &&
      other.rippleAmp == rippleAmp &&
      other.rippleAge == rippleAge;

  @override
  int get hashCode => Object.hash(angle, rippleAmp, rippleAge);
}

/// Draws the liquid of one bottle from its layer spans.
///
/// Guarantees:
///  * every unit has the same height ([BottleGeometry.unitHeight]);
///  * everything is clipped to the glass cavity, so nothing can leak or
///    overflow, and a full bottle ends exactly at the top of the body;
///  * an empty span list paints nothing (clean glass).
class LiquidLayerPainter extends CustomPainter {
  const LiquidLayerPainter({
    required this.geometry,
    required this.spans,
    required this.palette,
    this.assist = ColorAssist.off,
    this.surface = LiquidSurface.rest,
  });

  final BottleGeometry geometry;
  final List<LiquidLayerSpan> spans;
  final LiquidPalette palette;
  final ColorAssist assist;
  final LiquidSurface surface;

  @override
  void paint(Canvas canvas, Size size) =>
      paintLiquid(canvas, geometry, spans, palette, assist, surface: surface);

  @override
  bool shouldRepaint(LiquidLayerPainter old) =>
      old.assist != assist ||
      old.surface != surface ||
      old.palette != palette ||
      old.geometry.size != geometry.size ||
      old.geometry.capacity != geometry.capacity ||
      !listEquals(old.spans, spans);

  /// Reusable entry point (also used by `CustomBottlePainter`).
  static void paintLiquid(
    Canvas canvas,
    BottleGeometry g,
    List<LiquidLayerSpan> spans,
    LiquidPalette palette,
    ColorAssist assist, {
    LiquidSurface surface = LiquidSurface.rest,
  }) {
    if (spans.isEmpty) return;
    if (!surface.isRest) {
      _paintTilted(canvas, g, spans, palette, assist, surface);
      return;
    }
    final liquid = g.liquidBounds;
    final unitH = g.unitHeight;
    final floor = g.cavity.getBounds().bottom;

    // Visible extent of the liquid column: never above the body top.
    canvas.save();
    canvas.clipPath(g.cavity, doAntiAlias: true);

    // Highest span = the one that shows a surface.
    var topIndex = 0;
    for (var i = 0; i < spans.length; i++) {
      if (spans[i].to > spans[topIndex].to) topIndex = i;
    }

    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      if (span.units <= 0) continue;
      final color = palette.colorFor(span.colorId);
      final yTop = math.max(liquid.top, liquid.bottom - span.to * unitH);
      // The lowest span reaches the curved floor.
      final yBottom = span.from <= 0
          ? floor
          : liquid.bottom - span.from * unitH;
      if (yBottom <= yTop) continue;
      final rect = Rect.fromLTRB(
        liquid.left - 1,
        yTop,
        liquid.right + 1,
        yBottom,
      );

      _fill(canvas, rect, color);

      // Subtle separator between layers.
      if (span.from > 0) {
        canvas.drawLine(
          Offset(rect.left, rect.bottom),
          Offset(rect.right, rect.bottom),
          Paint()
            ..strokeWidth = 1
            ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10),
        );
      }

      if (assist.showPatterns) {
        canvas.save();
        canvas.clipRect(rect);
        AssistPainting.pattern(canvas, color.pattern, rect, unitH);
        canvas.restore();
      }

      if (i == topIndex) _surface(canvas, liquid, yTop, color);
    }

    if (assist.showSymbols) {
      for (final span in spans) {
        final color = palette.colorFor(span.colorId);
        // One symbol per WHOLE unit of the span (partial units, as seen
        // during a future pour animation, show none).
        for (var u = span.from.ceil(); u + 1 <= span.to + 1e-6; u++) {
          AssistPainting.symbol(
            canvas,
            color.symbol,
            Offset(liquid.center.dx, liquid.bottom - (u + 0.5) * unitH),
            math.min(unitH, liquid.width) * 0.30,
          );
        }
      }
    }
    canvas.restore();
  }

  /// Liquid in a rotated and/or rippling bottle. Each layer is the part of
  /// the hollow between two world-horizontal planes whose heights are solved
  /// from the layer volumes, so volumes are conserved at any tilt.
  static void _paintTilted(
    Canvas canvas,
    BottleGeometry g,
    List<LiquidLayerSpan> spans,
    LiquidPalette palette,
    ColorAssist assist,
    LiquidSurface surface,
  ) {
    final model = LiquidVolumeModel.of(g);
    final angle = surface.angle;
    final u = LiquidVolumeModel.up(angle);
    final poly = g.cavityPolygon;
    final bounds = g.cavity.getBounds();
    final liquid = g.liquidBounds;
    final unitH = g.unitHeight;

    final heights = <int, double>{};
    double hOf(double fill) => heights.putIfAbsent(
      (fill * 1000).round(),
      () => model.heightForFill(angle, fill),
    );

    var topIndex = 0;
    for (var i = 0; i < spans.length; i++) {
      if (spans[i].to > spans[topIndex].to) topIndex = i;
    }

    canvas.save();
    canvas.clipPath(g.cavity, doAntiAlias: true);
    final regions = <Path?>[];
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      if (span.units <= 0) {
        regions.add(null);
        continue;
      }
      final color = palette.colorFor(span.colorId);
      var region = model.clipBelow(poly, u, hOf(span.to));
      if (span.from > 0) region = model.clipAbove(region, u, hOf(span.from));
      if (region.length < 3) {
        regions.add(null);
        continue;
      }
      final path = Path()..addPolygon(region, true);
      regions.add(path);
      final rb = path.getBounds();

      canvas.save();
      canvas.clipPath(path, doAntiAlias: true);
      _fill(
        canvas,
        Rect.fromLTRB(bounds.left, rb.top, bounds.right, rb.bottom),
        color,
      );
      if (assist.showPatterns) {
        AssistPainting.pattern(canvas, color.pattern, rb, unitH);
      }
      canvas.restore();

      if (span.from > 0) {
        final c = model.chord(angle, hOf(span.from));
        if (c != null) {
          canvas.drawLine(
            c.$1,
            c.$2,
            Paint()
              ..strokeWidth = 1
              ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.10),
          );
        }
      }
      if (i == topIndex) {
        _tiltedSurface(canvas, model, angle, hOf(span.to), color, surface);
      }
    }

    if (assist.showSymbols) {
      for (var i = 0; i < spans.length; i++) {
        final region = regions[i];
        if (region == null) continue;
        final span = spans[i];
        final color = palette.colorFor(span.colorId);
        for (var n = span.from.ceil(); n + 1 <= span.to + 1e-6; n++) {
          final c = Offset(liquid.center.dx, liquid.bottom - (n + 0.5) * unitH);
          if (!region.contains(c)) continue;
          AssistPainting.symbol(
            canvas,
            color.symbol,
            c,
            math.min(unitH, liquid.width) * 0.30,
          );
        }
      }
    }
    canvas.restore();
  }

  static void _tiltedSurface(
    Canvas canvas,
    LiquidVolumeModel model,
    double angle,
    double h,
    LiquidColor c,
    LiquidSurface surface,
  ) {
    final chord = model.chord(angle, h);
    if (chord == null) return;
    final (a, b) = chord;
    final len = (b - a).distance;
    if (len < 2) return;
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final rot = math.atan2(b.dy - a.dy, b.dx - a.dx);
    final ellipse = Rect.fromCenter(
      center: Offset.zero,
      width: len * 0.96,
      height: len * 0.20,
    );
    canvas.save();
    canvas.translate(mid.dx, mid.dy);
    canvas.rotate(rot);
    canvas.drawOval(
      ellipse,
      Paint()
        ..shader = LinearGradient(colors: [c.base, c.light, c.base])
            .createShader(ellipse),
    );
    canvas.drawOval(
      ellipse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35),
    );
    // Expanding ripple rings where the stream lands.
    if (surface.rippleAmp > 0) {
      for (var k = 0; k < 3; k++) {
        final phase = (surface.rippleAge * 1.1 + k / 3) % 1.0;
        final ring = Rect.fromCenter(
          center: Offset.zero,
          width: len * (0.12 + 0.84 * phase),
          height: len * (0.12 + 0.84 * phase) * 0.20,
        );
        canvas.drawOval(
          ring,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFFFFFFFF)
                .withValues(alpha: (1 - phase) * 0.55 * surface.rippleAmp),
        );
      }
    }
    canvas.restore();
  }

  static void _fill(Canvas canvas, Rect rect, LiquidColor color) {
    // Cylinder shading: dark edges, bright left-of-centre band.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.dark, color.base, color.light, color.base, color.dark],
          stops: const [0, 0.20, 0.36, 0.72, 1],
        ).createShader(rect),
    );
    // Gentle vertical depth.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.14),
            const Color(0x00000000),
            const Color(0xFF000000).withValues(alpha: 0.16),
          ],
        ).createShader(rect),
    );
  }

  static void _surface(Canvas canvas, Rect liquid, double y, LiquidColor c) {
    final halfW = liquid.width / 2;
    final ellipse = Rect.fromCenter(
      center: Offset(liquid.center.dx, y),
      width: liquid.width * 0.96,
      height: halfW * 0.22,
    );
    canvas.save();
    // The surface never pokes above the column (full bottles stay flat).
    canvas.clipRect(
      Rect.fromLTRB(
        liquid.left - 2,
        liquid.top,
        liquid.right + 2,
        liquid.bottom + 40,
      ),
    );
    canvas.drawOval(
      ellipse,
      Paint()
        ..shader = LinearGradient(colors: [c.base, c.light, c.base])
            .createShader(ellipse),
    );
    canvas.drawOval(
      ellipse,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35),
    );
    canvas.restore();
  }
}

/// Symbols and patterns that make colours distinguishable without relying
/// on hue.
abstract final class AssistPainting {
  static void symbol(Canvas canvas, LiquidSymbol s, Offset c, double r) {
    final path = symbolPath(s, c, r);
    canvas.drawPath(
      path,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.92),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFF000000).withValues(alpha: 0.55),
    );
  }

  static Path symbolPath(LiquidSymbol s, Offset c, double r) {
    Path poly(List<Offset> pts) {
      final p = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final o in pts.skip(1)) {
        p.lineTo(o.dx, o.dy);
      }
      return p..close();
    }

    Offset at(double ang, double rad) =>
        Offset(c.dx + rad * math.cos(ang), c.dy + rad * math.sin(ang));

    switch (s) {
      case LiquidSymbol.circle:
        return Path()..addOval(Rect.fromCircle(center: c, radius: r));
      case LiquidSymbol.triangle:
        return poly([
          for (var i = 0; i < 3; i++)
            at(-math.pi / 2 + i * 2 * math.pi / 3, r * 1.15),
        ]);
      case LiquidSymbol.square:
        return Path()..addRect(Rect.fromCircle(center: c, radius: r * 0.88));
      case LiquidSymbol.diamond:
        return poly([
          at(-math.pi / 2, r * 1.2),
          at(0, r * 0.85),
          at(math.pi / 2, r * 1.2),
          at(math.pi, r * 0.85),
        ]);
      case LiquidSymbol.star:
        return poly([
          for (var i = 0; i < 10; i++)
            at(-math.pi / 2 + i * math.pi / 5, i.isEven ? r * 1.2 : r * 0.5),
        ]);
      case LiquidSymbol.cross:
        final t = r * 0.38;
        return Path()
          ..addRect(Rect.fromCenter(center: c, width: r * 2, height: t * 2))
          ..addRect(Rect.fromCenter(center: c, width: t * 2, height: r * 2));
      case LiquidSymbol.hexagon:
        return poly([
          for (var i = 0; i < 6; i++) at(i * math.pi / 3, r * 1.05),
        ]);
      case LiquidSymbol.crescent:
        return Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: c, radius: r)),
          Path()..addOval(
            Rect.fromCircle(
              center: c.translate(r * 0.55, -r * 0.15),
              radius: r * 0.85,
            ),
          ),
        );
      case LiquidSymbol.drop:
        return Path()
          ..moveTo(c.dx, c.dy - r * 1.2)
          ..cubicTo(
            c.dx + r * 0.2,
            c.dy - r * 0.5,
            c.dx + r,
            c.dy - r * 0.1,
            c.dx + r,
            c.dy + r * 0.35,
          )
          ..arcToPoint(
            Offset(c.dx - r, c.dy + r * 0.35),
            radius: Radius.circular(r),
            clockwise: true,
          )
          ..cubicTo(
            c.dx - r,
            c.dy - r * 0.1,
            c.dx - r * 0.2,
            c.dy - r * 0.5,
            c.dx,
            c.dy - r * 1.2,
          )
          ..close();
      case LiquidSymbol.heart:
        return Path()
          ..moveTo(c.dx, c.dy + r)
          ..cubicTo(
            c.dx - r * 1.6,
            c.dy - r * 0.1,
            c.dx - r * 0.7,
            c.dy - r * 1.2,
            c.dx,
            c.dy - r * 0.4,
          )
          ..cubicTo(
            c.dx + r * 0.7,
            c.dy - r * 1.2,
            c.dx + r * 1.6,
            c.dy - r * 0.1,
            c.dx,
            c.dy + r,
          )
          ..close();
      case LiquidSymbol.ring:
        return Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCircle(center: c, radius: r))
          ..addOval(Rect.fromCircle(center: c, radius: r * 0.5));
      case LiquidSymbol.bolt:
        return poly([
          c.translate(r * 0.2, -r * 1.2),
          c.translate(-r * 0.8, r * 0.15),
          c.translate(-r * 0.05, r * 0.15),
          c.translate(-r * 0.3, r * 1.2),
          c.translate(r * 0.8, -r * 0.3),
          c.translate(r * 0.05, -r * 0.3),
        ]);
    }
  }

  static void pattern(Canvas canvas, LiquidPattern p, Rect rect, double step) {
    final s = math.max(5.0, step * 0.28);
    final ink = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.30);

    switch (p) {
      case LiquidPattern.dots:
        for (var y = rect.top + s / 2; y < rect.bottom; y += s) {
          for (var x = rect.left + s / 2; x < rect.right; x += s) {
            canvas.drawCircle(Offset(x, y), s * 0.14, fill);
          }
        }
      case LiquidPattern.bigDots:
        for (var y = rect.top + s; y < rect.bottom; y += s * 2) {
          for (var x = rect.left + s; x < rect.right; x += s * 2) {
            canvas.drawCircle(Offset(x, y), s * 0.34, fill);
          }
        }
      case LiquidPattern.diagonal:
        for (var x = rect.left - rect.height; x < rect.right; x += s) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height, rect.top),
            ink,
          );
        }
      case LiquidPattern.horizontal:
        for (var y = rect.top + s / 2; y < rect.bottom; y += s * 0.8) {
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), ink);
        }
      case LiquidPattern.vertical:
        for (var x = rect.left + s / 2; x < rect.right; x += s * 0.9) {
          canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), ink);
        }
      case LiquidPattern.checks:
        var row = 0;
        for (var y = rect.top; y < rect.bottom; y += s, row++) {
          var col = row;
          for (var x = rect.left; x < rect.right; x += s, col++) {
            if (col.isEven) canvas.drawRect(Rect.fromLTWH(x, y, s, s), fill);
          }
        }
      case LiquidPattern.waves:
        for (var y = rect.top + s; y < rect.bottom; y += s * 1.1) {
          final path = Path()..moveTo(rect.left, y);
          for (var x = rect.left; x < rect.right; x += s) {
            path.quadraticBezierTo(x + s / 2, y - s * 0.4, x + s, y);
          }
          canvas.drawPath(path, ink);
        }
      case LiquidPattern.zigzag:
        for (var y = rect.top + s; y < rect.bottom; y += s * 1.2) {
          final path = Path()..moveTo(rect.left, y);
          var up = true;
          for (var x = rect.left; x < rect.right; x += s / 2) {
            path.lineTo(x + s / 2, up ? y - s * 0.35 : y);
            up = !up;
          }
          canvas.drawPath(path, ink);
        }
      case LiquidPattern.crosshatch:
        for (var x = rect.left - rect.height; x < rect.right; x += s * 1.2) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height, rect.top),
            ink,
          );
          canvas.drawLine(
            Offset(x, rect.top),
            Offset(x + rect.height, rect.bottom),
            ink,
          );
        }
      case LiquidPattern.rings:
        for (var y = rect.top + s; y < rect.bottom; y += s * 1.8) {
          for (var x = rect.left + s; x < rect.right; x += s * 1.8) {
            canvas.drawCircle(Offset(x, y), s * 0.42, ink);
          }
        }
      case LiquidPattern.chevrons:
        for (var y = rect.top + s * 0.7; y < rect.bottom; y += s * 1.1) {
          final path = Path()..moveTo(rect.left, y);
          for (var x = rect.left; x < rect.right; x += s) {
            path
              ..lineTo(x + s / 2, y + s * 0.4)
              ..lineTo(x + s, y);
          }
          canvas.drawPath(path, ink);
        }
      case LiquidPattern.dashes:
        var row = 0;
        for (var y = rect.top + s * 0.6; y < rect.bottom; y += s * 0.9, row++) {
          for (
            var x = rect.left + (row.isEven ? 0 : s);
            x < rect.right;
            x += s * 2
          ) {
            canvas.drawLine(Offset(x, y), Offset(x + s * 0.9, y), ink);
          }
        }
    }
  }
}
