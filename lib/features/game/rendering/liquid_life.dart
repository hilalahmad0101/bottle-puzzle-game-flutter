import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../engine/models/bottle_model.dart';
import 'bottle_geometry.dart';

/// How long one lap of the shared "liquid life" clock takes. Every motion in
/// [LiquidLifePainter] completes a whole number of cycles per lap, so the
/// clock can wrap from 1 back to 0 without any visible jump.
const Duration kLiquidLifeLap = Duration(seconds: 40);

/// Tiny rising bubbles and a faintly shimmering surface inside the liquid of
/// one bottle, so a resting board still feels alive.
///
/// Cost control: it paints only while [life] ticks (the board stops the clock
/// during a pour, in the background, and with reduced motion), draws at most
/// four circles and one short line per non-empty bottle, and sits in its own
/// repaint layer, so the glass and liquid are never repainted by it.
class LiquidLifeEffect extends StatelessWidget {
  const LiquidLifeEffect({
    super.key,
    required this.geometry,
    required this.bottle,
    required this.life,
    required this.seed,
  });

  final BottleGeometry geometry;
  final BottleModel bottle;

  /// 0..1 shared clock (one lap = [kLiquidLifeLap]).
  final Animation<double> life;

  /// Makes every bottle drift differently.
  final int seed;

  @override
  Widget build(BuildContext context) {
    if (bottle.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: geometry.size,
          painter: LiquidLifePainter(
            geometry: geometry,
            units: bottle.length,
            life: life,
            seed: seed,
          ),
        ),
      ),
    );
  }
}

class LiquidLifePainter extends CustomPainter {
  LiquidLifePainter({
    required this.geometry,
    required this.units,
    required this.life,
    required this.seed,
  }) : super(repaint: life);

  final BottleGeometry geometry;
  final int units;
  final Animation<double> life;
  final int seed;

  /// Bubbles drawn for a bottle holding [units] units.
  static int bubbleCount(int units) => units <= 0 ? 0 : math.min(4, units + 1);

  @override
  void paint(Canvas canvas, Size size) {
    if (units <= 0) return;
    final liquid = geometry.liquidBounds;
    final top = liquid.bottom - geometry.unitHeight * units;
    final height = liquid.bottom - top;
    if (height <= 0) return;
    final t = life.value; // 0..1 per lap
    final cx = liquid.center.dx;
    final span = liquid.width * 0.26;

    final count = bubbleCount(units);
    for (var j = 0; j < count; j++) {
      // 5, 6 or 8 rises per lap: a bubble every 8, 6.7 or 5 seconds.
      final cycles = const [5, 6, 8][(j + seed) % 3];
      final offset = ((j * 0.37 + seed * 0.173) % 1.0);
      final f = (t * cycles + offset) % 1.0; // 0 at the bottom .. 1 at surface
      final wobble = math.sin(2 * math.pi * (f * 2 + j * 0.31 + seed * 0.1));
      final x =
          cx +
          (((j * 0.53 + seed * 0.29) % 1.0) - 0.5) * 2 * span * 0.8 +
          wobble * liquid.width * 0.025;
      final y = liquid.bottom - height * 0.08 - f * height * 0.84;
      final r = math.max(
        0.6,
        liquid.width * (0.012 + 0.006 * ((j + seed) % 3)),
      );
      // Fade in at the bottom and out at the surface.
      final a = math.sin(math.pi * f).clamp(0.0, 1.0) * 0.5;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: a * 0.55),
      );
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.4, r * 0.35)
          ..color = Colors.white.withValues(alpha: a),
      );
    }

    // A faint ripple travelling along the surface (amplitude under 1.5 px).
    final inset = liquid.width * 0.10;
    final x0 = liquid.left + inset;
    final x1 = liquid.right - inset;
    final amp = math.min(1.4, geometry.unitHeight * 0.05);
    final path = Path();
    const steps = 14;
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final x = x0 + (x1 - x0) * u;
      final y =
          top +
          amp *
              math.sin(2 * math.pi * (u * 1.5 + t * 8 + seed * 0.21)) *
              math.sin(math.pi * u);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.28),
    );
  }

  @override
  bool shouldRepaint(LiquidLifePainter old) =>
      old.units != units ||
      old.seed != seed ||
      old.geometry.size != geometry.size ||
      !identical(old.life, life);
}
