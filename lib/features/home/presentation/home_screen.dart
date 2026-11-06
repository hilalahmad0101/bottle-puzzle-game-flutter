import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../journey/presentation/journey_banner.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/router/navigation.dart';
import '../../../app/theme/app_colors.dart';
import '../../../engine/generator/difficulty.dart';
import '../../../engine/generator/level_curve.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/difficulty_indicator.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/star_row.dart';
import '../../progress/application/providers.dart';

/// Expected difficulty of a level, from the same curve the generator uses
/// (tutorials are always easy). Cheap, so the home screen needs no level
/// generation.
Difficulty expectedDifficulty(int level) {
  if (level <= kTutorialLevels) return Difficulty.easy;
  return DifficultyGrader.tierOf(LevelCurve.forLevel(level).targetScore);
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    int level, {
    required bool resume,
  }) => openLevel(context, ref, level, resume: resume);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(progressProvider);
    final notices = ref.watch(startupNoticesProvider);
    final current = progress.currentLevel;
    final saved = progress.continueGame;
    final hasSaved = saved != null;
    final level = hasSaved ? saved.level : current;
    final difficulty = expectedDifficulty(level);

    final primary = AlchemyButton(
      key: const Key('home.play'),
      icon: Icons.play_arrow_rounded,
      label: hasSaved ? 'CONTINUE' : 'PLAY',
      subtitle: hasSaved
          ? 'Level ${saved.level} · ${saved.moves.length} ${saved.moves.length == 1 ? 'move' : 'moves'} made'
          : 'Level $current',
      onPressed: () => _play(context, ref, level, resume: true),
    );

    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        primary,
        if (hasSaved) ...[
          const SizedBox(height: 6),
          AlchemyButton(
            key: const Key('home.startOver'),
            kind: AlchemyButtonKind.quiet,
            label: 'START LEVEL ${saved.level} OVER',
            onPressed: () => _play(context, ref, saved.level, resume: false),
          ),
        ],
        const SizedBox(height: 10),
        AlchemyButton(
          key: const Key('home.levels'),
          kind: AlchemyButtonKind.secondary,
          icon: Icons.grid_view_rounded,
          label: 'LEVELS',
          onPressed: () => context.push(AppRoutes.levels),
        ),
        const SizedBox(height: 10),
        AlchemyButton(
          key: const Key('home.collection'),
          kind: AlchemyButtonKind.secondary,
          icon: Icons.science_outlined,
          label: 'BOTTLE COLLECTION',
          onPressed: () => context.push(AppRoutes.collection),
        ),
      ],
    );

    final levelCard = GlassPanel(
      glow: difficulty.color,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CURRENT LEVEL',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              letterSpacing: 2.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$level',
            key: const Key('home.level'),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 44,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          DifficultyIndicator(difficulty: difficulty),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const StarIcon(filled: true, size: 18),
                const SizedBox(width: 6),
                Text(
                  '${progress.totalStars}',
                  key: const Key('home.stars'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 16),
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: AppColors.cyanGlow,
                ),
                const SizedBox(width: 6),
                Text(
                  '${progress.completedCount} done',
                  key: const Key('home.completed'),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 10),
          const JourneyBanner(),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.midnightTop,
      body: AlchemyBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth > c.maxHeight * 1.15;
              final emblem = wide
                  ? (c.maxHeight * 0.52).clamp(90.0, 220.0)
                  : (c.maxHeight * 0.2).clamp(80.0, 190.0);
              final logo = BrandLogo(
                emblemHeight: emblem,
                titleSize: (c.maxWidth * (wide ? 0.05 : 0.085)).clamp(
                  22.0,
                  46.0,
                ),
              );
              final body = wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Center(child: logo)),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                levelCard,
                                const SizedBox(height: 14),
                                buttons,
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          logo,
                          const SizedBox(height: 18),
                          levelCard,
                          const SizedBox(height: 18),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: buttons,
                          ),
                        ],
                      ),
                    );
              return Stack(
                children: [
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Center(child: body),
                    ),
                  ),
                  if (notices.isNotEmpty)
                    Positioned(
                      left: 16,
                      right: 72,
                      top: 8,
                      child: GestureDetector(
                        key: const Key('home.notice'),
                        onTap: () =>
                            ref.read(startupNoticesProvider.notifier).dismiss(),
                        child: GlassPanel(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text(
                            notices.first,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 4,
                    right: 8,
                    child: OrbButton(
                      key: const Key('home.settings'),
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      showLabel: false,
                      size: 48,
                      onPressed: () => context.push(AppRoutes.settings),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
