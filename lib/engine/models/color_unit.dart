/// One unit of liquid. Identified by a stable integer id; the engine knows
/// nothing about how a colour is displayed.
final class ColorUnit {
  const ColorUnit(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is ColorUnit && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'C$id';
}
