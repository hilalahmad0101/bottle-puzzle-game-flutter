import 'dart:ui';

import 'bottle_spec.dart';

/// The logical geometry every bottle style exposes. Rendering, effects and
/// the (later) pour animation only use this interface, never a style's
/// internals. All coordinates are in the bottle's own box: (0,0) top-left,
/// `size` bottom-right.
abstract interface class BottleGeometry {
  Size get size;

  /// Units a full bottle holds.
  int get capacity;

  /// Outer glass silhouette.
  Path get outline;

  /// Inner hollow. Liquid is clipped to this path, so it can never leak
  /// outside the glass.
  Path get cavity;

  /// The straight-sided column the liquid occupies:
  /// bottom = lowest point of the inner floor, top = start of the shoulder.
  Rect get liquidBounds;

  /// Height of ONE unit. Identical for every unit of every bottle.
  double get unitHeight;

  /// Rectangle (within [liquidBounds]) of unit [index], 0 = bottom.
  Rect unitRect(int index);

  /// Where liquid leaves the bottle when poured (centre of the lip).
  Offset get mouth;

  /// Natural pivot for tilting (centre of the body).
  Offset get pivot;

  /// Rectangle of the decorative neck ring.
  Rect get ringRect;

  /// Visible facet edges as line segments.
  List<(Offset, Offset)> get facetEdges;

  /// The hollow sampled as a closed polygon (no repeated end point). Used
  /// for exact liquid-volume maths when a bottle is tilted.
  List<Offset> get cavityPolygon;

  /// Outer rim point on [side] (-1 left, +1 right) where a stream leaves
  /// the bottle when it is tilted toward that side.
  Offset pourLip(double side);

  /// Inner edge of the opening on [side]: liquid pours once its surface
  /// rises above this point.
  Offset mouthRim(double side);
}

/// Parametric implementation shared by all styles: differences between
/// styles are data ([BottleSpec]), not separate geometry code.
final class FacetedBottleGeometry implements BottleGeometry {
  FacetedBottleGeometry({
    required this.spec,
    required this.size,
    required this.capacity,
  }) : assert(capacity > 0) {
    _build();
  }

  final BottleSpec spec;
  @override
  final Size size;
  @override
  final int capacity;

  late final Path _outline;
  late final Path _cavity;
  late final Rect _liquid;
  late final Rect _ring;
  late final Offset _mouth;
  late final Offset _pivot;
  late final List<(Offset, Offset)> _facets;
  late final double _cx, _lipHalf, _yLipTop, _cavNeckHalf, _yMouth;
  late final List<Offset> _polygon = _sample(_cavity, 240);

  @override
  Path get outline => _outline;
  @override
  Path get cavity => _cavity;
  @override
  Rect get liquidBounds => _liquid;
  @override
  double get unitHeight => _liquid.height / capacity;
  @override
  Offset get mouth => _mouth;
  @override
  Offset get pivot => _pivot;
  @override
  Rect get ringRect => _ring;
  @override
  List<(Offset, Offset)> get facetEdges => _facets;
  @override
  List<Offset> get cavityPolygon => _polygon;

  @override
  Offset pourLip(double side) => Offset(_cx + side * _lipHalf, _yLipTop + 1.0);

  @override
  Offset mouthRim(double side) => Offset(_cx + side * _cavNeckHalf, _yMouth);

  static List<Offset> _sample(Path path, int n) {
    final metric = path.computeMetrics().first;
    return [
      for (var i = 0; i < n; i++)
        metric.getTangentForOffset(metric.length * i / n)!.position,
    ];
  }

  @override
  Rect unitRect(int index) {
    assert(index >= 0 && index < capacity);
    final h = unitHeight;
    final bottom = _liquid.bottom - index * h;
    return Rect.fromLTRB(_liquid.left, bottom - h, _liquid.right, bottom);
  }

  void _build() {
    final w = size.width, h = size.height;
    final cx = w / 2;
    final s = spec;

    final bodyHalf = s.bodyWidth * w / 2;
    final neckHalf = s.neckWidth * w / 2;
    final lipHalf = s.lipWidth * w / 2;
    final yLipTop = s.lipTop * h;
    final yLipBottom = s.lipBottom * h;
    final yShoulder = s.shoulderTop * h;
    final yBodyTop = s.bodyTop * h;
    final yBodyBottom = s.bodyBottom * h;
    final radius = s.cornerRadius * w;
    final wall = s.wall * w;

    _outline = _path(
      cx: cx,
      lipHalf: lipHalf,
      neckHalf: neckHalf,
      yLipTop: yLipTop,
      yLipBottom: yLipBottom,
      yShoulder: yShoulder,
      yBodyTop: yBodyTop,
      bodyHalf: bodyHalf,
      yBodyBottom: yBodyBottom,
      radius: radius,
    );

    final cavBodyHalf = bodyHalf - wall;
    final cavNeckHalf = neckHalf - wall * 0.8;
    final yCavBottom = yBodyBottom - s.baseThickness * h;
    _cavity = _path(
      cx: cx,
      lipHalf: cavNeckHalf,
      neckHalf: cavNeckHalf,
      yLipTop: yLipBottom, // open mouth: no flare inside
      yLipBottom: yLipBottom,
      yShoulder: yShoulder,
      yBodyTop: yBodyTop,
      bodyHalf: cavBodyHalf,
      yBodyBottom: yCavBottom,
      radius: radius + s.cavityCornerExtra * w,
    );

    _liquid = Rect.fromLTRB(
      cx - cavBodyHalf,
      yBodyTop,
      cx + cavBodyHalf,
      yCavBottom,
    );
    _ring = Rect.fromLTRB(
      cx - neckHalf - s.ringOverhang * w,
      s.ringTop * h,
      cx + neckHalf + s.ringOverhang * w,
      s.ringBottom * h,
    );
    _cx = cx;
    _lipHalf = lipHalf;
    _yLipTop = yLipTop;
    _cavNeckHalf = cavNeckHalf;
    _yMouth = yLipBottom;
    _mouth = Offset(cx, yLipTop);
    _pivot = Offset(cx, (yBodyTop + yCavBottom) / 2);

    final fx = s.facetOffset * bodyHalf;
    final fn = s.facetOffset * neckHalf;
    final yFacetEnd = yBodyBottom - radius * 0.8;
    _facets = [
      for (final sign in const [-1.0, 1.0]) ...[
        (Offset(cx + sign * fx, yBodyTop), Offset(cx + sign * fx, yFacetEnd)),
        (Offset(cx + sign * fx, yBodyTop), Offset(cx + sign * fn, yShoulder)),
      ],
    ];
  }

