import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../progress/application/providers.dart';

/// Shows the animated logo while progress and settings load, then moves on.
///
/// It appears on the very first frame (nothing is awaited before `runApp`),
/// and leaves as soon as BOTH the short logo animation has finished and the
/// data is ready, so a fast device is never held back by more than the
/// animation itself.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _maybeLeave();
      });
  bool _left = false;

  @override
  void initState() {
    super.initState();
    // Reduced motion: no flourish, go as soon as the data is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) {
        _c.value = 1;
        _maybeLeave();
      } else {
        _c.forward();
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _maybeLeave() {
    if (_left || !mounted) return;
    if (_c.status != AnimationStatus.completed) return;
    if (!ref.read(bootstrapProvider).hasValue) return;
    _left = true;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bootstrapProvider, (_, next) {
      if (next.hasValue) _maybeLeave();
    });
    final boot = ref.watch(bootstrapProvider);
    return Scaffold(
      backgroundColor: AppColors.midnightTop,
      body: AlchemyBackground(
        child: SafeArea(
          child: Center(
            child: LayoutBuilder(
              builder: (context, c) {
                final emblem = (c.maxHeight * 0.30).clamp(90.0, 190.0);
                return SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) => BrandLogo(
                          emblemHeight: emblem,
                          progress: Curves.easeInOut.transform(_c.value),
                          titleSize: (c.maxWidth * 0.085).clamp(24.0, 46.0),
                        ),
                      ),
                      if (boot.hasError) ...[
                        const SizedBox(height: 28),
                        const Text(
                          "Couldn't open your saved game.",
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        AlchemyButton(
                          label: 'TRY AGAIN',
                          expand: false,
                          onPressed: () => ref.invalidate(bootstrapProvider),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
