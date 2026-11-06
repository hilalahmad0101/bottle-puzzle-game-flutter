import 'dart:ui';

import 'bottle_geometry.dart';
import 'bottle_spec.dart';

enum RingKind { brass, prismatic, royal, verdant, celestial }

/// A cosmetic bottle style: a silhouette ([spec]) plus finish. Every style
/// produces the same [BottleGeometry] interface, so gameplay, effects and
/// animation never depend on which style is active.
final class BottleStyle {
  const BottleStyle({
    required this.id,
    required this.name,
    required this.spec,
    required this.ring,
    required this.glassTint,
    required this.rimLight,
    required this.glow,
    required this.accent,
    required this.facetStrength,
    this.prismatic = false,
  });

  final String id;
  final String name;
  final BottleSpec spec;
  final RingKind ring;

  /// Colour of the glass body.
  final Color glassTint;

  /// Edge highlight colour.
  final Color rimLight;

  /// Soft aura around the bottle.
  final Color glow;

  /// Colour of the illuminated neck ring.
  final Color accent;

  /// 0..1 strength of facet edges and shading.
  final double facetStrength;

  /// Facet edges use a rainbow dispersion instead of plain white.
  final bool prismatic;

  BottleGeometry geometryFor(Size size, int capacity) =>
      FacetedBottleGeometry(spec: spec, size: size, capacity: capacity);
}

/// The built-in styles.
abstract final class BottleStyles {
  /// Rounded hexagonal glass with a warm brass ring.
  static const alchemyClassic = BottleStyle(
    id: 'alchemy_classic',
    name: 'Alchemy Classic',
    ring: RingKind.brass,
    glassTint: Color(0xFF9FD8FF),
    rimLight: Color(0xFFE6F6FF),
    glow: Color(0xFF3FA9FF),
    accent: Color(0xFFFFC25A),
    facetStrength: 0.55,
    spec: BottleSpec(
      aspect: 0.42,
      bodyWidth: 0.80,
      neckWidth: 0.30,
      lipWidth: 0.40,
      lipTop: 0.02,
      lipBottom: 0.065,
      shoulderTop: 0.24,
      bodyTop: 0.35,
      bodyBottom: 0.975,
      shoulder: ShoulderShape.rounded,
      base: BaseShape.rounded,
      cornerRadius: 0.20,
      wall: 0.045,
      baseThickness: 0.05,
      cavityCornerExtra: 0.08,
      facetOffset: 0.38,
      ringTop: 0.135,
      ringBottom: 0.185,
      ringOverhang: 0.055,
    ),
  );

  /// Sharp angular crystal with an iridescent light ring.
  static const crystalPrism = BottleStyle(
    id: 'crystal_prism',
    name: 'Crystal Prism',
    ring: RingKind.prismatic,
    glassTint: Color(0xFFB9C4FF),
    rimLight: Color(0xFFF1EEFF),
    glow: Color(0xFFB04DFF),
    accent: Color(0xFF58F0FF),
    facetStrength: 0.95,
    prismatic: true,
    spec: BottleSpec(
      aspect: 0.42,
      bodyWidth: 0.78,
      neckWidth: 0.24,
      lipWidth: 0.32,
      lipTop: 0.02,
      lipBottom: 0.05,
      shoulderTop: 0.22,
      bodyTop: 0.38,
      bodyBottom: 0.975,
      shoulder: ShoulderShape.angled,
      base: BaseShape.chamfered,
      cornerRadius: 0.16,
      wall: 0.035,
      baseThickness: 0.045,
      cavityCornerExtra: 0.04,
      facetOffset: 0.45,
      ringTop: 0.12,
      ringBottom: 0.155,
      ringOverhang: 0.04,
    ),
  );

  /// Broad, heavy glass with a double gold ring and a violet jewel.
  static const royalGlass = BottleStyle(
    id: 'royal_glass',
    name: 'Royal Glass',
    ring: RingKind.royal,
    glassTint: Color(0xFFC7B6FF),
    rimLight: Color(0xFFFFF1D6),
    glow: Color(0xFF8A5BFF),
    accent: Color(0xFFFFD36E),
    facetStrength: 0.4,
    spec: BottleSpec(
      aspect: 0.44,
      bodyWidth: 0.86,
      neckWidth: 0.34,
      lipWidth: 0.46,
      lipTop: 0.02,
      lipBottom: 0.075,
      shoulderTop: 0.21,
      bodyTop: 0.36,
      bodyBottom: 0.975,
      shoulder: ShoulderShape.ogee,
      base: BaseShape.rounded,
      cornerRadius: 0.26,
      wall: 0.05,
      baseThickness: 0.065,
      cavityCornerExtra: 0.10,
      facetOffset: 0.34,
      ringTop: 0.125,
      ringBottom: 0.2,
      ringOverhang: 0.06,
    ),
  );

  /// A round-bellied apothecary vial in green glass with a leaf-set copper
  /// ring (a reward for a long stay in the Enchanted Garden).
  static const verdantVial = BottleStyle(
    id: 'verdant_vial',
    name: 'Verdant Vial',
    ring: RingKind.verdant,
    glassTint: Color(0xFFA8F0C0),
    rimLight: Color(0xFFEAFFEA),
    glow: Color(0xFF5CFF9A),
    accent: Color(0xFF9CFF7A),
    facetStrength: 0.3,
    spec: BottleSpec(
      aspect: 0.45,
      bodyWidth: 0.90,
      neckWidth: 0.26,
      lipWidth: 0.36,
      lipTop: 0.02,
      lipBottom: 0.06,
      shoulderTop: 0.23,
      bodyTop: 0.40,
      bodyBottom: 0.975,
      shoulder: ShoulderShape.rounded,
      base: BaseShape.rounded,
      cornerRadius: 0.27,
      wall: 0.05,
      baseThickness: 0.06,
      cavityCornerExtra: 0.10,
      facetOffset: 0.30,
      ringTop: 0.125,
      ringBottom: 0.18,
      ringOverhang: 0.05,
    ),
  );

  /// A tall, slim flask with a deep-indigo glass and a silver star ring
  /// (the long-journey reward).
  static const starlitFlask = BottleStyle(
    id: 'starlit_flask',
    name: 'Starlit Flask',
    ring: RingKind.celestial,
    glassTint: Color(0xFF9DB4FF),
    rimLight: Color(0xFFEFF2FF),
    glow: Color(0xFF6B7BFF),
    accent: Color(0xFFFFE08A),
    facetStrength: 0.8,
    spec: BottleSpec(
      aspect: 0.38,
      bodyWidth: 0.70,
      neckWidth: 0.22,
      lipWidth: 0.30,
      lipTop: 0.02,
      lipBottom: 0.05,
      shoulderTop: 0.20,
      bodyTop: 0.33,
      bodyBottom: 0.975,
      shoulder: ShoulderShape.ogee,
      base: BaseShape.chamfered,
      cornerRadius: 0.12,
      wall: 0.032,
      baseThickness: 0.045,
      cavityCornerExtra: 0.03,
      facetOffset: 0.42,
      ringTop: 0.11,
      ringBottom: 0.15,
      ringOverhang: 0.04,
    ),
  );

  static const List<BottleStyle> all = [
    alchemyClassic,
    crystalPrism,
    royalGlass,
    verdantVial,
    starlitFlask,
  ];
}
