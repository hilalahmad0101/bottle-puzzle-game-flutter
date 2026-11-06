import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../application/journey_providers.dart';

/// "ALCHEMY JOURNEY": the player's current chapter, how far through it they
/// are, and what comes next. Everything is read from [journeyProvider].
class JourneyBanner extends ConsumerWidget {
  const JourneyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(journeyProvider);
    final accent = p.stage.glowA;
    final left = p.levelsToNext;
    return Semantics(
      container: true,
      label:
          'Alchemy Journey, chapter ${p.chapter}: ${p.title}. '
          '$left ${left == 1 ? 'level' : 'levels'} until ${p.nextStage.name}.',
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'ALCHEMY JOURNEY',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10.5,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              p.title,
              key: const Key('home.journey.title'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color.lerp(AppColors.textPrimary, accent, 0.35),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 190,
                height: 6,
                child: LinearProgressIndicator(
                  key: const Key('home.journey.progress'),
                  value: p.stageProgress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$left ${left == 1 ? 'level' : 'levels'} to ${p.nextStage.name}',
              key: const Key('home.journey.next'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
