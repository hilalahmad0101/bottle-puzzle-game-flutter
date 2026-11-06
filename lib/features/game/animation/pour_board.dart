import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../application/board_controller.dart';
import '../rendering/bottle_geometry.dart';
import '../rendering/bottle_static_layers.dart';
import '../rendering/bottle_style.dart';
import '../rendering/bottle_view.dart';
import '../rendering/liquid_life.dart' show kLiquidLifeLap;
import '../rendering/liquid_palette.dart';
import '../rendering/liquid_volume_model.dart';
import 'animation_settings.dart';
import 'board_layout.dart';
import 'pour_overlay_painter.dart';
import 'pour_plan.dart';

/// The playing field: every bottle, tap handling, and the pour animation.
///
/// It owns NO game state. It renders `controller.committedState` and, while
/// `controller.activePour` is set, hides the two bottles involved and draws
/// them (plus the stream) from a [PourPlan] instead. Starting, finishing and
/// interrupting an animation only ever flips `controller.activePour`; the
/// game itself is untouched.
class PourBoard extends StatefulWidget {
  const PourBoard({
    super.key,
    required this.controller,
    required this.palette,
    this.style = BottleStyles.alchemyClassic,
    this.assist = ColorAssist.off,
    this.settings = const AnimationSettings(),
    this.timeScaleMultiplier = 1.0,
    this.scrub,
    this.debugOverlay = false,
    this.fitToHeight = false,
    this.hintBottles = const {},
    this.liquidLife = false,
    this.highContrast = false,
    this.onTapOutcome,
    this.cache,
  });

  final BoardController controller;
  final LiquidPalette palette;
  final BottleStyle style;
  final ColorAssist assist;
  final AnimationSettings settings;

  /// Debug: >1 slows every animation down.
  final double timeScaleMultiplier;

  /// Debug: when non-null the animation is frozen at this progress (0..1).
  final ValueNotifier<double?>? scrub;
  final bool debugOverlay;

  /// Lay the bottles out to fit the available HEIGHT as well as the width
  /// (the playing screen). Off, the board is as tall as its width needs
  /// and is meant to scroll.
  final bool fitToHeight;

  /// Bottles to highlight as a hint.
  final Set<int> hintBottles;

  /// Idle bubbles and a shimmering surface in every bottle. The caller turns
  /// this on only when decorative motion is allowed; it is paused during
  /// a pour and while the app is in the background.
  final bool liquidLife;

  /// Draws the high-contrast outline and colour dividers on every bottle.
  final bool highContrast;
  final ValueChanged<TapOutcome>? onTapOutcome;
  final BottleLayerCache? cache;

  @override
  State<PourBoard> createState() => PourBoardState();
}

