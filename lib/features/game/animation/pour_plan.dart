import 'dart:math' as math;
import 'dart:ui';

import '../../../engine/generator/seeded_random.dart';
import '../../../engine/models/color_unit.dart';
import '../../../engine/models/move_result.dart';
import '../rendering/bottle_geometry.dart';
import '../rendering/liquid_layer.dart';
import '../rendering/liquid_layer_painter.dart' show LiquidSurface;
import '../rendering/liquid_volume_model.dart';
import 'liquid_levels.dart';

enum PourPhase { approach, pouring, returning, settling, done }

abstract final class PourEasing {
  static double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  static double smoothstep(double t) {
    final x = clamp01(t);
    return x * x * (3 - 2 * x);
  }

  static double easeInOutCubic(double t) {
    final x = clamp01(t);
    return x < 0.5 ? 4 * x * x * x : 1 - math.pow(-2 * x + 2, 3) / 2;
  }

  /// Cumulative fraction poured at pour-progress [t]: a gentle ease at both
  /// ends with a steady middle. F(0)=0, F(1)=1, strictly increasing.
  static double flow(double t) {
    final x = clamp01(t);
    return 0.5 * x + 0.5 * smoothstep(x);
  }

  /// dF/dt, normalised to 0..1.
  static double flowRate(double t) {
    final x = clamp01(t);
    return (0.5 + 3 * x * (1 - x)) / 1.25;
  }
}

/// A curved liquid stream: cubic Bezier p0..p3 from the bottle lip to the
/// surface it lands on. Only the part between [tail] and [head] (path
/// parameters 0..1) is visible.
final class StreamFrame {
  const StreamFrame({
    required this.p0,
    required this.p1,
    required this.p2,
    required this.p3,
    required this.width,
    required this.head,
    required this.tail,
    required this.color,
  });

  final Offset p0, p1, p2, p3;
  final double width;
  final double head;
  final double tail;
  final ColorUnit color;

  Offset at(double s) {
    final u = 1 - s;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * s) +
        p2 * (3 * u * s * s) +
        p3 * (s * s * s);
  }

  Offset tangent(double s) {
    final u = 1 - s;
    return (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * s) +
        (p3 - p2) * (3 * s * s);
  }
}

/// Everything the painter needs for one instant. All positions are in board
/// coordinates.
final class PourFrame {
  const PourFrame({
    required this.time,
    required this.phase,
    required this.sourceAnchor,
    required this.sourceAngle,
    required this.sourceSpans,
    required this.sourceSurface,
    required this.destSpans,
    required this.destSurface,
    required this.stream,
    required this.glow,
    required this.impact,
    required this.particleTime,
    required this.particleStrength,
  });

  final double time;
  final PourPhase phase;

  /// World position of the source bottle's local `geometry.mouth` point.
  final Offset sourceAnchor;

  /// Clockwise rotation of the source bottle (radians; signed by side).
  final double sourceAngle;
  final List<LiquidLayerSpan> sourceSpans;
  final LiquidSurface sourceSurface;
  final List<LiquidLayerSpan> destSpans;
  final LiquidSurface destSurface;
  final StreamFrame? stream;

  /// 0..1 strength of the selection glow around the moving bottle.
  final double glow;

  /// Where the stream meets the destination liquid.
  final Offset impact;

  /// Seconds since the stream reached the destination.
  final double particleTime;

  /// 0..1 strength of splash/bubbles.
  final double particleStrength;
}

/// A splash droplet.
final class Droplet {
  const Droplet(this.position, this.radius, this.alpha);
  final Offset position;
  final double radius;
  final double alpha;
}

/// A bubble inside the destination liquid, relative to the surface point
/// under the stream (x offset, depth below surface).
final class Bubble {
  const Bubble(this.dx, this.depth, this.radius, this.alpha);
  final double dx;
  final double depth;
  final double radius;
  final double alpha;
}

