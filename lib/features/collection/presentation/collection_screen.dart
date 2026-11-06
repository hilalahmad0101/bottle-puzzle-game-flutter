import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../engine/models/bottle_model.dart';
import '../../../engine/models/color_unit.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/alchemy_controls.dart';
import '../../../shared/widgets/alchemy_toast.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/star_row.dart';
import '../../feedback/feedback_service.dart';
import '../../game/rendering/bottle_style.dart';
import '../../game/rendering/bottle_view.dart';
import '../../game/rendering/liquid_palette.dart';
import '../../progress/application/providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/domain/app_settings.dart';

const Map<String, String> _taglines = {
  'alchemy_classic': 'Rounded hexagonal glass with a riveted brass ring.',
  'crystal_prism': 'Sharp facets and a ring that splits light into colour.',
  'royal_glass': 'Heavy, broad glass crowned with gold and a violet jewel.',
};

/// The bottle styles. Stars earned by playing unlock them; the chosen one is
/// used on the playing board.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  String? _toast;
  int _toastId = 0;

  void _showToast(String m) {
    final id = ++_toastId;
    setState(() => _toast = m);
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (mounted && id == _toastId) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressProvider);
    final stars = progress.totalStars;
    final equipped = ref.watch(bottleStyleProvider).id;
    final assist = ref.watch(appSettingsProvider).colorAssist;
    final palette = LiquidPalette.forColorIds(const [0, 1, 2, 3]);
    final sample = BottleModel(
      units: const [ColorUnit(0), ColorUnit(1), ColorUnit(2), ColorUnit(3)],
    );

    return Scaffold(
      backgroundColor: AppColors.midnightTop,
      body: AlchemyBackground(
        child: SafeArea(
          child: Column(
            children: [
              AlchemyAppBar(title: 'COLLECTION', onBack: () => context.pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const StarIcon(filled: true, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        '$stars stars earned',
                        key: const Key('collection.stars'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = math.max(
                          1,
                          math.min(3, (c.maxWidth - 16) ~/ 220),
                        );
                        final w = (c.maxWidth - 32 - (cols - 1) * 12) / cols;
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final style in BottleStyles.all)
                                SizedBox(
                                  width: w,
                                  child: _StyleCard(
                                    style: style,
                                    sample: sample,
                                    palette: palette,
                                    assist: assist,
                                    stars: stars,
                                    isUnlocked: progress.isStyleUnlocked(
                                      style.id,
                                    ),
                                    equipped: style.id == equipped,
                                    onEquip: () {
                                      ref.read(feedbackProvider).button();
                                      ref
                                          .read(appSettingsProvider.notifier)
                                          .setBottleStyle(style.id);
                                    },
                                    onLocked: () => _showToast(
                                      'Earn ${BottleUnlocks.required(style.id) - stars} more stars to unlock ${style.name}',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_toast != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 16,
                        child: Center(
                          child: AlchemyToast(
                            message: _toast!,
                            icon: Icons.lock_outline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.sample,
    required this.palette,
    required this.assist,
    required this.stars,
    required this.isUnlocked,
    required this.equipped,
    required this.onEquip,
    required this.onLocked,
  });

  final BottleStyle style;
  final BottleModel sample;
  final LiquidPalette palette;
  final ColorAssist assist;
  final int stars;
  final bool isUnlocked;
  final bool equipped;
  final VoidCallback onEquip;
  final VoidCallback onLocked;

  @override
  Widget build(BuildContext context) {
    final need = BottleUnlocks.required(style.id);
    final unlocked = isUnlocked;
    return GlassPanel(
      key: Key('style.${style.id}'),
      glow: equipped ? AppColors.gold : null,
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: unlocked ? 1 : 0.4,
                  child: BottleView(
                    bottle: sample,
                    palette: palette,
                    style: style,
                    assist: assist,
                    completed: false,
                  ),
                ),
                if (!unlocked)
                  const Icon(
                    Icons.lock_rounded,
                    size: 34,
                    color: Colors.white70,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            style.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _taglines[style.id] ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 12),
          if (!unlocked) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: stars / need,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation(AppColors.gold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$stars / $need stars',
              key: Key('style.${style.id}.progress'),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            AlchemyButton(
              key: Key('style.${style.id}.locked'),
              kind: AlchemyButtonKind.secondary,
              icon: Icons.lock_outline,
              label: 'LOCKED',
              onPressed: onLocked,
            ),
          ] else if (equipped)
            Container(
              key: Key('style.${style.id}.equipped'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: AppColors.gold.withValues(alpha: 0.16),
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.7),
                ),
              ),
              child: const Text(
                'EQUIPPED',
                style: TextStyle(
                  color: AppColors.goldLight,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            )
          else
            AlchemyButton(
              key: Key('style.${style.id}.equip'),
              label: 'EQUIP',
              onPressed: onEquip,
            ),
        ],
      ),
    );
  }
}
