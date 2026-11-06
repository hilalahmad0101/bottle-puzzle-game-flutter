import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A frosted-glass card with a luminous edge. Cheap to draw (no backdrop
/// blur), so it is safe in scrolling lists on mid-range phones.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.glow,
    this.strong = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Optional coloured halo (e.g. the current level).
  final Color? glow;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    // The shadow is painted BEHIND the base colour, so the base must be
    // nearly opaque, otherwise a glow shows through as a solid colour block.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: glow != null ? const Color(0xF0101638) : const Color(0x99101638),
        boxShadow: [
          if (glow != null)
            BoxShadow(
              color: glow!.withValues(alpha: 0.30),
              blurRadius: 22,
              spreadRadius: 1,
            ),
        ],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: strong ? 0.16 : 0.10),
              Colors.white.withValues(alpha: strong ? 0.07 : 0.04),
            ],
          ),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
