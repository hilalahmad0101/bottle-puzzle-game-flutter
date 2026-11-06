import 'package:flutter/material.dart';

/// Soft gradient backdrop shared by all screens.
class PrismBackground extends StatelessWidget {
  const PrismBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.18),
              Theme.of(context).scaffoldBackgroundColor,
            ),
            Theme.of(context).scaffoldBackgroundColor,
          ],
        ),
      ),
      child: child,
    );
  }
}
