import '../../../engine/models/color_unit.dart';
import '../rendering/liquid_layer.dart';

/// Layer spans of a bottle that is gaining or losing liquid by a possibly
/// fractional amount. At the end of a pour these equal
/// `LiquidLayerSpan.fromUnits(resultingBottle.units)` exactly.
abstract final class LiquidLevels {
  /// [before] with [amount] units removed from the TOP.
  static List<LiquidLayerSpan> drained(List<ColorUnit> before, double amount) {
    final spans = LiquidLayerSpan.fromUnits(before);
    var remaining = amount;
    while (remaining > 1e-9 && spans.isNotEmpty) {
      final last = spans.removeLast();
      final cut = remaining < last.units ? remaining : last.units;
      remaining -= cut;
      final newTo = last.to - cut;
      if (newTo - last.from > 1e-9) {
        spans.add(LiquidLayerSpan(last.colorId, last.from, newTo));
      }
    }
    return spans;
  }

  /// [before] with [amount] units of [color] added on top (merging with an
  /// equal top layer so no seam appears between same-colour liquid).
  static List<LiquidLayerSpan> filled(
    List<ColorUnit> before,
    ColorUnit color,
    double amount,
  ) {
    final spans = LiquidLayerSpan.fromUnits(before);
    if (amount <= 1e-9) return spans;
    if (spans.isNotEmpty && spans.last.colorId == color.id) {
      final last = spans.removeLast();
      spans.add(LiquidLayerSpan(color.id, last.from, last.to + amount));
    } else {
      final n = before.length.toDouble();
      spans.add(LiquidLayerSpan(color.id, n, n + amount));
    }
    return spans;
  }

  /// Total liquid height, in units.
  static double total(List<LiquidLayerSpan> spans) => spans.isEmpty
      ? 0
      : spans.map((s) => s.to).reduce((a, b) => a > b ? a : b);
}
