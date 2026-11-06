import 'package:flutter/foundation.dart';

import '../../../engine/models/color_unit.dart';

/// A run of one colour, in UNIT coordinates measured from the bottle floor
/// (0 = bottom). Spans may be fractional, so the later pour animation can
/// grow or shrink a layer smoothly without the renderer knowing about it.
@immutable
final class LiquidLayerSpan {
  const LiquidLayerSpan(this.colorId, this.from, this.to);

  final int colorId;
  final double from;
  final double to;

  double get units => to - from;

  /// Merges contiguous equal colours of an engine bottle (bottom -> top)
  /// into spans.
  static List<LiquidLayerSpan> fromUnits(Iterable<ColorUnit> units) {
    final spans = <LiquidLayerSpan>[];
    var i = 0;
    for (final u in units) {
      if (spans.isNotEmpty && spans.last.colorId == u.id) {
        final last = spans.removeLast();
        spans.add(LiquidLayerSpan(u.id, last.from, last.to + 1));
      } else {
        spans.add(LiquidLayerSpan(u.id, i.toDouble(), i + 1.0));
      }
      i++;
    }
    return spans;
  }

  @override
  bool operator ==(Object other) =>
      other is LiquidLayerSpan &&
      other.colorId == colorId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(colorId, from, to);

  @override
  String toString() => 'Span(c$colorId $from..$to)';
}
