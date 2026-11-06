import 'bottle_model.dart';
import 'color_unit.dart';

/// Immutable snapshot of every bottle in a level.
final class PuzzleState {
  PuzzleState(Iterable<BottleModel> bottles)
    : bottles = List.unmodifiable(bottles);

  /// Convenience: build from nested colour-id lists (bottom -> top).
  factory PuzzleState.fromIds(
    List<List<int>> bottles, {
    int capacity = kDefaultBottleCapacity,
  }) => PuzzleState([
    for (final b in bottles)
      BottleModel(capacity: capacity, units: b.map(ColorUnit.new)),
  ]);

  final List<BottleModel> bottles;

  int get bottleCount => bottles.length;

  /// Count of units per colour id, across all bottles.
  Map<int, int> get colorCounts {
    final counts = <int, int>{};
    for (final b in bottles) {
      for (final u in b.units) {
        counts[u.id] = (counts[u.id] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// Copy with the bottles at the given indices replaced.
  PuzzleState replacing(Map<int, BottleModel> changes) => PuzzleState([
    for (var i = 0; i < bottles.length; i++) changes[i] ?? bottles[i],
  ]);

  @override
  bool operator ==(Object other) {
    if (other is! PuzzleState || other.bottles.length != bottles.length) {
      return false;
    }
    for (var i = 0; i < bottles.length; i++) {
      if (other.bottles[i] != bottles[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(bottles);

  @override
  String toString() => 'PuzzleState($bottles)';
}
