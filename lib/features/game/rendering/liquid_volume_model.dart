import 'dart:math' as math;
import 'dart:ui';

import 'bottle_geometry.dart';

/// Exact liquid-volume maths inside a bottle's hollow, for any tilt.
///
/// Heights are measured along the world "up" direction expressed in the
/// bottle's own coordinates: for a bottle rotated clockwise by `angle`,
/// up = (-sin angle, -cos angle). A liquid at "height h" is the part of the
/// hollow with `up . p <= h`; its volume is that polygon's AREA (a 2D
/// cross-section, which is also how the upright renderer measures units).
/// Solving area -> h for a tilted bottle makes the surface stay horizontal in
/// the world while conserving volume, and tells us how far we must tilt
/// before liquid reaches the lip.
final class LiquidVolumeModel {
  LiquidVolumeModel._(this.geometry) : poly = geometry.cavityPolygon;

  static final Expando<LiquidVolumeModel> _cache = Expando('LiquidVolumeModel');

  /// One model per geometry instance (memoises volumes and tilt angles).
  static LiquidVolumeModel of(BottleGeometry g) =>
      _cache[g] ??= LiquidVolumeModel._(g);

  final BottleGeometry geometry;
  final List<Offset> poly;
  final Map<int, double> _volumeMemo = {};
  final Map<int, double> _tiltMemo = {};

  /// World "up" in bottle coordinates for a bottle rotated by [angle].
  static Offset up(double angle) => Offset(-math.sin(angle), -math.cos(angle));

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

  /// Keep the part with `u . p <= h`.
  List<Offset> clipBelow(List<Offset> pts, Offset u, double h) =>
      _clip(pts, u, h, true);

  /// Keep the part with `u . p >= h`.
  List<Offset> clipAbove(List<Offset> pts, Offset u, double h) =>
      _clip(pts, u, h, false);

  static List<Offset> _clip(List<Offset> pts, Offset u, double h, bool below) {
    final out = <Offset>[];
    final n = pts.length;
    final sign = below ? 1.0 : -1.0;
    for (var i = 0; i < n; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % n];
      final da = (_dot(u, a) - h) * sign;
      final db = (_dot(u, b) - h) * sign;
      if (da <= 0) out.add(a);
      if ((da < 0 && db > 0) || (da > 0 && db < 0)) {
        final t = da / (da - db);
        out.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
      }
    }
    return out;
  }

  static double area(List<Offset> p) {
    var s = 0.0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      s += a.dx * b.dy - b.dx * a.dy;
    }
    return s.abs() / 2;
  }

  late final double totalArea = area(poly);

  double areaBelow(double angle, double h) =>
      area(clipBelow(poly, up(angle), h));

  (double, double) heightRange(double angle) {
    final u = up(angle);
    var lo = double.infinity, hi = -double.infinity;
    for (final p in poly) {
      final d = _dot(u, p);
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    return (lo, hi);
  }

  /// Volume (area) of [fill] units standing upright.
  double fillVolume(double fill) =>
      _volumeMemo.putIfAbsent((fill * 1000).round(), () {
        final y = geometry.liquidBounds.bottom - fill * geometry.unitHeight;
        return areaBelow(0, -y);
      });

  /// Height at which a tilted bottle holds [volume].
  double heightFor(double angle, double volume) {
    final (lo0, hi0) = heightRange(angle);
    if (volume <= 0) return lo0 - 1;
    if (volume >= totalArea) return hi0 + 1;
    var lo = lo0, hi = hi0;
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      if (areaBelow(angle, mid) < volume) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return (lo + hi) / 2;
  }

  double heightForFill(double angle, double fill) =>
      heightFor(angle, fillVolume(fill));

  /// The two ends of the liquid surface at height [h] (null if it does not
  /// cross the hollow), ordered along the surface direction.
  (Offset, Offset)? chord(double angle, double h) {
    final u = up(angle);
    final pts = [
      for (final p in clipBelow(poly, u, h))
        if ((_dot(u, p) - h).abs() < 1e-3) p,
    ];
    if (pts.length < 2) return null;
    final t = Offset(math.cos(angle), -math.sin(angle));
    pts.sort((a, b) => _dot(t, a).compareTo(_dot(t, b)));
    return (pts.first, pts.last);
  }

  /// Fill levels (in units) a pour can pass through: every quarter unit up to
  /// [capacity]. `PourPlan` samples the tilt curve exactly at these.
  static Iterable<double> warmUpFills(int capacity) => [
    for (var i = capacity * 4; i >= 0; i--) i / 4,
  ];

  /// Whether [requiredTilt] for [fill] is already computed.
  bool isTiltWarm(double fill) => _tiltMemo.containsKey((fill * 100).round());

  /// Smallest clockwise tilt (radians, >= 0) at which [fill] units reach the
  /// opening, so that liquid starts to pour over the right-hand rim. By
  /// symmetry the same magnitude applies tilting left. Returns [maxAngle]
  /// when even that is not enough (e.g. an empty bottle).
  double requiredTilt(double fill, {double maxAngle = 2.1}) => _tiltMemo
      .putIfAbsent((fill * 100).round(), () => _solveTilt(fill, maxAngle));

  double _solveTilt(double fill, double maxAngle) {
    final rim = geometry.mouthRim(1);
    final volume = fillVolume(fill);
    double gap(double a) => heightFor(a, volume) - _dot(up(a), rim);
    if (gap(0) >= 0) return 0;
    if (gap(maxAngle) < 0) return maxAngle;
    var lo = 0.0, hi = maxAngle;
    for (var i = 0; i < 18; i++) {
      final mid = (lo + hi) / 2;
      if (gap(mid) < 0) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }
}
