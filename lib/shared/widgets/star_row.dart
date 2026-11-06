import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A star path with five points.
Path starPath(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 10; i++) {
    final a = -math.pi / 2 + i * math.pi / 5;
    final rad = i.isEven ? r : r * 0.46;
    final o = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
    i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
  }
  return p..close();
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.filled);

  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = starPath(c, size.shortestSide / 2);
    if (filled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.gold.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.18),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.goldLight, AppColors.gold, AppColors.goldDeep],
          ).createShader(Offset.zero & size),
      );
    } else {
      canvas.drawPath(
        path,
        Paint()..color = Colors.white.withValues(alpha: 0.08),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = filled
            ? AppColors.goldLight.withValues(alpha: 0.9)
            : Colors.white24,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.filled != filled;
}

/// One star, lit or dark.
class StarIcon extends StatelessWidget {
  const StarIcon({super.key, required this.filled, this.size = 20});

  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _StarPainter(filled));
}

/// [earned] of [total] stars.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.earned,
    this.total = 3,
    this.size = 18,
    this.gap = 2,
  });

  final int earned;
  final int total;
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$earned of $total stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) SizedBox(width: gap),
            StarIcon(filled: i < earned, size: size),
          ],
        ],
      ),
    );
  }
}
