import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bottle_geometry.dart';

/// Shimmer sweep + sparkles ([progress] 0..1 while animating) over a steady
/// soft aura. At progress 1 it is static, so a finished bottle costs
/// nothing per frame.
class CompletedEffectPainter extends CustomPainter {
  CompletedEffectPainter({
    required this.geometry,
    required this.color,
    required Animation<double> progress,
  }) : _progress = progress,
       super(repaint: progress);

  final BottleGeometry geometry;
  final Color color;
  final Animation<double> _progress;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _progress.value;

    // Steady aura, fades in with the sweep.
    canvas.drawPath(
      geometry.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.06
        ..color = color.withValues(alpha: 0.38 * p)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.07),
    );

    if (p <= 0 || p >= 1) return;

    // Slanted light band sweeping left -> right, clipped to the glass.
    canvas.save();
    canvas.clipPath(geometry.outline);
    final band = size.width * 0.34;
    final slant = size.height * 0.45;
    final x0 = -band - slant + p * (size.width + band + slant);
    final strength = math.sin(math.pi * p);
    final mid = x0 + slant / 2;
    canvas.drawPath(
      Path()
        ..moveTo(x0, size.height)
        ..lineTo(x0 + band, size.height)
        ..lineTo(x0 + band + slant, 0)
        ..lineTo(x0 + slant, 0)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(mid, 0),
          Offset(mid + band, 0),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55 * strength),
            Colors.white.withValues(alpha: 0),
          ],
          const [0, 0.5, 1],
        ),
    );
    canvas.restore();

    // Sparkles around the neck.
    final ring = geometry.ringRect;
    for (var i = 0; i < 5; i++) {
      final phase = ((p * 1.4) - i * 0.12).clamp(0.0, 1.0);
      if (phase <= 0 || phase >= 1) continue;
      final a = math.sin(math.pi * phase);
      final dx = (i - 2) * ring.width * 0.55;
      final dy = -phase * size.height * 0.10 - (i.isOdd ? 4 : 0);
      _sparkle(
        canvas,
        Offset(ring.center.dx + dx, ring.top + dy),
        size.width * (0.025 + 0.012 * (i % 3)),
        a,
      );
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, double a) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = Colors.white.withValues(alpha: 0.9 * a),
    );
  }

  @override
  bool shouldRepaint(CompletedEffectPainter old) =>
      old.geometry != geometry || old.color != color;
}

/// Celebration layer for a solved bottle. Plays once when [active] turns
/// true (or shows the settled glow if it starts active), honours "reduce
/// motion", and stops its ticker when done.
class CompletedBottleEffect extends StatefulWidget {
  const CompletedBottleEffect({
    super.key,
    required this.geometry,
    required this.active,
    this.color = const Color(0xFFFFE08A),
  });

  final BottleGeometry geometry;
  final bool active;
  final Color color;

  @override
  State<CompletedBottleEffect> createState() => _CompletedBottleEffectState();
}

class _CompletedBottleEffectState extends State<CompletedBottleEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.value = 1; // already solved: settled, no replay
  }

  @override
  void didUpdateWidget(CompletedBottleEffect old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      reduce ? _c.value = 1 : _c.forward(from: 0);
    } else if (!widget.active && old.active) {
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: widget.geometry.size,
          painter: CompletedEffectPainter(
            geometry: widget.geometry,
            color: widget.color,
            progress: _c,
          ),
        ),
      ),
    );
  }
}
