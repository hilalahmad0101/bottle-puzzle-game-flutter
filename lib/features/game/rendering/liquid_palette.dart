import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../engine/generator/seeded_random.dart';

enum LiquidSymbol {
  circle,
  triangle,
  square,
  diamond,
  star,
  cross,
  hexagon,
  crescent,
  drop,
  heart,
  ring,
  bolt,
}

enum LiquidPattern {
  dots,
  diagonal,
  horizontal,
  vertical,
  checks,
  waves,
  zigzag,
  crosshatch,
  bigDots,
  rings,
  chevrons,
  dashes,
}

/// Colour-blind assistance for liquids.
enum ColorAssist {
  off,
  symbols,
  patterns,
  both;

  bool get showSymbols => this == symbols || this == both;
  bool get showPatterns => this == patterns || this == both;
}

/// One liquid colour. Gameplay refers to colours by stable integer id; this
/// is the only place an id becomes pixels.
final class LiquidColor {
  const LiquidColor(this.name, this.base, this.symbol, this.pattern);

  final String name;
  final Color base;
  final LiquidSymbol symbol;
  final LiquidPattern pattern;

  Color get light => Color.lerp(base, const Color(0xFFFFFFFF), 0.38)!;
  Color get dark => Color.lerp(base, const Color(0xFF000000), 0.45)!;
}

/// CIE L*a*b* distance helpers used to keep active colours apart.
abstract final class ColorMath {
  static (double, double, double) lab(Color c) {
    double lin(double v) => v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    final r = lin(c.r), g = lin(c.g), b = lin(c.b);
    final x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047;
    final y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b;
    final z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883;
    double f(double t) =>
        t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + 16 / 116;
    final fx = f(x), fy = f(y), fz = f(z);
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  /// CIE76 colour difference (about 2.3 is a just-noticeable difference).
  static double deltaE(Color a, Color b) {
    final (l1, a1, b1) = lab(a);
    final (l2, a2, b2) = lab(b);
    return math.sqrt(
      math.pow(l1 - l2, 2) + math.pow(a1 - a2, 2) + math.pow(b1 - b2, 2),
    );
  }
}

/// Maps colour ids to [LiquidColor]s.
final class LiquidPalette {
  const LiquidPalette._(this._byId);

  /// The twelve base colours, in catalogue order.
  static const List<LiquidColor> all = [
    LiquidColor(
      'Cyan',
      Color(0xFF00D4FF),
      LiquidSymbol.circle,
      LiquidPattern.dots,
    ),
    LiquidColor(
      'Magenta',
      Color(0xFFFF2BC8),
      LiquidSymbol.triangle,
      LiquidPattern.diagonal,
    ),
    LiquidColor(
      'Emerald',
      Color(0xFF00A86B),
      LiquidSymbol.square,
      LiquidPattern.horizontal,
    ),
    LiquidColor(
      'Amber',
      Color(0xFFFFB300),
      LiquidSymbol.diamond,
      LiquidPattern.vertical,
    ),
    LiquidColor(
      'Violet',
      Color(0xFF8E5BFF),
      LiquidSymbol.star,
      LiquidPattern.checks,
    ),
    LiquidColor(
      'Coral',
      Color(0xFFFF6B5E),
      LiquidSymbol.cross,
      LiquidPattern.waves,
    ),
    LiquidColor(
      'Royal Blue',
      Color(0xFF2D5BFF),
      LiquidSymbol.hexagon,
      LiquidPattern.zigzag,
    ),
    LiquidColor(
      'Lime',
      Color(0xFFB8F000),
      LiquidSymbol.crescent,
      LiquidPattern.crosshatch,
    ),
    LiquidColor(
      'Rose',
      Color(0xFFFF9FC2),
      LiquidSymbol.drop,
      LiquidPattern.bigDots,
    ),
    LiquidColor(
      'Turquoise',
      Color(0xFF12C9B0),
      LiquidSymbol.heart,
      LiquidPattern.rings,
    ),
    LiquidColor(
      'Gold',
      Color(0xFFE0C23A),
      LiquidSymbol.ring,
      LiquidPattern.chevrons,
    ),
    LiquidColor(
      'Deep Orange',
      Color(0xFFFF5A1F),
      LiquidSymbol.bolt,
      LiquidPattern.dashes,
    ),
  ];

  /// Indices into [all], ordered so that ANY prefix is as mutually distinct
  /// as possible (greedy farthest-point ordering in L*a*b*). A level with
  /// N colours uses the first N, so similar colours (cyan/turquoise,
  /// amber/gold/orange, rose/magenta/coral) only meet when unavoidable.
  static final List<int> distinctOrder = _computeOrder();

  static List<int> _computeOrder() {
    final chosen = <int>[0];
    while (chosen.length < all.length) {
      var best = -1;
      var bestMin = -1.0;
      for (var i = 0; i < all.length; i++) {
        if (chosen.contains(i)) continue;
        var minD = double.infinity;
        for (final j in chosen) {
          final d = ColorMath.deltaE(all[i].base, all[j].base);
          if (d < minD) minD = d;
        }
        if (minD > bestMin) {
          bestMin = minD;
          best = i;
        }
      }
      chosen.add(best);
    }
    return List.unmodifiable(chosen);
  }

  final Map<int, LiquidColor> _byId;

  /// Palette for the colour ids of one level. With the default [seed] the
  /// i-th smallest id gets the i-th most distinctive colour; a non-zero
  /// seed permutes which id gets which colour of the same chosen set, so
  /// levels look different without becoming less distinguishable.
  factory LiquidPalette.forColorIds(Iterable<int> ids, {int seed = 0}) {
    final sorted = ids.toSet().toList()..sort();
    final n = math.min(sorted.length, all.length);
    final picks = [for (var i = 0; i < n; i++) distinctOrder[i]];
    if (seed != 0) SeededRandom(seed).shuffle(picks);
    return LiquidPalette._({
      for (var i = 0; i < sorted.length; i++)
        sorted[i]: all[picks[i % picks.length]],
    });
  }

  /// Every base colour, id = catalogue index (for previews).
  static final LiquidPalette catalogue = LiquidPalette._({
    for (var i = 0; i < all.length; i++) i: all[i],
  });

  /// Colour for [id]. Unknown ids fall back to the catalogue, never throw.
  LiquidColor colorFor(int id) =>
      _byId[id] ?? all[distinctOrder[id.abs() % all.length]];

  Iterable<MapEntry<int, LiquidColor>> get entries => _byId.entries;

  @override
  bool operator ==(Object other) =>
      other is LiquidPalette && mapEquals(other._byId, _byId);

  @override
  int get hashCode => Object.hashAll(
    _byId.entries.map((e) => Object.hash(e.key, e.value.name)),
  );
}