class PourBoardState extends State<PourBoard>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _anim = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);

  // The shared clock behind the idle bubbles (see LiquidLifeEffect). It runs
  // only while it is wanted: never during a pour, never in the background.
  late final AnimationController _life = AnimationController(
    vsync: this,
    duration: kLiquidLifeLap,
  );
  bool _foreground = true;

  /// Whether the idle liquid clock is ticking (for tests).
  @visibleForTesting
  bool get liquidLifeRunning => _life.isAnimating;

  void _syncLife() {
    final want = widget.liquidLife && _foreground && _plan == null;
    if (want && !_life.isAnimating) {
      _life.repeat();
    } else if (!want && _life.isAnimating) {
      _life.stop();
    }
  }

  BoardLayout? _layout;
  BottleGeometry? _geometry;
  BottleGeometry? _warmedFor;
  PourPlan? _plan;
  int? _planToken;
  double _lastScrub = 0;

  /// The plan being animated, if any (for the debug screen and tests).
  PourPlan? get currentPlan => _plan;

  /// The geometry the board currently lays bottles out with (for tests).
  @visibleForTesting
  BottleGeometry? get debugGeometry => _geometry;

  /// 0..1 progress of the running animation.
  double get progress => _anim.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onController);
    widget.scrub?.addListener(_onScrub);
    _syncLife();
  }

  @override
  void didUpdateWidget(PourBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
      _dropPlan();
    }
    if (oldWidget.scrub != widget.scrub) {
      oldWidget.scrub?.removeListener(_onScrub);
      widget.scrub?.addListener(_onScrub);
    }
    _syncLife();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = widget.controller;
    final token = _planToken;
    controller.removeListener(_onController);
    widget.scrub?.removeListener(_onScrub);
    _anim.dispose();
    _life.dispose();
    // Leaving the screen mid-pour: the move is already committed, so just
    // drop the replay (after teardown, so listeners are not notified while
    // the tree is being disposed).
    if (token != null) {
      scheduleMicrotask(() {
        if (!controller.isDisposed && controller.activePour?.token == token) {
          controller.interruptPour(InterruptReason.navigation);
        }
      });
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncLife();
    if (state != AppLifecycleState.resumed) {
      // A backgrounded app gets no frames, and the clock jumps on return:
      // never resume a half-finished pour, show the committed result.
      widget.controller.interruptPour(InterruptReason.background);
    }
  }

  void _onController() {
    final ap = widget.controller.activePour;
    if (ap == null) {
      if (_plan != null) _dropPlan();
      return;
    }
    if (_planToken == ap.token) return;
    _begin(ap);
  }

  void _begin(ActivePour ap) {
    final layout = _layout;
    final state = widget.controller.committedState;
    final move = ap.result.move;
    final cap = ap.result.sourceBefore!.capacity;
    if (layout == null ||
        layout.rects.length != state.bottleCount ||
        ap.result.destinationBefore!.capacity != cap) {
      // Cannot lay out the animation: show the result immediately.
      scheduleMicrotask(() => widget.controller.finishPour(ap.token));
      return;
    }
    final geometry = _geometryFor(layout, cap);
    final systemReduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final reduced = widget.settings.isReduced(
      systemPrefersReduced: systemReduce,
    );
    final plan = PourPlan.build(
      result: ap.result,
      geometry: geometry,
      sourceRect: layout.rects[move.source],
      destRect: layout.rects[move.destination],
      boardWidth: layout.size.width,
      timeScale: widget.settings.speed.timeScale * widget.timeScaleMultiplier,
      reducedMotion: reduced,
    );
    setState(() {
      _plan = plan;
      _planToken = ap.token;
    });
    _syncLife(); // bubbles rest while liquid moves
    _anim.duration = Duration(microseconds: (plan.duration * 1e6).round());
    if (widget.scrub?.value == null) {
      _anim.forward(from: 0);
    } else {
      _anim.value = 0;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final token = _planToken;
    if (token == null || widget.scrub?.value != null) return;
    _dropPlan();
    widget.controller.finishPour(token);
  }

  void _onScrub() {
    final v = widget.scrub?.value;
    if (_plan == null) return;
    if (v != null) {
      _lastScrub = v;
      _anim.stop();
    } else {
      _anim.forward(from: _lastScrub);
    }
  }

  void _dropPlan() {
    _anim.stop();
    _anim.value = 0;
    if (!mounted) return;
    setState(() {
      _plan = null;
      _planToken = null;
    });
    _syncLife();
  }

  /// The first tilt solves cost tens of milliseconds, which would hitch the
  /// frame in which the player taps. Do them once per geometry in the frame
  /// AFTER the board first appears, so the screen shows immediately and the
  /// cost is paid long before anyone can tap. (Not `scheduleTask` with idle
  /// priority: Flutter's default strategy never runs idle tasks and polls
  /// the event loop while it declines them.)
  void _warmUp(BottleGeometry g) {
    if (identical(_warmedFor, g)) return;
    _warmedFor = g;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final model = LiquidVolumeModel.of(g);
      for (final fill in LiquidVolumeModel.warmUpFills(g.capacity)) {
        model.requiredTilt(fill);
      }
    });
  }

  BottleGeometry _geometryFor(BoardLayout layout, int capacity) {
    final g = _geometry;
    if (g != null && g.size == layout.bottleSize && g.capacity == capacity) {
      return g;
    }
    return _geometry = widget.style.geometryFor(layout.bottleSize, capacity);
  }

  double _seconds() {
    final p = _plan;
    if (p == null) return 0;
    return (widget.scrub?.value ?? _anim.value) * p.duration;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 360.0;
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final c = widget.controller;
            final state = c.committedState;
            final layout = BoardLayout.compute(
              count: state.bottleCount,
              width: width,
              aspect: widget.style.spec.aspect,
              maxHeight: widget.fitToHeight && constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
            );
            final resized =
                _layout != null &&
                (_layout!.size != layout.size ||
                    _layout!.rects.length != layout.rects.length);
            _layout = layout;
            if (state.bottleCount > 0) {
              _warmUp(_geometryFor(layout, state.bottles.first.capacity));
            }
            if (resized && _plan != null) {
              // Layout changed under a running animation: stale geometry.
              final token = _planToken;
              scheduleMicrotask(() {
                if (mounted && _planToken == token) {
                  c.interruptPour(InterruptReason.other);
                }
              });
            }

            final plan = _plan;
            final involved = plan == null
                ? const <int>{}
                : {plan.result.move.source, plan.result.move.destination};

            return SizedBox(
              width: layout.size.width,
              height: layout.size.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < state.bottleCount; i++)
                    Positioned.fromRect(
                      rect: layout.rects[i],
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          final outcome = c.tapBottle(i);
                          widget.onTapOutcome?.call(outcome);
                        },
                        child: Offstage(
                          offstage: involved.contains(i),
                          child: BottleView(
                            bottle: state.bottles[i],
                            palette: widget.palette,
                            style: widget.style,
                            assist: widget.assist,
                            selected: c.selectedIndex == i,
                            hint: widget.hintBottles.contains(i),
                            // Hold the "solved" celebration until the pour
                            // that solved it has finished.
                            completed: involved.contains(i) ? false : null,
                            cache: widget.cache,
                            life: widget.liquidLife ? _life : null,
                            highContrast: widget.highContrast,
                            lifeSeed: i,
                          ),
                        ),
                      ),
                    ),
                  if (plan != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: layout.size,
                            painter: PourOverlayPainter(
                              plan: plan,
                              style: widget.style,
                              layers: (widget.cache ?? BottleLayerCache.shared)
                                  .obtain(
                                    widget.style,
                                    layout.bottleSize,
                                    plan.geometry.capacity,
                                  ),
                              palette: widget.palette,
                              assist: widget.assist,
                              debug: widget.debugOverlay,
                              repaint: widget.scrub == null
                                  ? _anim
                                  : Listenable.merge([_anim, widget.scrub]),
                              seconds: _seconds,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Reports frame timing (build + raster) for the debug screen.
final class FrameStats {
  FrameStats();

  final List<FrameTiming> _frames = [];

  void add(List<FrameTiming> timings) {
    _frames.addAll(timings);
    if (_frames.length > 120) _frames.removeRange(0, _frames.length - 120);
  }

  int get count => _frames.length;

  double get avgBuildMs => _avg((t) => t.buildDuration);
  double get avgRasterMs => _avg((t) => t.rasterDuration);
  double get worstTotalMs => _frames.isEmpty
      ? 0
      : _frames
            .map((t) => t.totalSpan.inMicroseconds / 1000)
            .reduce((a, b) => a > b ? a : b);

  /// Frames over the 60 fps budget of 16.7 ms.
  int get slowFrames =>
      _frames.where((t) => t.totalSpan.inMicroseconds > 16700).length;

  double _avg(Duration Function(FrameTiming) pick) => _frames.isEmpty
      ? 0
      : _frames
                .map((t) => pick(t).inMicroseconds / 1000)
                .reduce((a, b) => a + b) /
            _frames.length;

  void clear() => _frames.clear();

  TimingsCallback get callback => add;
}
