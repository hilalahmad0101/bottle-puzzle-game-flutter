import 'package:flutter/material.dart';

import '../../../engine/models/bottle_model.dart';
import 'bottle_geometry.dart';
import 'bottle_selection_effect.dart';
import 'bottle_static_layers.dart';
import 'bottle_style.dart';
import 'completed_bottle_effect.dart';
import 'custom_bottle_painter.dart';
import 'high_contrast_overlay.dart';
import 'liquid_layer.dart';
import 'liquid_life.dart';
import 'liquid_palette.dart';

/// One bottle, drawn from an engine [BottleModel].
///
/// Layer / repaint structure (each `RepaintBoundary` is its own raster
/// layer, so a pulsing selection halo never forces the glass or liquid to
/// repaint, and moving the bottle only changes compositing):
///
///   Transform (lift when selected)           <- no repaint
///     RepaintBoundary: glass + liquid         <- repaints only on liquid change
///     RepaintBoundary: selection halo         <- animates only while selected
///     RepaintBoundary: completion effect      <- plays once, then static
class BottleView extends StatefulWidget {
  const BottleView({
    super.key,
    required this.bottle,
    required this.palette,
    this.style = BottleStyles.alchemyClassic,
    this.selected = false,
    this.hint = false,
    this.completed,
    this.assist = ColorAssist.off,
    this.layers,
    this.cache,
    this.life,
    this.lifeSeed = 0,
    this.highContrast = false,
  });

  final BottleModel bottle;
  final LiquidPalette palette;
  final BottleStyle style;
  final bool selected;

  /// Highlighted by the hint system (a golden halo, no lift).
  final bool hint;

  /// Defaults to "the bottle is full of a single colour".
  final bool? completed;
  final ColorAssist assist;

  /// Override the liquid layers (the pour animation will drive these with
  /// fractional spans). Defaults to the layers of [bottle].
  final List<LiquidLayerSpan>? layers;

  /// Glass cache, injectable for tests.
  final BottleLayerCache? cache;

  /// Shared clock for the idle bubbles and surface shimmer. Null (the
  /// default) draws none of it and costs nothing.
  final Animation<double>? life;
  final int lifeSeed;

  /// Firm outline and colour dividers (the "High contrast" setting).
  final bool highContrast;

  @override
  State<BottleView> createState() => _BottleViewState();
}

class _BottleViewState extends State<BottleView> {
  BottleGeometry? _geometry;
  BottleStyle? _geometryStyle;
  int _geometryCapacity = 0;

  BottleGeometry _geometryFor(Size size) {
    final g = _geometry;
    if (g != null &&
        g.size == size &&
        _geometryStyle == widget.style &&
        _geometryCapacity == widget.bottle.capacity) {
      return g;
    }
    _geometryStyle = widget.style;
    _geometryCapacity = widget.bottle.capacity;
    return _geometry = widget.style.geometryFor(size, widget.bottle.capacity);
  }

  String _label() {
    final b = widget.bottle;
    if (b.isEmpty) return 'Empty bottle';
    final top = widget.palette.colorFor(b.topColor!.id).name;
    return 'Bottle, ${b.length} of ${b.capacity} units, top $top';
  }

  @override
  Widget build(BuildContext context) {
    final aspect = widget.style.spec.aspect;
    final bottle = widget.bottle;
    final completed = widget.completed ?? bottle.isSolvedBottle;

    return Semantics(
      label: _label(),
      selected: widget.selected,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Largest box of the bottle's aspect that fits.
          var h = constraints.hasBoundedHeight ? constraints.maxHeight : 220.0;
          var w = h * aspect;
          if (constraints.hasBoundedWidth && w > constraints.maxWidth) {
            w = constraints.maxWidth;
            h = w / aspect;
          }
          final size = Size(w, h);
          final geometry = _geometryFor(size);
          final layers = (widget.cache ?? BottleLayerCache.shared).obtain(
            widget.style,
            size,
            bottle.capacity,
          );
          final spans =
              widget.layers ?? LiquidLayerSpan.fromUnits(bottle.units);

          // Center loosens tight parent constraints so the box really is
          // the aspect-fitted [size] the geometry was built for.
          return Center(
            child: SizedBox.fromSize(
              size: size,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.selected ? 1.0 : 0.0),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (context, lift, child) => Transform.translate(
                  offset: Offset(0, -lift * h * 0.07),
                  child: child,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: CustomBottlePainter(
                          geometry: geometry,
                          style: widget.style,
                          layers: layers,
                          spans: spans,
                          palette: widget.palette,
                          assist: widget.assist,
                        ),
                      ),
                    ),
                    if (widget.highContrast)
                      HighContrastOverlay(
                        geometry: geometry,
                        bottle: widget.bottle,
                      ),
                    if (widget.life != null && !widget.bottle.isEmpty)
                      LiquidLifeEffect(
                        geometry: geometry,
                        bottle: widget.bottle,
                        life: widget.life!,
                        seed: widget.lifeSeed,
                      ),
                    BottleSelectionEffect(
                      geometry: geometry,
                      selected: widget.selected,
                      color: widget.style.accent,
                    ),
                    BottleSelectionEffect(
                      geometry: geometry,
                      selected: widget.hint && !widget.selected,
                      color: const Color(0xFFFFD36E),
                    ),
                    CompletedBottleEffect(
                      geometry: geometry,
                      active: completed,
                      color: widget.style.accent,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