/// The complete, deterministic choreography of ONE pour.
///
/// It is a pure function of the engine's [MoveResult], the bottle layout and
/// the settings. `frameAt(seconds)` depends only on wall-clock seconds (never
/// on frame counts), so timing is device independent and unit-testable.
///
/// Sequence (normal speed): approach (bottle rises, flies over the
/// destination and tilts) -> pour (stream, levels move, ripples) -> return
/// -> settle. The destination fills after the stream's flight time, so a
/// little liquid is always "in the air" in between.
final class PourPlan {
  PourPlan._({
    required this.result,
    required this.geometry,
    required this.sourceRect,
    required this.destRect,
    required this.side,
    required this.reduced,
    required this.timeScale,
    required this.quantity,
    required this.tApproachEnd,
    required this.tPourEnd,
    required this.tStreamEnd,
    required this.tReturnStart,
    required this.tReturnEnd,
    required this.duration,
    required this.lipTarget,
    required this.angleTable,
    required this.seed,
  });

  final MoveResult result;
  final BottleGeometry geometry;
  final Rect sourceRect;
  final Rect destRect;

  /// +1: the source tilts clockwise (mouth to the right); -1 the opposite.
  final int side;
  final bool reduced;
  final double timeScale;
  final int quantity;

  final double tApproachEnd;
  final double tPourEnd;
  final double tStreamEnd;
  final double tReturnStart;
  final double tReturnEnd;

  /// Total length in seconds.
  final double duration;

  /// Board position the source's pour lip is held at while pouring.
  final Offset lipTarget;

  /// (source fill in units, tilt magnitude in radians), fill descending.
  final List<(double, double)> angleTable;
  final int seed;

  /// Largest tilt used (about 103 degrees). Past 90 degrees the base of the
  /// bottle swings ABOVE the lip, so an unlimited tilt (an emptied bottle
  /// would need ~115 degrees) would push the bottle off the top of the board.
  static const double maxTilt = 1.8;

  /// The lift a selected bottle has (matches `BottleView`).
  static const double liftFraction = 0.07;

  static PourPlan build({
    required MoveResult result,
    required BottleGeometry geometry,
    required Rect sourceRect,
    required Rect destRect,
    required double boardWidth,
    double timeScale = 1.0,
    bool reducedMotion = false,
  }) {
    assert(result.isSuccess, 'only successful moves can be animated');
    assert(timeScale > 0);
    final q = result.quantity;
    final k = timeScale;
    final w = destRect.width;
    final h = destRect.height;

    // Which way to tilt: toward the destination, unless the bottle's body
    // (which extends the other way) would leave the board.
    final dx = destRect.center.dx - sourceRect.center.dx;
    final preferred = dx >= 0 ? 1 : -1;
    int pick() {
      double overflow(int s) {
        final lipX = destRect.center.dx - s * 0.38 * w;
        final lo = s == 1 ? lipX - h * 0.98 : lipX - 0.5 * w;
        final hi = s == 1 ? lipX + 0.5 * w : lipX + h * 0.98;
        return math.max(0.0, -lo) + math.max(0.0, hi - boardWidth);
      }

      final a = overflow(preferred), b = overflow(-preferred);
      return a <= b ? preferred : -preferred;
    }

    final side = pick();

    // Timeline.
    final approach = reducedMotion ? 0.0 : 0.50 * k;
    final pour = reducedMotion ? 0.32 * k : (0.34 + 0.27 * q) * k;
    final flight = reducedMotion ? 0.0 : 0.12 * k;
    final ret = reducedMotion ? 0.0 : 0.50 * k;
    final settle = reducedMotion ? 0.0 : 0.24 * k;
    final tA = approach;
    final tP = tA + pour;
    final tS = tP + flight;
    final tR0 = tP + (reducedMotion ? 0.0 : 0.06 * k);
    final tR1 = tR0 + ret;
    final duration = tR1 + settle;

    // Tilt needed as the source empties (solved on the real hollow).
    final model = LiquidVolumeModel.of(geometry);
    final before = result.sourceBefore!.length.toDouble();
    final after = result.sourceAfter!.length.toDouble();
    final samples = q * 4 + 1;
    final table = <(double, double)>[
      for (var i = 0; i < samples; i++)
        () {
          final fill = before + (after - before) * i / (samples - 1);
          return (fill, math.min(maxTilt, model.requiredTilt(fill) + 0.06));
        }(),
    ];

    final lipTarget = Offset(
      destRect.center.dx - side * 0.38 * w,
      destRect.top + geometry.mouth.dy - 0.25 * h,
    );

    return PourPlan._(
      result: result,
      geometry: geometry,
      sourceRect: sourceRect,
      destRect: destRect,
      side: side,
      reduced: reducedMotion,
      timeScale: timeScale,
      quantity: q,
      tApproachEnd: tA,
      tPourEnd: tP,
      tStreamEnd: tS,
      tReturnStart: tR0,
      tReturnEnd: tR1,
      duration: duration,
      lipTarget: lipTarget,
      angleTable: table,
      seed: StableHash.words([
        result.move.source,
        result.move.destination,
        q,
        result.sourceBefore!.length,
      ]),
    );
  }

