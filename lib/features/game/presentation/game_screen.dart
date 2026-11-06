import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../engine/generator/difficulty.dart';
import '../../../shared/widgets/alchemy_background.dart';
import '../../../shared/widgets/alchemy_button.dart';
import '../../../shared/widgets/alchemy_toast.dart';
import '../../../shared/widgets/brand_logo.dart';
import '../../../shared/widgets/difficulty_indicator.dart';
import '../../../shared/widgets/ambient_motion.dart';
import '../../settings/application/settings_providers.dart';
import '../animation/pour_board.dart';
import '../application/game_session.dart';
import 'pause_menu.dart';

/// The playing screen. Everything on it is read from the real [GameSession]
/// (board, move count, difficulty) and every button calls the real action.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final GameSession _session = ref.read(gameSessionProvider);
  Timer? _completeTimer;
  Timer? _noticeTimer;
  bool _completeScheduled = false;
  int _noticeHandled = 0;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    // The session may already be finished (a restored, solved game). That
    // check reads MediaQuery, which is not allowed inside initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onSession();
    });
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    _completeTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _onSession() {
    final s = _session;
    if (s.status == SessionStatus.completed) {
      if (!_completeScheduled && s.result != null) {
        _completeScheduled = true;
        // Let the last pour settle and the solved bottle glow first.
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        _completeTimer = Timer(Duration(milliseconds: reduce ? 250 : 1000), () {
          if (mounted && _session.status == SessionStatus.completed) {
            context.push(AppRoutes.complete);
          }
        });
      }
    } else {
      _completeScheduled = false;
      _completeTimer?.cancel();
    }
    if (s.notice != null && s.noticeId != _noticeHandled) {
      _noticeHandled = s.noticeId;
      _noticeTimer?.cancel();
      final id = s.noticeId;
      _noticeTimer = Timer(
        const Duration(milliseconds: 3200),
        () => s.dismissNotice(id),
      );
    }
  }

  Future<void> _openPause() async {
    if (_dialogOpen || _session.status != SessionStatus.playing) return;
    _dialogOpen = true;
    _session.pause();
    var action = PauseAction.resume;
    while (mounted) {
      final r = await showAlchemyDialog<PauseAction>(
        context,
        label: 'Pause menu',
        child: PauseMenu(
          level: _session.level?.levelNumber ?? 0,
          moves: _session.moves,
        ),
      );
      action = r ?? PauseAction.resume;
      if (action == PauseAction.settings && mounted) {
        await context.push<void>(AppRoutes.settings);
        continue; // back from settings: show the menu again
      }
      break;
    }
    _dialogOpen = false;
    _session.resume();
    if (!mounted) return;
    switch (action) {
      case PauseAction.restart:
        _session.restart();
      case PauseAction.home:
        context.go(AppRoutes.home);
      case PauseAction.resume:
      case PauseAction.settings:
        break;
    }
  }

  Future<void> _restart() async {
    final moves = _session.moves;
    if (moves == 0) {
      _session.restart();
      return;
    }
    if (_dialogOpen) return;
    _dialogOpen = true;
    _session.pause();
    final ok = await showAlchemyDialog<bool>(
      context,
      label: 'Restart level',
      child: ConfirmRestart(moves: moves),
    );
    _dialogOpen = false;
    _session.resume();
    if (ok == true) _session.restart();
  }

  /// The extra bottle changes how the level scores, so ask first.
  Future<void> _booster() async {
    if (_dialogOpen || !_session.canUseBooster) return;
    _dialogOpen = true;
    _session.pause();
    final ok = await showAlchemyDialog<bool>(
      context,
      label: 'Extra bottle',
      child: const ConfirmBooster(),
    );
    _dialogOpen = false;
    _session.resume();
    if (ok == true) _session.useBooster();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openPause();
      },
      child: Scaffold(
        backgroundColor: AppColors.midnightTop,
        body: AlchemyBackground(
          child: SafeArea(
            // Big system text must never break the HUD.
            child: MediaQuery(
              data: mq.copyWith(
                textScaler: mq.textScaler.clamp(maxScaleFactor: 1.35),
              ),
              child: ListenableBuilder(
                listenable: _session,
                builder: (context, _) => _body(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = _session;
    switch (s.status) {
      case SessionStatus.idle:
      case SessionStatus.loading:
        return const _Loading();
      case SessionStatus.failed:
        return _Failed(
          onRetry: () => s.startLevel(s.level?.levelNumber ?? 1),
          onHome: () => context.go(AppRoutes.home),
        );
      case SessionStatus.playing:
      case SessionStatus.completed:
        return _playing(context, s);
    }
  }

  Widget _playing(BuildContext context, GameSession s) {
    final settings = ref.watch(appSettingsProvider);
    final style = ref.watch(bottleStyleProvider);
    final board = s.board!;
    final level = s.level!;

    final boardWidget = PourBoard(
      key: ValueKey(s.runId),
      controller: board,
      palette: s.palette!,
      style: style,
      assist: settings.colorAssist,
      settings: settings.animation,
      fitToHeight: true,
      hintBottles: s.hintBottles,
      liquidLife: ambientMotionAllowed(context, ref) && !settings.highContrast,
      highContrast: settings.highContrast,
      onTapOutcome: s.onTap,
    );

    _Hud hudFor({required bool vertical}) => _Hud(
      level: level.levelNumber,
      difficulty: level.difficulty,
      moves: s.moves,
      par: s.par,
      onPause: _openPause,
      vertical: vertical,
    );
    final actions = ListenableBuilder(
      listenable: board,
      builder: (context, _) => _Actions(
        canUndo: s.canUndo,
        hintBusy: s.hintLoading,
        canHint: s.isPlaying && !board.isPouring && !board.isPaused,
        canRestart: s.isPlaying,
        showBooster: s.boosterEnabled,
        canBooster: s.canUseBooster,
        boosted: s.boosted,
        onUndo: s.undo,
        onHint: s.requestHint,
        onRestart: _restart,
        onBooster: _booster,
        onUnavailable: s.explainUnavailable,
        reasonFor: s.whyUnavailable,
      ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.2;
        final stage = Stack(
          children: [
            Positioned.fill(child: Center(child: boardWidget)),
            if (s.notice != null)
              Positioned(
                left: 16,
                right: 16,
                top: 4,
                child: Center(
                  child: AlchemyToast(
                    key: ValueKey(s.noticeId),
                    message: s.notice!,
                    icon: Icons.lightbulb_outline,
                  ),
                ),
              ),
          ],
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: stage),
              // The side panel scales its content down if the screen is short
              // (landscape + very large text) instead of scrolling, so every
              // control stays visible.
              SizedBox(
                width: (c.maxWidth * 0.26).clamp(190.0, 280.0),
                height: c.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: (c.maxWidth * 0.26).clamp(190.0, 280.0) - 12,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            hudFor(vertical: true),
                            const SizedBox(height: 18),
                            actions,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            hudFor(vertical: false),
            Expanded(child: stage),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: actions,
            ),
          ],
        );
      },
    );
  }
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.level,
    required this.difficulty,
    required this.moves,
    required this.par,
    required this.onPause,
    this.vertical = false,
  });

  /// Stacked layout for the narrow side panel in landscape.
  final bool vertical;

  final int level;
  final Difficulty difficulty;
  final int moves;
  final int par;
  final VoidCallback onPause;

  Widget _title() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'LEVEL $level',
          key: const Key('game.level'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.5,
          ),
        ),
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: DifficultyIndicator(difficulty: difficulty),
      ),
    ],
  );

  Widget _moves() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text(
        'MOVES',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10.5,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$moves',
          key: const Key('game.moves'),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            height: 1.05,
          ),
        ),
      ),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          'par $par',
          key: const Key('game.par'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
      ),
    ],
  );

  Widget _pause() => OrbButton(
    key: const Key('game.pause'),
    icon: Icons.pause_rounded,
    label: 'Pause',
    showLabel: false,
    size: 48,
    onPressed: onPause,
  );

  @override
  Widget build(BuildContext context) {
    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pause(),
          const SizedBox(height: 8),
          _title(),
          const SizedBox(height: 10),
          _moves(),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(
        children: [
          _pause(),
          Expanded(child: _title()),
          SizedBox(width: 72, child: _moves()),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.canUndo,
    required this.hintBusy,
    required this.canHint,
    required this.canRestart,
    required this.showBooster,
    required this.canBooster,
    required this.boosted,
    required this.onUndo,
    required this.onHint,
    required this.onRestart,
    required this.onBooster,
    required this.onUnavailable,
    required this.reasonFor,
  });

  final bool canUndo;
  final bool hintBusy;
  final bool canHint;
  final bool canRestart;
  final bool showBooster;
  final bool canBooster;
  final bool boosted;
  final VoidCallback onUndo;
  final VoidCallback onHint;
  final VoidCallback onRestart;
  final VoidCallback onBooster;
  final void Function(GameAction) onUnavailable;
  final String? Function(GameAction) reasonFor;

  @override
  Widget build(BuildContext context) {
    // Wrap, not Row: in the narrow landscape side panel (or with very large
    // text) the orbs flow onto a second line instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.spaceEvenly,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: 12,
      runSpacing: 10,
      children: [
        OrbButton(
          key: const Key('game.undo'),
          icon: Icons.undo_rounded,
          label: 'Undo',
          onPressed: canUndo ? onUndo : null,
          onDisabledTap: () => onUnavailable(GameAction.undo),
          unavailableReason: reasonFor(GameAction.undo),
        ),
        OrbButton(
          key: const Key('game.hint'),
          icon: Icons.lightbulb_outline_rounded,
          label: 'Hint',
          accent: AppColors.gold,
          busy: hintBusy,
          onPressed: canHint ? onHint : null,
          onDisabledTap: () => onUnavailable(GameAction.hint),
          unavailableReason: reasonFor(GameAction.hint),
        ),
        OrbButton(
          key: const Key('game.restart'),
          icon: Icons.refresh_rounded,
          label: 'Restart',
          onPressed: canRestart ? onRestart : null,
        ),
        if (showBooster)
          OrbButton(
            key: const Key('game.booster'),
            icon: boosted ? Icons.add_box_rounded : Icons.add_box_outlined,
            label: 'Bottle',
            accent: AppColors.gold,
            onPressed: canBooster ? onBooster : null,
            onDisabledTap: () => onUnavailable(GameAction.booster),
            unavailableReason: reasonFor(GameAction.booster),
          ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          BrandEmblem(height: 110, progress: 0.55),
          SizedBox(height: 18),
          Text(
            'Mixing the elixirs…',
            key: Key('game.loading'),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.onRetry, required this.onHome});

  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This level couldn't be prepared.",
              key: Key('game.failed'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            AlchemyButton(
              label: 'TRY AGAIN',
              expand: false,
              onPressed: onRetry,
            ),
            const SizedBox(height: 8),
            AlchemyButton(
              label: 'HOME',
              kind: AlchemyButtonKind.quiet,
              expand: false,
              onPressed: onHome,
            ),
          ],
        ),
      ),
    );
  }
}