  Path _path({
    required double cx,
    required double lipHalf,
    required double neckHalf,
    required double yLipTop,
    required double yLipBottom,
    required double yShoulder,
    required double yBodyTop,
    required double bodyHalf,
    required double yBodyBottom,
    required double radius,
  }) {
    // Right side, top to bottom, as segments in (dx from centre, y).
    final yLipMid = yLipTop + (yLipBottom - yLipTop) * 0.5;
    final shoulderH = yBodyTop - yShoulder;
    final segs = <_Seg>[
      _Seg(Offset(lipHalf, yLipTop), Offset(lipHalf, yLipMid)),
      _Seg(
        Offset(lipHalf, yLipMid),
        Offset(neckHalf, yLipBottom),
        c1: Offset(lipHalf - (lipHalf - neckHalf) * 0.15, yLipBottom),
      ),
      _Seg(Offset(neckHalf, yLipBottom), Offset(neckHalf, yShoulder)),
      switch (spec.shoulder) {
        ShoulderShape.angled => _Seg(
          Offset(neckHalf, yShoulder),
          Offset(bodyHalf, yBodyTop),
        ),
        ShoulderShape.ogee => _Seg(
          Offset(neckHalf, yShoulder),
          Offset(bodyHalf, yBodyTop),
          c1: Offset(neckHalf, yShoulder + shoulderH * 0.5),
          c2: Offset(bodyHalf, yBodyTop - shoulderH * 0.5),
        ),
        ShoulderShape.rounded => _Seg(
          Offset(neckHalf, yShoulder),
          Offset(bodyHalf, yBodyTop),
          c1: Offset(neckHalf, yShoulder + shoulderH * 0.12),
          c2: Offset(bodyHalf, yBodyTop - shoulderH * 0.85),
        ),
      },
      _Seg(Offset(bodyHalf, yBodyTop), Offset(bodyHalf, yBodyBottom - radius)),
      if (spec.base == BaseShape.rounded)
        _Seg(
          Offset(bodyHalf, yBodyBottom - radius),
          Offset(bodyHalf - radius, yBodyBottom),
          c1: Offset(bodyHalf, yBodyBottom),
        )
      else
        _Seg(
          Offset(bodyHalf, yBodyBottom - radius),
          Offset(bodyHalf - radius, yBodyBottom),
        ),
    ];

    final p = Path()
      ..moveTo(cx - lipHalf, yLipTop)
      ..lineTo(cx + lipHalf, yLipTop);
    for (final s in segs) {
      s.addTo(p, cx, 1);
    }
    // Flat bottom edge between the two rounded (or chamfered) corners. Any
    // curve here would only span the short flat part and look spiky on
    // bottles with very round corners.
    p.lineTo(cx - (bodyHalf - radius), yBodyBottom);
    for (final s in segs.reversed) {
      s.addReversedTo(p, cx, -1);
    }
    return p..close();
  }
}

/// One right-side segment; mirrored for the left side.
final class _Seg {
  const _Seg(this.p0, this.p1, {this.c1, this.c2});

  final Offset p0, p1;
  final Offset? c1, c2;

  Offset _m(Offset o, double cx, double sign) => Offset(cx + sign * o.dx, o.dy);

  void addTo(Path p, double cx, double sign) {
    final a = _m(p1, cx, sign);
    if (c1 == null) {
      p.lineTo(a.dx, a.dy);
    } else if (c2 == null) {
      final c = _m(c1!, cx, sign);
      p.quadraticBezierTo(c.dx, c.dy, a.dx, a.dy);
    } else {
      final ca = _m(c1!, cx, sign);
      final cb = _m(c2!, cx, sign);
      p.cubicTo(ca.dx, ca.dy, cb.dx, cb.dy, a.dx, a.dy);
    }
  }

  void addReversedTo(Path p, double cx, double sign) {
    final a = _m(p0, cx, sign);
    if (c1 == null) {
      p.lineTo(a.dx, a.dy);
    } else if (c2 == null) {
      final c = _m(c1!, cx, sign);
      p.quadraticBezierTo(c.dx, c.dy, a.dx, a.dy);
    } else {
      final ca = _m(c2!, cx, sign);
      final cb = _m(c1!, cx, sign);
      p.cubicTo(ca.dx, ca.dy, cb.dx, cb.dy, a.dx, a.dy);
    }
  }
}
