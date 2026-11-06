import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/collection/presentation/collection_screen.dart';
import '../../features/complete/presentation/level_complete_screen.dart';
import '../../features/game/presentation/animation_lab_screen.dart';
import '../../features/game/presentation/bottle_preview_screen.dart';
import '../../features/game/presentation/game_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/levels/presentation/level_select_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import 'app_routes.dart';

/// A short fade with a slight rise: one consistent transition everywhere.
CustomTransitionPage<void> _page(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  GoRoute route(String path, Widget Function() build) => GoRoute(
    path: path,
    pageBuilder: (context, state) => _page(state, build()),
  );

  return GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      route(AppRoutes.splash, () => const SplashScreen()),
      route(AppRoutes.home, () => const HomeScreen()),
      route(AppRoutes.levels, () => const LevelSelectScreen()),
      route(AppRoutes.play, () => const GameScreen()),
      route(AppRoutes.complete, () => const LevelCompleteScreen()),
      route(AppRoutes.collection, () => const CollectionScreen()),
      route(AppRoutes.settings, () => const SettingsScreen()),
      route(AppRoutes.preview, () => const BottlePreviewScreen()),
      route(AppRoutes.animationLab, () => const AnimationLabScreen()),
    ],
  );
});
