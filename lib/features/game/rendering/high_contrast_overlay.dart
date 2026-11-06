import 'package:flutter/material.dart';

import '../../../engine/models/bottle_model.dart';
import 'bottle_geometry.dart';

/// High-contrast mode for one bottle: a firm light outline around the glass
/// and a dark-and-light divider wherever two different colours meet, so
/// neighbouring liquids can be told apart by an edge and not only by hue.
///
/// Static (it never animates) and in its own repaint layer.
class HighContrastOverlay extends StatelessWidget {
  const HighContrastOverlay({
    super.key,
    required this.geometry,
    required this.bottle,
  });

  final BottleGeometry geometry;
  final BottleModel bottle;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: geometry.size,
          painter: HighContrastPainter(geometry: geometry, bottle: bottle),
        ),
      ),
    );
  }
}

class HighContrastPainter extends CustomPainter {
  HighContrastPainter({required this.geometry, required this.bottle});

  final BottleGeometry geometry;
  final BottleModel bottle;

  /// Indices `i` (1-based unit boundaries) where unit `i-1` and `i` differ.
  static List<int> dividers(BottleModel b) => [
    for (var i = 1; i < b.units.length; i++)
      if (b.units[i] != b.units[i - 1]) i,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawPath(
      geometry.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.035).clamp(1.6, 3.2)
        ..color = Colors.white.withValues(alpha: 0.92),
    );

    final liquid = geometry.liquidBounds;
    final u = geometry.unitHeight;
    final inset = liquid.width * 0.04;
    for (final i in dividers(bottle)) {
      final y = liquid.bottom - u * i;
      final a = Offset(liquid.left + inset, y);
      final b = Offset(liquid.right - inset, y);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = (w * 0.045).clamp(2.0, 3.6)
          ..color = const Color(0xFF050816).withValues(alpha: 0.85),
      );
      canvas.drawLine(
        a,
        b,
        Paint()
          ..strokeWidth = (w * 0.016).clamp(0.9, 1.6)
          ..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(HighContrastPainter old) =>
      old.bottle != bottle || old.geometry.size != geometry.size;
}
