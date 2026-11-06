/// How the bottle narrows from body to neck.
enum ShoulderShape {
  /// Straight chamfer (crystal look).
  angled,

  /// Smooth S-curve.
  ogee,

  /// Round bulb-like shoulder.
  rounded,
}

/// Bottom corner treatment of the body.
enum BaseShape { rounded, chamfered }

/// Pure description of a bottle silhouette. Every number is a FRACTION of
/// the bottle box (widths of box width W, heights of box height H) so one
/// geometry builder can render any style at any size.
///
/// Vertical layout, top to bottom: lip, neck (with ring), shoulder, body,
/// thick base. Liquid occupies the body only, so a full bottle never
/// reaches the neck.
final class BottleSpec {
  const BottleSpec({
    required this.aspect,
    required this.bodyWidth,
    required this.neckWidth,
    required this.lipWidth,
    required this.lipTop,
    required this.lipBottom,
    required this.shoulderTop,
    required this.bodyTop,
    required this.bodyBottom,
    required this.shoulder,
    required this.base,
    required this.cornerRadius,
    required this.wall,
    required this.baseThickness,
    required this.cavityCornerExtra,
    required this.facetOffset,
    required this.ringTop,
    required this.ringBottom,
    required this.ringOverhang,
  });

  /// Box width / height.
  final double aspect;
  final double bodyWidth;
  final double neckWidth;
  final double lipWidth;

  final double lipTop;
  final double lipBottom;

  /// Where the neck ends and the shoulder starts.
  final double shoulderTop;

  /// Where the straight body (and the liquid column) starts.
  final double bodyTop;
  final double bodyBottom;

  final ShoulderShape shoulder;
  final BaseShape base;

  /// Outer bottom corner radius, fraction of W.
  final double cornerRadius;

  /// Glass wall thickness, fraction of W.
  final double wall;

  /// Extra glass under the liquid, fraction of H.
  final double baseThickness;

  /// How much rounder the inside bottom corners are (fraction of W).
  final double cavityCornerExtra;

  /// X position of the facet edges as a fraction of the body half-width.
  final double facetOffset;

  final double ringTop;
  final double ringBottom;

  /// How far the ring sticks out past the neck, fraction of W.
  final double ringOverhang;
}
