import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/glass_panel.dart';

enum PauseAction { resume, restart, settings, home }

/// Shows [child] centred over a dimmed screen, safe on small phones and with
/// large text (it scrolls instead of overflowing).
Future<T?> showAlchemyDialog<T>(
  BuildContext context, {
  required Widget child,
  String label = 'Dialog',
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    barrierColor: const Color(0xB3050816),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// The pause menu: resume, restart, settings or home.
class PauseMenu extends StatelessWidget {
  const PauseMenu({super.key, required this.level, required this.moves});

  final int level;
  final int moves;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      strong: true,
      glow: AppColors.cyanGlow,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PAUSED',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Level $level · $moves ${moves == 1 ? 'move' : 'moves'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          AlchemyButton(
            key: const Key('pause.resume'),
            icon: Icons.play_arrow_rounded,
            label: 'RESUME',
            onPressed: () => Navigator.of(context).pop(PauseAction.resume),
          ),
          const SizedBox(height: 10),
          AlchemyButton(
            key: const Key('pause.restart'),
            kind: AlchemyButtonKind.secondary,
            icon: Icons.refresh_rounded,
            label: 'RESTART',
            onPressed: () => Navigator.of(context).pop(PauseAction.restart),
          ),
          const SizedBox(height: 10),
          AlchemyButton(
            key: const Key('pause.settings'),
            kind: AlchemyButtonKind.secondary,
            icon: Icons.settings_rounded,
            label: 'SETTINGS',
            onPressed: () => Navigator.of(context).pop(PauseAction.settings),
          ),
          const SizedBox(height: 10),
          AlchemyButton(
            key: const Key('pause.home'),
            kind: AlchemyButtonKind.secondary,
            icon: Icons.home_rounded,
            label: 'HOME',
            subtitle: 'Your game is saved',
            onPressed: () => Navigator.of(context).pop(PauseAction.home),
          ),
        ],
      ),
    );
  }
}

/// "Restart the level? You will lose N moves."
class ConfirmRestart extends StatelessWidget {
  const ConfirmRestart({super.key, required this.moves});

  final int moves;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      strong: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RESTART LEVEL?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You will lose your $moves ${moves == 1 ? 'move' : 'moves'}.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 18),
          AlchemyButton(
            key: const Key('confirm.restart'),
            label: 'RESTART',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 8),
          AlchemyButton(
            key: const Key('confirm.cancel'),
            kind: AlchemyButtonKind.quiet,
            label: 'KEEP PLAYING',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

/// Asked before the optional extra bottle is added, because it changes the
/// level's scoring.
class ConfirmBooster extends StatelessWidget {
  const ConfirmBooster({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      strong: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'ADD AN EXTRA BOTTLE?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'One more empty bottle joins the board. Your moves and undo history stay. A level finished this way earns 1 star at most. Restarting removes the bottle again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 18),
          AlchemyButton(
            key: const Key('confirm.booster'),
            label: 'ADD BOTTLE',
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 8),
          AlchemyButton(
            key: const Key('confirm.booster.cancel'),
            kind: AlchemyButtonKind.quiet,
            label: 'NOT NOW',
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
