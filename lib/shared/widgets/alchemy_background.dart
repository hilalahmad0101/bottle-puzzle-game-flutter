import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/generator/seeded_random.dart';
import '../../features/journey/application/journey_providers.dart';
import '../../features/journey/domain/journey.dart';
import '../../features/settings/application/settings_providers.dart';
import 'ambient_motion.dart';

/// The shared laboratory backdrop: a deep gradient, two soft coloured glows
/// and slowly rising motes of light. Its colours come from the player's
/// chapter of the Alchemy Journey (Midnight Lab at the start, more colour as
/// levels are completed) and change smoothly when a new chapter is reached.
/// The motes only move while ambient motion is allowed (not with reduced
/// motion), and live in their own repaint layer.
class AlchemyBackground extends ConsumerStatefulWidget {
  const AlchemyBackground({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AlchemyBackground> createState() => _AlchemyBackgroundState();
}

class _AlchemyBackgroundState extends ConsumerState<AlchemyBackground>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  );

  // Chapter change: blend from the old palette to the new one.
  late final AnimationController _blend = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );
  JourneyStage? _from;
  JourneyStage? _to;

  @override
  void dispose() {
    _c.dispose();
    _blend.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _from = _to = ref.read(journeyStageProvider);
    _blend.value = 1;
    // Not in build: starting an animation there would rebuild mid-build.
    ref.listenManual(journeyStageProvider, (_, next) => _onStage(next));
  }

  void _onStage(JourneyStage next) {
    final current = _to!;
    final animate =
        mounted &&
        ref.read(ambientMotionProvider) &&
        !ref
            .read(animationSettingsProvider)
            .isReduced(
              systemPrefersReduced:
                  MediaQuery.maybeDisableAnimationsOf(context) ?? false,
            );
    if (!animate) {
      setState(() {
        _from = _to = next;
        _blend.value = 1;
      });
      return;
    }
    if (current == next) return;
    _from = JourneyStage.lerp(_from ?? current, current, _blend.value);
    _to = next;
    _blend
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final animate = ambientMotionAllowed(context, ref);
    final contrast = ref.watch(highContrastProvider);
    if (animate && !_c.isAnimating) {
      _c.repeat();
    } else if (!animate && _c.isAnimating) {
      _c.stop();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _blend,
          builder: (context, _) {
            final s = JourneyStage.lerp(_from!, _to!, _blend.value);
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [s.top, s.mid, s.bottom],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _MotesPainter(
                      _c,
                      _motes,
                      glowA: s.glowA,
                      glowB: s.glowB,
                      tints: s.motes,
                      calm: contrast,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        widget.child,
      ],
    );
  }

  static final List<_Mote> _motes = () {
    final r = SeededRandom(2024);
    return [
      for (var i = 0; i < 38; i++)
        _Mote(
          x: r.nextInt(1000) / 1000,
          y: r.nextInt(1000) / 1000,
          size: 0.6 + r.nextInt(100) / 100 * 1.8,
          speed: 0.6 + r.nextInt(100) / 100,
          phase: r.nextInt(1000) / 1000,
          tintIndex: i,
        ),
    ];
  }();
}

class _Mote {
  const _Mote({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.tintIndex,
  });

  final double x, y, size, speed, phase;
  final int tintIndex;
}

class _MotesPainter extends CustomPainter {
  _MotesPainter(
    this.t,
    this.motes, {
    required this.glowA,
    required this.glowB,
    required this.tints,
    required this.calm,
  }) : super(repaint: t);

  final Animation<double> t;
  final List<_Mote> motes;
  final Color glowA, glowB;
  final List<Color> tints;

  /// High-contrast mode: fainter glows and no drifting motes, so nothing
  /// busy sits behind the text and bottles.
  final bool calm;

  @override
  void paint(Canvas canvas, Size size) {
    // Two soft glows give the scene depth.
    final rectA = Rect.fromCircle(
      center: Offset(size.width * 0.85, size.height * 0.08),
      radius: size.shortestSide * 0.9,
    );
    canvas.drawRect(
      rectA,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowA.withValues(alpha: calm ? 0.12 : 0.28),
            Colors.transparent,
          ],
        ).createShader(rectA),
    );
    final rectB = Rect.fromCircle(
      center: Offset(size.width * 0.05, size.height * 0.95),
      radius: size.shortestSide * 0.8,
    );
    canvas.drawRect(
      rectB,
      Paint()
        ..shader = RadialGradient(
          colors: [
            glowB.withValues(alpha: calm ? 0.06 : 0.14),
            Colors.transparent,
          ],
        ).createShader(rectB),
    );

    if (calm) return;
    final time = t.value;
    for (final m in motes) {
      final y = ((m.y - time * m.speed * 6) % 1 + 1) % 1;
      final twinkle =
          0.5 + 0.5 * math.sin(2 * math.pi * (time * 20 * m.speed + m.phase));
      canvas.drawCircle(
        Offset(m.x * size.width, y * size.height),
        m.size,
        Paint()
          ..color = tints[m.tintIndex % tints.length].withValues(
            alpha: 0.10 + 0.32 * twinkle,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_MotesPainter old) =>
      old.glowA != glowA ||
      old.glowB != glowB ||
      old.calm != calm ||
      !identical(old.tints, tints) && !_same(old.tints, tints);

  static bool _same(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
