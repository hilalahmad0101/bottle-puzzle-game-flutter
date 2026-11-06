import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'bottle_geometry.dart';

/// Pulsing halo and a light that travels around the silhouette.
class SelectionEffectPainter extends CustomPainter {
  SelectionEffectPainter({
    required this.geometry,
    required this.color,
    required this.metric,
    required Animation<double> pulse,
  }) : _pulse = pulse,
       super(repaint: pulse);

  final BottleGeometry geometry;
  final Color color;
  final ui.PathMetric? metric;
  final Animation<double> _pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _pulse.value;
    final glow = 0.55 + 0.25 * math.sin(2 * math.pi * t);

    canvas.drawPath(
      geometry.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..color = color.withValues(alpha: glow * 0.75)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06),
    );
    canvas.drawPath(
      geometry.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = color.withValues(alpha: 0.95),
    );

    final m = metric;
    if (m != null && m.length > 0) {
      final len = m.length * 0.16;
      final start = (t * m.length) % m.length;
      final end = start + len;
      final path = end <= m.length
          ? m.extractPath(start, end)
          : (ui.Path()
              ..addPath(m.extractPath(start, m.length), Offset.zero)
              ..addPath(m.extractPath(0, end - m.length), Offset.zero));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.6
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(SelectionEffectPainter old) =>
      old.geometry != geometry || old.color != color || old.metric != metric;
}

/// Selection halo for a bottle. Animates only while [selected]; when not
/// selected it is an empty box and costs nothing. Place it in its own
/// repaint layer next to the bottle so the bottle never repaints.
class BottleSelectionEffect extends StatefulWidget {
  const BottleSelectionEffect({
    super.key,
    required this.geometry,
    required this.selected,
    this.color = const Color(0xFF7CF3FF),
  });

  final BottleGeometry geometry;
  final bool selected;
  final Color color;

  @override
  State<BottleSelectionEffect> createState() => _BottleSelectionEffectState();
}

class _BottleSelectionEffectState extends State<BottleSelectionEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  ui.PathMetric? _metric;
  BottleGeometry? _metricFor;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _c.repeat();
  }

  @override
  void didUpdateWidget(BottleSelectionEffect old) {
    super.didUpdateWidget(old);
    if (widget.selected && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.selected && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  ui.PathMetric? _metricOf(BottleGeometry g) {
    if (!identical(_metricFor, g)) {
      final it = g.outline.computeMetrics().iterator;
      _metric = it.moveNext() ? it.current : null;
      _metricFor = g;
    }
    return _metric;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.selected) return const SizedBox.shrink();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _c.stop();
      _c.value = 0.25; // static halo
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: widget.geometry.size,
          painter: SelectionEffectPainter(
            geometry: widget.geometry,
            color: widget.color,
            metric: _metricOf(widget.geometry),
            pulse: _c,
          ),
        ),
      ),
    );
  }
}