  Offset get homeAnchor => sourceRect.topLeft + geometry.mouth;

  Offset get liftedAnchor =>
      homeAnchor + Offset(0, -liftFraction * sourceRect.height);

  /// Board position of a bottle-local [local] point when the bottle's mouth
  /// anchor is at [anchor] and it is rotated by [angle].
  Offset worldPoint(Offset anchor, double angle, Offset local) {
    final v = local - geometry.mouth;
    final c = math.cos(angle), s = math.sin(angle);
    return anchor + Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// Anchor that places the pour lip exactly on [lipTarget] at [angle].
  Offset anchorForLip(double angle) {
    final lip = geometry.pourLip(side.toDouble());
    final v = lip - geometry.mouth;
    final c = math.cos(angle), s = math.sin(angle);
    return lipTarget - Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// Tilt magnitude (radians) while the source holds [fill] units.
  double tiltAtFill(double fill) {
    final t = angleTable;
    final hi = t.first.$1, lo = t.last.$1;
    final f = fill.clamp(math.min(hi, lo), math.max(hi, lo));
    final x = (hi - f) / (hi - lo) * (t.length - 1);
    final i = x.floor().clamp(0, t.length - 2);
    final r = x - i;
    return t[i].$2 + (t[i + 1].$2 - t[i].$2) * r;
  }

  double get startTilt =>
      side * tiltAtFill(result.sourceBefore!.length.toDouble());
  double get endTilt =>
      side * tiltAtFill(result.sourceAfter!.length.toDouble());

  PourPhase phaseAt(double t) {
    if (t >= duration) return PourPhase.done;
    if (reduced) return PourPhase.pouring;
    if (t < tApproachEnd) return PourPhase.approach;
    if (t < tReturnStart) return PourPhase.pouring;
    if (t < tReturnEnd) return PourPhase.returning;
    return PourPhase.settling;
  }

  Offset _lerp(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;

  PourFrame frameAt(double seconds) {
    final t = seconds.clamp(0.0, duration).toDouble();
    final q = quantity.toDouble();
    final srcUnits = result.sourceBefore!.units;
    final dstUnits = result.destinationBefore!.units;
    final color = result.color!;
    final pourDur = reduced ? duration : tPourEnd - tApproachEnd;
    final flight = tStreamEnd - tPourEnd;

    // Levels.
    final tauSrc = PourEasing.clamp01((t - tApproachEnd) / pourDur);
    final tauDst = reduced
        ? tauSrc
        : PourEasing.clamp01((t - tApproachEnd - flight) / pourDur);
    final srcFill = reduced
        ? PourEasing.smoothstep(tauSrc)
        : PourEasing.flow(tauSrc);
    final dstFill = reduced
        ? PourEasing.smoothstep(tauDst)
        : PourEasing.flow(tauDst);
    final srcSpans = LiquidLayerSpan.fromUnits(srcUnits);
    final sourceSpans = LiquidLevels.drained(srcUnits, q * srcFill);
    final destSpans = LiquidLevels.filled(dstUnits, color, q * dstFill);
    assert(srcSpans.isNotEmpty);

    final destFillUnits = dstUnits.length + q * dstFill;
    final impact = Offset(
      destRect.center.dx,
      destRect.top +
          geometry.liquidBounds.bottom -
          destFillUnits * geometry.unitHeight,
    );

    if (reduced) {
      return PourFrame(
        time: t,
        phase: phaseAt(t),
        sourceAnchor: homeAnchor,
        sourceAngle: 0,
        sourceSpans: sourceSpans,
        sourceSurface: LiquidSurface.rest,
        destSpans: destSpans,
        destSurface: LiquidSurface.rest,
        stream: null,
        glow: 0,
        impact: impact,
        particleTime: 0,
        particleStrength: 0,
      );
    }

    final h = sourceRect.height;
    var anchor = homeAnchor;
    var angle = 0.0;
    double glow = 0;

    if (t < tApproachEnd) {
      final p = t / tApproachEnd;
      final e = PourEasing.easeInOutCubic(p);
      final a = startTilt;
      angle = a * PourEasing.easeInOutCubic((p - 0.15) / 0.85);
      anchor =
          _lerp(liftedAnchor, anchorForLip(a), e) +
          Offset(0, -math.sin(math.pi * e) * 0.06 * h);
      glow = 1 - PourEasing.smoothstep(p);
    } else if (t < tReturnStart) {
      final fillNow = result.sourceBefore!.length - q * srcFill;
      angle = side * tiltAtFill(fillNow);
      anchor = anchorForLip(angle);
    } else {
      final p = PourEasing.easeInOutCubic(
        (t - tReturnStart) / (tReturnEnd - tReturnStart),
      );
      final a = endTilt;
      angle = a * (1 - p);
      // At p == 1 the arc term is sin(pi) ~ 1e-16, which would leave the
      // bottle a hair off its slot and flip anti-aliased edge pixels when
      // the overlay hands over to the resting bottle. Make the end exact.
      anchor = p >= 1
          ? homeAnchor
          : _lerp(anchorForLip(a), homeAnchor, p) +
                Offset(0, -math.sin(math.pi * p) * 0.04 * h);
      if (t > tReturnEnd) {
        final s = (t - tReturnEnd) / (duration - tReturnEnd);
        anchor += Offset(
          0,
          h *
              0.012 *
              math.exp(-5 * s) *
              math.sin(2 * math.pi * 2.2 * s) *
              (1 - s),
        );
      }
    }

    // Slosh of the liquid inside the source (settles to exactly 0).
    var srcEnv = 0.0;
    if (t >= tReturnStart && t < tReturnEnd) {
      srcEnv =
          0.8 *
          math.sin(math.pi * (t - tReturnStart) / (tReturnEnd - tReturnStart));
    } else if (t >= tReturnEnd) {
      final s = (t - tReturnEnd) / (duration - tReturnEnd);
      srcEnv = 0.8 * (1 - s) * (1 - s);
    }
    final srcSlosh = 0.05 * math.sin(2 * math.pi * 3.1 * t) * srcEnv;

    // Destination ripples / slosh while the stream lands, decaying after.
    final hitStart = tApproachEnd + flight;
    final hitEnd = tStreamEnd;
    var dstEnv = 0.0;
    if (t >= hitStart && t <= hitEnd) {
      dstEnv = PourEasing.clamp01((t - hitStart) / (0.15 * timeScale));
    } else if (t > hitEnd) {
      final s = PourEasing.clamp01((t - hitEnd) / (duration - hitEnd));
      dstEnv = (1 - s) * (1 - s);
    }
    final dstSlosh = 0.05 * math.sin(2 * math.pi * 3.4 * t) * dstEnv;

    // Stream.
    StreamFrame? stream;
    if (t >= tApproachEnd && t <= tStreamEnd) {
      final head = PourEasing.clamp01((t - tApproachEnd) / flight);
      final tail = PourEasing.clamp01((t - tPourEnd) / flight);
      if (head > tail && head > 0) {
        final rate = t <= tPourEnd ? PourEasing.flowRate(tauSrc) : 0.5;
        final w = geometry.size.width;
        final p0 = lipTarget;
        final p3 = impact;
        final dy = p3.dy - p0.dy;
        final axis = Offset(math.sin(startTilt), -math.cos(startTilt));
        final reach = math.min(0.30 * dy, 0.65 * (p3.dx - p0.dx).abs());
        stream = StreamFrame(
          p0: p0,
          p1: p0 + axis * reach,
          p2: Offset(p3.dx, p3.dy - 0.45 * dy),
          p3: p3,
          width: w * 0.085 * (0.55 + 0.45 * rate) * (1 - 0.6 * tail),
          head: head,
          tail: tail,
          color: color,
        );
      }
    }

    return PourFrame(
      time: t,
      phase: phaseAt(t),
      sourceAnchor: anchor,
      sourceAngle: angle,
      sourceSpans: sourceSpans,
      sourceSurface: LiquidSurface(angle: angle + srcSlosh),
      destSpans: destSpans,
      destSurface: LiquidSurface(
        angle: dstSlosh,
        rippleAmp: dstEnv,
        rippleAge: math.max(0.0, t - hitStart),
      ),
      stream: stream,
      glow: glow,
      impact: impact,
      particleTime: math.max(0.0, t - hitStart),
      particleStrength: dstEnv,
    );
  }

  /// Splash droplets (board coordinates) for [frame]. Deterministic.
  List<Droplet> splash(PourFrame frame) {
    if (frame.particleStrength <= 0.02 || reduced) return const [];
    final w = geometry.size.width;
    const life = 0.5;
    final out = <Droplet>[];
    for (var i = 0; i < 7; i++) {
      final age = frame.particleTime - i * 0.07;
      if (age < 0) continue;
      final cycle = (age / life).floor();
      final local = age - cycle * life;
      final rng = SeededRandom(StableHash.words([seed, i, cycle]));
      final a = -math.pi / 2 + (rng.nextInt(1000) / 1000 - 0.5) * 1.7;
      final speed = w * (2.2 + rng.nextInt(1000) / 1000 * 2.0);
      final pos =
          frame.impact +
          Offset(
            math.cos(a) * speed * local,
            math.sin(a) * speed * local + 0.5 * w * 14 * local * local,
          );
      if (pos.dy > frame.impact.dy) continue; // fell back into the liquid
      out.add(
        Droplet(
          pos,
          w * (0.014 + 0.012 * rng.nextInt(1000) / 1000),
          (1 - local / life) * frame.particleStrength,
        ),
      );
    }
    return out;
  }

  /// Bubbles rising to the destination surface for [frame]. Deterministic.
  List<Bubble> bubbles(PourFrame frame) {
    if (frame.particleStrength <= 0.02 || reduced) return const [];
    final w = geometry.size.width;
    const life = 0.9;
    final out = <Bubble>[];
    for (var i = 0; i < 8; i++) {
      final age = frame.particleTime - i * 0.11;
      if (age < 0) continue;
      final cycle = (age / life).floor();
      final local = (age - cycle * life) / life;
      final rng = SeededRandom(StableHash.words([seed, 100 + i, cycle]));
      final dx = (rng.nextInt(1000) / 1000 - 0.5) * w * 0.34;
      final depth =
          geometry.unitHeight * (0.4 + 1.3 * rng.nextInt(1000) / 1000);
      out.add(
        Bubble(
          dx + math.sin(local * 6 + i) * w * 0.012,
          depth * (1 - local),
          w * (0.011 + 0.014 * rng.nextInt(1000) / 1000),
          math.sin(math.pi * local) * 0.6 * frame.particleStrength,
        ),
      );
    }
    return out;
  }
}
