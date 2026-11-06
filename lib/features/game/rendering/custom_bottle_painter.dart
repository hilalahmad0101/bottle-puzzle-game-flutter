import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'bottle_geometry.dart';
import 'bottle_static_layers.dart';
import 'bottle_style.dart';
import 'liquid_layer.dart';
import 'liquid_layer_painter.dart';
import 'liquid_palette.dart';

/// Composes one bottle: cached back glass -> liquid -> cached front glass.
///
/// Only the liquid is drawn from scratch; the glass is replayed from
/// Pictures. [shouldRepaint] is true only when the liquid or the cached
/// layers actually changed, so selection or completion effects (which live
/// in their own layers) never cause this painter to redraw.
class CustomBottlePainter extends CustomPainter {
  const CustomBottlePainter({
    required this.geometry,
    required this.style,
    required this.layers,
    required this.spans,
    required this.palette,
    this.assist = ColorAssist.off,
  });

  final BottleGeometry geometry;
  final BottleStyle style;
  final BottleStaticLayers layers;
  final List<LiquidLayerSpan> spans;
  final LiquidPalette palette;
  final ColorAssist assist;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPicture(layers.back);
    LiquidLayerPainter.paintLiquid(canvas, geometry, spans, palette, assist);
    canvas.drawPicture(layers.front);
  }

  @override
  bool shouldRepaint(CustomBottlePainter old) =>
      !identical(old.layers, layers) ||
      old.assist != assist ||
      old.palette != palette ||
      !listEquals(old.spans, spans);
}
