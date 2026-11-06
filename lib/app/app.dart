import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import 'audio_guard.dart';
import 'persistence_guard.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget: wires theme, theme mode and routing.
class PrismPourApp extends ConsumerWidget {
  const PrismPourApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // The laboratory is always night: one deliberate look.
      themeMode: ThemeMode.dark,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => PersistenceGuard(
        child: AudioGuard(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
