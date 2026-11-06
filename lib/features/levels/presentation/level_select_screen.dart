import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/navigation.dart';
import '../../../app/theme/app_colors.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_controls.dart';
import '../../../shared/widgets/alchemy_toast.dart';
import '../../../shared/widgets/ambient_motion.dart';
import '../../../shared/widgets/glass_panel.dart';
import '../../../shared/widgets/star_row.dart';
import '../../progress/application/providers.dart';
import '../../progress/domain/player_progress.dart';

/// Levels are shown in chapters of ten. There is no last level: more
/// chapters appear as you scroll, and the list only builds what is visible.
class LevelSelectScreen extends ConsumerStatefulWidget {
  const LevelSelectScreen({super.key});

  static const int perChapter = 10;

  @override
  ConsumerState<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends ConsumerState<LevelSelectScreen> {
  ScrollController? _scroll;
  int _extraChapters = 0;
  String? _toast;
  int _toastId = 0;
  double _lastExtent = 0;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  void _showToast(String m) {
    final id = ++_toastId;
    setState(() => _toast = m);
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      if (mounted && id == _toastId) setState(() => _toast = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(progressProvider);
    final current = progress.currentLevel;
    final currentChapter = (current - 1) ~/ LevelSelectScreen.perChapter;
    final chapterCount = math.max(3, currentChapter + 3) + _extraChapters;

    return Scaffold(
      backgroundColor: AppColors.midnightTop,
      body: AlchemyBackground(
        child: SafeArea(
          child: Column(
            children: [
              AlchemyAppBar(title: 'LEVELS', onBack: () => context.pop()),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _Summary(progress: progress),
              ),
              Expanded(
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, c) {
                        final geo = _Geometry.of(c.maxWidth);
                        // Open on the current chapter (exact: rows are fixed height).
                        if (_scroll == null ||
                            (_lastExtent - geo.extent).abs() > 0.5) {
                          final off = math.max(
                            0.0,
                            currentChapter * geo.extent - geo.extent * 0.15,
                          );
                          _scroll?.dispose();
                          _scroll = ScrollController(initialScrollOffset: off);
                          _lastExtent = geo.extent;
                        }
                        return ListView.builder(
                          key: const Key('levels.list'),
                          controller: _scroll,
                          itemExtent: geo.extent,
                          itemCount: chapterCount,
                          padding: EdgeInsets.fromLTRB(geo.pad, 0, geo.pad, 24),
                          itemBuilder: (context, i) {
                            if (i == chapterCount - 1) {
                              // Reached the end: there are always more.
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() => _extraChapters += 4);
                                }
                              });
                            }
                            return _Chapter(
                              index: i,
                              geo: geo,
                              progress: progress,
                              onLocked: (n) => _showToast(
                                'Complete level $current to unlock level $n',
                              ),
                              onOpen: (n) => openLevel(context, ref, n),
                            );
                          },
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

/// Sizes derived from the screen width. Everything is deterministic, so a
/// chapter always has the same height.
class _Geometry {
  _Geometry(this.pad, this.cols, this.tile, this.gap, this.extent);

  final double pad;
  final int cols;
  final double tile;
  final double gap;
  final double extent;

  static const double header = 64;

  static _Geometry of(double width) {
    const pad = 16.0, gap = 8.0;
    final cols = width >= 640 ? 10 : 5;
    final tile = math
        .min(((width - 2 * pad - (cols - 1) * gap) / cols), 76.0)
        .clamp(40.0, 76.0);
    final rows = LevelSelectScreen.perChapter ~/ cols;
    final extent = header + rows * tile + (rows - 1) * gap + 22;
    return _Geometry(pad, cols, tile, gap, extent);
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.progress});

  final PlayerProgress progress;

  @override
  Widget build(BuildContext context) {
    Widget stat(
      IconData? icon,
      Widget? lead,
      String value,
      String label,
      Key key,
    ) => Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ?lead,
              if (icon != null) Icon(icon, size: 18, color: AppColors.cyanGlow),
              const SizedBox(width: 5),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    key: key,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );

    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          stat(
            null,
            const StarIcon(filled: true, size: 18),
            '${progress.totalStars}',
            'STARS',
            const Key('levels.stars'),
          ),
          stat(
            Icons.check_circle_outline,
            null,
            '${progress.completedCount}',
            'COMPLETED',
            const Key('levels.completed'),
          ),
          stat(
            Icons.play_circle_outline,
            null,
            '${progress.currentLevel}',
            'CURRENT',
            const Key('levels.current'),
          ),
        ],
      ),
    );
  }
}

class _Chapter extends StatelessWidget {
  const _Chapter({
    required this.index,
    required this.geo,
    required this.progress,
    required this.onLocked,
    required this.onOpen,
  });

