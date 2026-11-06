import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../engine/generator/difficulty.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/difficulty_indicator.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/star_row.dart';
import '../../feedback/feedback_service.dart';
import '../../game/application/game_session.dart';
import '../../game/rendering/bottle_style.dart';
import '../../progress/application/providers.dart';
import 'victory_painter.dart';

/// Shown when the level is solved. Everything displayed comes from the real
/// [LevelResult] and the saved progress.
class LevelCompleteScreen extends ConsumerStatefulWidget {
  const LevelCompleteScreen({super.key});

  @override
  ConsumerState<LevelCompleteScreen> createState() =>
      _LevelCompleteScreenState();
}

class _LevelCompleteScreenState extends ConsumerState<LevelCompleteScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  // Captured ONCE. Starting the next level clears the session's result and
  // changes progress, which rebuilds this screen while it is still sliding
  // away; it must keep showing the result it was opened for.
  LevelResult? _result;
  Timer? _rewardTimer;

  @override
  void initState() {
    super.initState();
    _result = ref.read(gameSessionProvider).result;
    // A rewarding chime once the level-complete fanfare has had its moment.
    if (_result?.hasReward ?? false) {
      _rewardTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) ref.read(feedbackProvider).reward();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      reduce ? _c.value = 1 : _c.forward();
    });
  }

  @override
  void dispose() {
    _rewardTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _next(GameSession s, LevelResult r) async {
    final load = s.startLevel(r.level + 1);
    context.pop(); // back to the play screen, which shows the new level
    await load;
  }

  Future<void> _replay(GameSession s, LevelResult r) async {
    final load = s.startLevel(r.level, resume: false);
    context.pop();
    await load;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.read(gameSessionProvider);
    final r = _result;
    if (r == null) {
      // Nothing to show (e.g. the app was restored on this route).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(AppRoutes.home);
      });
      return const Scaffold(backgroundColor: AppColors.midnightTop);
    }
    final progress = ref.watch(progressProvider);
    final firstTime = r.previousBest == null;
    // Only "unlocked" if the next level was not already open and finished.
    final unlockedNext = firstTime && !progress.isCompleted(r.level + 1);
    final newStyles = [
      for (final s in BottleStyles.all)
        if (r.newStyleIds.contains(s.id)) s.name,
    ];
    final chapter = r.newChapter;
    final difficulty = Difficulty.values[r.difficultyIndex];

    return PopScope(
      canPop: false, // no dead end: the buttons are the ways out
      child: Scaffold(
        backgroundColor: AppColors.midnightTop,
        body: AlchemyBackground(
          child: Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: VictoryPainter(
                    progress: _c,
                    seed: r.level * 7919 + r.moves,
                    center: const Offset(0.5, 0.26),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ShaderMask(
                                  shaderCallback: (b) => const LinearGradient(
                                    colors: [
                                      AppColors.goldLight,
                                      AppColors.gold,
                                      AppColors.rose,
                                    ],
                                  ).createShader(b),
                                  child: const FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'LEVEL COMPLETE',
                                      key: Key('complete.title'),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 4,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Level ${r.level}',
                                  key: const Key('complete.level'),
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                DifficultyIndicator(difficulty: difficulty),
                                const SizedBox(height: 18),
                                _Stars(
                                  earned: r.stars,
                                  controller: _c,
                                  size: (c.maxWidth / 6.5).clamp(40.0, 64.0),
                                ),
                                const SizedBox(height: 16),
                                GlassPanel(
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          _Stat(
                                            label: 'MOVES',
                                            value: '${r.moves}',
                                            k: const Key('complete.moves'),
                                          ),
                                          _Stat(
                                            label: 'PAR',
                                            value: '${r.par}',
                                            k: const Key('complete.par'),
                                          ),
                                          if (r.hintsUsed > 0)
                                            _Stat(
                                              label: 'HINTS',
                                              value: '${r.hintsUsed}',
                                              k: const Key('complete.hints'),
                                            ),
                                          if (r.previousBest != null)
                                            _Stat(
                                              label: 'BEST',
                                              value:
                                                  '${r.isNewBest ? (r.assisted && r.moves < r.par ? r.par : r.moves) : r.previousBest!.bestMoves}',
                                              k: const Key('complete.best'),
                                            ),
                                        ],
                                      ),
                                      if (r.isNewBest &&
                                          r.previousBest != null) ...[
                                        const SizedBox(height: 8),
                                        const _Chip(
                                          text: 'NEW BEST',
                                          key: Key('complete.newBest'),
                                        ),
                                      ],
                                      if (r.assisted) ...[
                                        const SizedBox(height: 8),
                                        const _Chip(
                                          text: 'EXTRA BOTTLE · 1 STAR MAX',
                                          key: Key('complete.assisted'),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Text(
                                        '★★★  ${r.thresholds.three} moves or fewer\n'
                                        '★★   ${r.thresholds.two} moves or fewer\n'
                                        '★    finish the level',
                                        key: const Key('complete.rules'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                          height: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (unlockedNext) ...[
                                  const SizedBox(height: 10),
                                  _Chip(
                                    text: 'LEVEL ${r.level + 1} UNLOCKED',
                                    key: const Key('complete.unlocked'),
                                  ),
                                ],
                                if (chapter != null) ...[
                                  const SizedBox(height: 8),
                                  _Chip(
                                    text:
                                        'NEW CHAPTER: ${chapter.title.toUpperCase()}',
                                    key: const Key('complete.chapter'),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    chapter.stage.tagline,
                                    key: const Key('complete.chapter.tagline'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                for (final n in newStyles) ...[
                                  const SizedBox(height: 8),
                                  _Chip(
                                    text: 'NEW BOTTLE: ${n.toUpperCase()}',
                                    key: Key('complete.style.$n'),
                                  ),
                                ],
                                const SizedBox(height: 20),
                                AlchemyButton(
                                  key: const Key('complete.next'),
                                  icon: Icons.arrow_forward_rounded,
                                  label: 'NEXT LEVEL',
                                  onPressed: () => _next(session, r),
                                ),
                                const SizedBox(height: 10),
                                AlchemyButton(
                                  key: const Key('complete.replay'),
                                  kind: AlchemyButtonKind.secondary,
                                  icon: Icons.replay_rounded,
                                  label: 'REPLAY',
                                  onPressed: () => _replay(session, r),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Expanded(
                                      child: AlchemyButton(
                                        key: const Key('complete.levels'),
                                        kind: AlchemyButtonKind.quiet,
                                        label: 'LEVELS',
                                        onPressed: () {
                                          context.go(AppRoutes.home);
                                          context.push(AppRoutes.levels);
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: AlchemyButton(
                                        key: const Key('complete.home'),
                                        kind: AlchemyButtonKind.quiet,
                                        label: 'HOME',
                                        onPressed: () =>
                                            context.go(AppRoutes.home),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.k});

  final String label;
  final String value;
  final Key k;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            key: k,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.gold.withValues(alpha: 0.16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.7)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.goldLight,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Three stars; each earned one pops in turn.
class _Stars extends StatelessWidget {
  const _Stars({
    required this.earned,
    required this.controller,
    required this.size,
  });

  final int earned;
  final Animation<double> controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$earned of 3 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: size * 0.08,
                vertical: i == 1 ? 0 : size * 0.12,
              ),
              child: i < earned
                  ? ScaleTransition(
                      scale: CurvedAnimation(
                        parent: controller,
                        curve: Interval(
                          0.18 + i * 0.16,
                          0.42 + i * 0.16,
                          curve: Curves.elasticOut,
                        ),
                      ),
                      child: StarIcon(filled: true, size: size),
                    )
                  : StarIcon(filled: false, size: size),
            ),
        ],
      ),
    );
  }
}
