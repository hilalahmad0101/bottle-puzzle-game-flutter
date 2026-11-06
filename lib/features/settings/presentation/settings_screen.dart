import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../engine/models/bottle_model.dart';
import '../../../engine/models/color_unit.dart';
import '../../../engine/progression/star_rating.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/alchemy_controls.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../feedback/feedback_service.dart';
import '../../game/animation/animation_settings.dart';
import '../../game/rendering/bottle_style.dart';
import '../../progress/application/providers.dart';
import '../../game/rendering/bottle_view.dart';
import '../../game/rendering/liquid_palette.dart';
import '../application/settings_providers.dart';

/// Every control here changes a real setting that is saved and used.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final n = ref.read(appSettingsProvider.notifier);
    final style = ref.watch(bottleStyleProvider);
    final progress = ref.watch(progressProvider);

    return Scaffold(
      backgroundColor: AppColors.midnightTop,
      body: AlchemyBackground(
        child: SafeArea(
          child: Column(
            children: [
              AlchemyAppBar(title: 'SETTINGS', onBack: () => context.pop()),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: ListView(
                      key: const Key('settings.list'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        const _Section('SOUND & FEEL'),
                        GlassPanel(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Column(
                            children: [
                              _Row(
                                title: 'Music',
                                subtitle: 'A calm ambient track while you play. Off by default.',
                                trailing: AlchemySwitch(
                                  key: const Key('settings.music'),
                                  value: s.musicEnabled,
                                  onChanged: n.setMusic,
                                  label: 'Music',
                                ),
                              ),
                              const _Divider(),
                              _Row(
                                title: 'Sound effects',
                                subtitle: 'Glass, pouring, a gentle sound for a wrong move, and a chime when you win.',
                                trailing: AlchemySwitch(
                                  key: const Key('settings.sfx'),
                                  label: 'Sound effects',
                                  value: s.soundEffects,
                                  onChanged: n.setSoundEffects,
                                ),
                              ),
                              const _Divider(),
                              _Row(
                                title: 'Haptics',
                                subtitle:
                                    'Gentle vibration feedback on your device.',
                                trailing: AlchemySwitch(
                                  key: const Key('settings.haptics'),
                                  label: 'Haptics',
                                  value: s.haptics,
                                  onChanged: (v) {
                                    n.setHaptics(v);
                                    if (v) ref.read(feedbackProvider).button();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _Section('MOTION'),
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Label('Animation speed'),
                              AlchemySegments<AnimationSpeed>(
                                key: const Key('settings.speed'),
                                itemKeyPrefix: 'settings.speed',
                                options: const {
                                  AnimationSpeed.normal: 'Normal',
                                  AnimationSpeed.fast: 'Fast',
                                },
                                selected: s.speed,
                                onChanged: n.setSpeed,
                              ),
                              const SizedBox(height: 16),
                              const _Label('Reduce motion'),
                              const Text(
                                'Liquid levels still change, but bottles stop flying and tilting, and streams, splashes and background motion are removed.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AlchemySegments<MotionPreference>(
                                key: const Key('settings.motion'),
                                itemKeyPrefix: 'settings.motion',
                                options: const {
                                  MotionPreference.system: 'System',
                                  MotionPreference.on: 'On',
                                  MotionPreference.off: 'Off',
                                },
                                selected: s.motion,
                                onChanged: n.setMotion,
                              ),
                            ],
                          ),
                        ),
                        const _Section('GAMEPLAY'),
                        GlassPanel(
                          child: _Row(
                            title: 'Extra bottle booster',
                            subtitle: 'Adds a Bottle button while playing. It gives the level one more empty bottle, but a level finished that way earns 1 star at most. Off by default.',
                            trailing: AlchemySwitch(
                              key: const Key('settings.booster'),
                              label: 'Extra bottle booster',
                              value: s.extraBottleBooster,
                              onChanged: n.setExtraBottleBooster,
                            ),
                          ),
                        ),
                        const _Section('ACCESSIBILITY'),
                        GlassPanel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _Label('Colour-blind assistance'),
                              const Text(
                                'Marks every colour with its own symbol and/or pattern so no puzzle depends on hue alone.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AlchemySegments<ColorAssist>(
                                key: const Key('settings.assist'),
                                itemKeyPrefix: 'settings.assist',
                                options: const {
                                  ColorAssist.off: 'Off',
                                  ColorAssist.symbols: 'Symbols',
                                  ColorAssist.patterns: 'Patterns',
                                  ColorAssist.both: 'Both',
                                },
                                selected: s.colorAssist,
                                onChanged: n.setColorAssist,
                              ),
                              const SizedBox(height: 12),
                              _Row(
                                title: 'High contrast',
                                subtitle: 'A firm outline on every bottle, dividers between colours, and a calmer background.',
                                trailing: AlchemySwitch(
                                  key: const Key('settings.contrast'),
                                  label: 'High contrast',
                                  value: s.highContrast,
                                  onChanged: n.setHighContrast,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Center(
                                child: SizedBox(
                                  height: 118,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (var i = 0; i < 4; i++)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: BottleView(
                                            key: Key('settings.preview.$i'),
                                            bottle: BottleModel(
                                              units: [
                                                ColorUnit(i),
                                                ColorUnit(i),
                                                ColorUnit((i + 1) % 4),
                                              ],
                                            ),
                                            palette: LiquidPalette.forColorIds(
                                              const [0, 1, 2, 3],
                                            ),
                                            style: style,
                                            assist: s.colorAssist,
                                            completed: false,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const _Section('YOUR PROGRESS'),
                        GlassPanel(
                          key: const Key('settings.stats'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Column(
                            children: [
                              _Stat(
                                'Levels completed',
                                '${progress.completedCount}',
                                const Key('settings.stats.completed'),
                              ),
                              const _Divider(),
                              _Stat(
                                'Stars earned',
                                '${progress.totalStars}',
                                const Key('settings.stats.stars'),
                              ),
                              const _Divider(),
                              _Stat(
                                'Current level',
                                '${progress.currentLevel}',
                                const Key('settings.stats.current'),
                              ),
                              const _Divider(),
                              _Stat(
                                'Hints shown',
                                '${progress.totalHintsShown}',
                                const Key('settings.stats.hints'),
                              ),
                              const _Divider(),
                              _Stat(
                                'Bottle styles unlocked',
                                '${BottleStyles.all.where((s) => progress.isStyleUnlocked(s.id)).length} / ${BottleStyles.all.length}',
                                const Key('settings.stats.styles'),
                              ),
                            ],
                          ),
                        ),
                        const _Section('HOW STARS WORK'),
                        GlassPanel(
                          child: Text(
                            'Par is the length of the best known solution of a level.\n\n'
                            '★★★  at most ${(StarRating.threeStarFactor * 100).round()}% of par (rounded up)\n'
                            '★★   at most ${(StarRating.twoStarFactor * 100).round()}% of par (rounded up)\n'
                            '★    any finished level\n\n'
                            'Moves are the pours on the board when you solve it: an undone pour is not counted. Hints, restarts and pauses never change your stars.',
                            key: const Key('settings.rules'),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const _Section('DEVELOPER TOOLS'),
                        GlassPanel(
                          child: Column(
                            children: [
                              AlchemyButton(
                                key: const Key('settings.bottleLab'),
                                kind: AlchemyButtonKind.secondary,
                                icon: Icons.science_outlined,
                                label: 'BOTTLE LAB',
                                onPressed: () =>
                                    context.push(AppRoutes.preview),
                              ),
                              const SizedBox(height: 10),
                              AlchemyButton(
                                key: const Key('settings.animationLab'),
                                kind: AlchemyButtonKind.secondary,
                                icon: Icons.water_drop_outlined,
                                label: 'ANIMATION LAB',
                                onPressed: () =>
                                    context.push(AppRoutes.animationLab),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.cyanGlow,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.4,
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Colors.white.withValues(alpha: 0.08));
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.valueKey);

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value,
          key: valueKey,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}