  final int index;
  final _Geometry geo;
  final PlayerProgress progress;
  final ValueChanged<int> onLocked;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final first = index * LevelSelectScreen.perChapter + 1;
    final last = first + LevelSelectScreen.perChapter - 1;
    final done = progress.completedIn(first, last);
    final stars = progress.starsIn(first, last);
    final rows = LevelSelectScreen.perChapter ~/ geo.cols;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _Geometry.header,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    flex: 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'CHAPTER ${index + 1}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    flex: 3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const StarIcon(filled: true, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$stars/${LevelSelectScreen.perChapter * 3}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$done/${LevelSelectScreen.perChapter}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: done / LevelSelectScreen.perChapter,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation(AppColors.gold),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) SizedBox(height: geo.gap),
          Row(
            children: [
              for (var k = 0; k < geo.cols; k++) ...[
                if (k > 0) SizedBox(width: geo.gap),
                Builder(
                  builder: (context) {
                    final n = first + r * geo.cols + k;
                    return SizedBox(
                      width: geo.tile,
                      height: geo.tile,
                      child: _Tile(
                        level: n,
                        record: progress.recordOf(n),
                        isCurrent: n == progress.currentLevel,
                        locked: !progress.isUnlocked(n),
                        hasSave: progress.saved.containsKey(n),
                        onTap: () =>
                            progress.isUnlocked(n) ? onOpen(n) : onLocked(n),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _Tile extends ConsumerStatefulWidget {
  const _Tile({
    required this.level,
    required this.record,
    required this.isCurrent,
    required this.locked,
    required this.hasSave,
    required this.onTap,
  });

  final int level;
  final LevelRecord? record;
  final bool isCurrent;
  final bool locked;
  final bool hasSave;
  final VoidCallback onTap;

  @override
  ConsumerState<_Tile> createState() => _TileState();
}

class _TileState extends ConsumerState<_Tile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String get _label {
    if (widget.locked) return 'Level ${widget.level}, locked';
    final r = widget.record;
    if (r != null) {
      return 'Level ${widget.level}, completed, ${r.stars} stars, best ${r.bestMoves} moves';
    }
    return 'Level ${widget.level}, current level${widget.hasSave ? ', game in progress' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final animate = widget.isCurrent && ambientMotionAllowed(context, ref);
    if (animate && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!animate && _pulse.isAnimating) {
      _pulse.stop();
    }
    final done = widget.record != null;
    return Semantics(
      button: true,
      label: _label,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('level.${widget.level}'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final glow = widget.isCurrent ? 0.25 + 0.3 * _pulse.value : 0.0;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: widget.isCurrent
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.goldLight,
                          AppColors.gold,
                          AppColors.goldDeep,
                        ],
                      )
                    : null,
                color: widget.isCurrent
                    ? null
                    : (widget.locked
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.white.withValues(alpha: 0.12)),
                border: Border.all(
                  color: widget.isCurrent
                      ? AppColors.goldLight
                      : (done
                            ? AppColors.gold.withValues(alpha: 0.5)
                            : AppColors.glassBorder),
                ),
                boxShadow: [
                  if (widget.isCurrent)
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: glow),
                      blurRadius: 16,
                    ),
                ],
              ),
              child: child,
            );
          },
          child: widget.locked
              ? const Center(
                  child: Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: Colors.white30,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(3),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '${widget.level}',
                              style: TextStyle(
                                color: widget.isCurrent
                                    ? const Color(0xFF2A1A00)
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ),
                        ),
                        if (done)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: StarRow(
                              earned: widget.record!.stars,
                              size: 12,
                              gap: 1,
                            ),
                          )
                        else if (widget.hasSave)
                          const Icon(
                            Icons.pause_circle_outline,
                            size: 14,
                            color: Color(0xFF2A1A00),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
