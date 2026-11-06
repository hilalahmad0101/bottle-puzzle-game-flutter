/// A requested pour from bottle index [source] to bottle index [destination].
final class MoveModel {
  const MoveModel(this.source, this.destination);

  final int source;
  final int destination;

  @override
  bool operator ==(Object other) =>
      other is MoveModel &&
      other.source == source &&
      other.destination == destination;

  @override
  int get hashCode => Object.hash(source, destination);

  @override
  String toString() => 'Move($source -> $destination)';
}
