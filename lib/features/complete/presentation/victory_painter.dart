import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../engine/generator/seeded_random.dart';
import '../../game/rendering/liquid_palette.dart';

/// The victory effect: rotating prism rays, three expanding light rings and
/// a fountain of liquid droplets in the game's own colours. Deterministic
/// for a given [seed]. At progress 1 only a soft glow and slowly turning
/// rays remain.
class VictoryPainter extends CustomPainter {
  VictoryPainter({
    required this.progress,
    required this.seed,
    required this.center,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final int seed;

  /// Where the burst originates, as a fraction of the size.
  final Offset center;

  static const int dropletCount = 30;

  /// Position (relative to the burst origin, in units of the shorter side)
  /// of droplet [i] at [age] seconds. Pure so it can be tested.
  static Offset dropletOffset({
    required int seed,
    required int i,
    required double age,
  }) {
    final r = SeededRandom(StableHash.words([seed, i, 7]));
    final angle = -math.pi / 2 + (r.nextInt(1000) / 1000 - 0.5) * 1.9;
    final speed = 0.55 + r.nextInt(1000) / 1000 * 0.75;
    return Offset(
      math.cos(angle) * speed * age,
      math.sin(angle) * speed * age + 0.5 * 1.7 * age * age,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value; // 0..1 over the whole animation
    final origin = Offset(size.width * center.dx, size.height * center.dy);
    final unit = size.shortestSide;

    // Warm glow behind everything.
    final glowR =
        unit * (0.35 + 0.35 * Curves.easeOut.transform(math.min(1.0, t * 2)));
    final glowRect = Rect.fromCircle(center: origin, radius: glowR);
    canvas.drawRect(
      glowRect,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.gold.withValues(alpha: 0.30), Colors.transparent],
        ).createShader(glowRect),
    );

    // Prism rays.
    final rayAlpha =
        0.10 + 0.10 * Curves.easeOut.transform(math.min(1.0, t * 1.5));
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final a = (i / rays) * 2 * math.pi + t * 0.9;
      final len = size.longestSide * 0.9;
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..lineTo(
          origin.dx + math.cos(a - 0.05) * len,
          origin.dy + math.sin(a - 0.05) * len,
        )
        ..lineTo(
          origin.dx + math.cos(a + 0.05) * len,
          origin.dy + math.sin(a + 0.05) * len,
        )
        ..close();
      final colour = [
        AppColors.cyanGlow,
        AppColors.gold,
        AppColors.rose,
      ][i % 3];
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: rayAlpha),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: origin, radius: len)),
      );
    }

    // Expanding rings, staggered.
    const ringColours = [AppColors.cyanGlow, AppColors.gold, AppColors.rose];
    for (var k = 0; k < 3; k++) {
      final local = ((t * 2.2) - k * 0.22).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final e = Curves.easeOutCubic.transform(local);
      canvas.drawCircle(
        origin,
        unit * (0.1 + 0.85 * e),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 + 7 * (1 - e)
          ..color = ringColours[k].withValues(alpha: 0.55 * (1 - e)),
      );
    }

    // Liquid droplets.
    final seconds = t * 2.8; // animation length
    for (var i = 0; i < dropletCount; i++) {
      final delay = i * 0.03;
      final age = seconds - delay;
      if (age <= 0 || age > 1.9) continue;
      final off = dropletOffset(seed: seed, i: i, age: age);
      final p = origin + Offset(off.dx * unit, off.dy * unit);
      final colour =
          LiquidPalette.all[(i * 5 + seed.abs()) % LiquidPalette.all.length];
      final fade = (1 - age / 1.9).clamp(0.0, 1.0);
      canvas.drawCircle(
        p,
        unit * (0.010 + 0.008 * (i % 3)),
        Paint()..color = colour.light.withValues(alpha: 0.9 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(VictoryPainter old) =>
      old.seed != seed || old.center != center;
}
