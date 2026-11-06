import 'color_unit.dart';

/// Default capacity of a normal bottle, in colour units.
const int kDefaultBottleCapacity = 4;

/// Immutable bottle. [units] are ordered bottom -> top.
final class BottleModel {
  BottleModel({
    this.capacity = kDefaultBottleCapacity,
    Iterable<ColorUnit> units = const [],
  }) : units = List.unmodifiable(units);

  final int capacity;
  final List<ColorUnit> units;

  int get length => units.length;
  bool get isEmpty => units.isEmpty;
  bool get isFull => units.length >= capacity;
  int get availableSpace => capacity - units.length;

  /// Top-most unit, or null when empty.
  ColorUnit? get topColor => units.isEmpty ? null : units.last;

  /// Number of contiguous same-colour units at the top.
  int get topGroupSize {
    if (units.isEmpty) return 0;
    final top = units.last;
    var n = 0;
    for (var i = units.length - 1; i >= 0 && units[i] == top; i--) {
      n++;
    }
    return n;
  }

  /// True when full and every unit is the same colour.
  bool get isSolvedBottle => isFull && units.every((u) => u == units.first);

  /// Structural validity: positive capacity and not over-filled.
  bool get isValid => capacity > 0 && units.length <= capacity;

  /// Copy with [count] units removed from the top.
  BottleModel withTopRemoved(int count) => BottleModel(
    capacity: capacity,
    units: units.sublist(0, units.length - count),
  );

  /// Copy with [count] units of [color] added on top.
  BottleModel withAdded(ColorUnit color, int count) => BottleModel(
    capacity: capacity,
    units: [...units, for (var i = 0; i < count; i++) color],
  );

  @override
  bool operator ==(Object other) =>
      other is BottleModel &&
      other.capacity == capacity &&
      _listEq(other.units, units);

  @override
  int get hashCode => Object.hash(capacity, Object.hashAll(units));

  @override
  String toString() => 'Bottle($capacity: $units)';
}

bool _listEq(List<ColorUnit> a, List<ColorUnit> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
