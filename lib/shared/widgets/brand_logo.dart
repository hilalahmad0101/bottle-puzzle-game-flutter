import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../features/game/rendering/bottle_static_layers.dart';
import '../../features/game/rendering/bottle_style.dart';
import '../../features/game/rendering/custom_bottle_painter.dart';
import '../../features/game/rendering/liquid_layer.dart';
import '../../features/game/rendering/liquid_palette.dart';

/// The emblem: one of the game's own bottles filling with three liquids,
/// with sparkles. [progress] 0..1 drives the fill (1 = full, settled).
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({super.key, required this.height, this.progress = 1});

  final double height;
  final double progress;

  static const _style = BottleStyles.alchemyClassic;

  @override
  Widget build(BuildContext context) {
    final size = Size(height * _style.spec.aspect, height);
    final geometry = _style.geometryFor(size, 4);
    final layers = BottleLayerCache.shared.obtain(_style, size, 4);
    final fill = (progress.clamp(0.0, 1.0)) * 3.4;
    double cap(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
    final spans = <LiquidLayerSpan>[
      if (fill > 0) LiquidLayerSpan(0, 0, cap(fill, 0, 1.25)),
      if (fill > 1.25) LiquidLayerSpan(1, 1.25, cap(fill, 1.25, 2.35)),
      if (fill > 2.35) LiquidLayerSpan(3, 2.35, cap(fill, 2.35, 3.4)),
    ];
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: size,
            painter: CustomBottlePainter(
              geometry: geometry,
              style: _style,
              layers: layers,
              spans: spans,
              palette: LiquidPalette.catalogue,
            ),
          ),
          CustomPaint(size: size, painter: _SparklePainter(progress)),
        ],
      ),
    );
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    const spots = [
      Offset(-0.35, 0.18),
      Offset(1.25, 0.32),
      Offset(-0.2, 0.62),
      Offset(1.18, 0.74),
      Offset(0.5, -0.06),
    ];
    for (var i = 0; i < spots.length; i++) {
      final local = ((t * 1.6) - i * 0.18).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final a = math.sin(math.pi * local);
      final c = Offset(spots[i].dx * size.width, spots[i].dy * size.height);
      final r = size.width * (0.07 + 0.03 * (i % 3)) * a;
      final path = Path()
        ..moveTo(c.dx, c.dy - r * 2)
        ..quadraticBezierTo(c.dx, c.dy, c.dx + r * 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r * 2)
        ..quadraticBezierTo(c.dx, c.dy, c.dx - r * 2, c.dy)
        ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r * 2)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = (i.isEven ? AppColors.goldLight : AppColors.cyanGlow)
              .withValues(alpha: 0.9 * a),
      );
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.t != t;
}

/// Emblem plus the wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.emblemHeight = 150,
    this.progress = 1,
    this.titleSize = 38,
    this.showSubtitle = true,
  });

  final double emblemHeight;
  final double progress;
  final double titleSize;
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final reveal = Curves.easeOut.transform(
      ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    return Semantics(
      label: 'Prism Pour, Alchemy Lab',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrandEmblem(height: emblemHeight, progress: progress),
          SizedBox(height: emblemHeight * 0.1),
          Opacity(
            opacity: reveal,
            child: Transform.translate(
              offset: Offset(0, (1 - reveal) * 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        colors: [
                          AppColors.goldLight,
                          AppColors.gold,
                          AppColors.rose,
                        ],
                      ).createShader(r),
                      child: Text(
                        'PRISM POUR',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w900,
                          letterSpacing: titleSize * 0.12,
                        ),
                      ),
                    ),
                  ),
                  if (showSubtitle)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'ALCHEMY LAB',
                        style: TextStyle(
                          color: AppColors.cyanGlow.withValues(alpha: 0.85),
                          fontSize: titleSize * 0.34,
                          fontWeight: FontWeight.w600,
                          letterSpacing: titleSize * 0.24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
