import 'bottle_model.dart';
import 'color_unit.dart';
import 'move_model.dart';
import 'puzzle_state.dart';

/// Compact, validated JSON forms of puzzles and move lists, for storage.
///
/// Decoding NEVER trusts its input: anything malformed throws a
/// [FormatException] so callers can discard just that record.
abstract final class PuzzleCodec {
  /// Largest colour id and bottle count accepted (sanity bounds against
  /// damaged data, far above anything the game makes).
  static const int maxColorId = 1000000;
  static const int maxBottles = 64;
  static const int maxCapacity = 64;

  /// `[[capacity, id, id, ...], ...]`, units bottom to top.
  static List<List<int>> encode(PuzzleState s) => [
    for (final b in s.bottles) [b.capacity, for (final u in b.units) u.id],
  ];

  static PuzzleState decode(Object? json) {
    if (json is! List || json.isEmpty || json.length > maxBottles) {
      throw const FormatException('bottles must be a non-empty list');
    }
    final bottles = <BottleModel>[];
    for (final raw in json) {
      if (raw is! List || raw.isEmpty || raw.first is! int) {
        throw const FormatException('bad bottle');
      }
      final capacity = raw.first as int;
      if (capacity < 1 || capacity > maxCapacity || raw.length - 1 > capacity) {
        throw const FormatException('bad capacity');
      }
      final units = <ColorUnit>[];
      for (final id in raw.skip(1)) {
        if (id is! int || id < 0 || id > maxColorId) {
          throw const FormatException('bad colour id');
        }
        units.add(ColorUnit(id));
      }
      bottles.add(BottleModel(capacity: capacity, units: units));
    }
    return PuzzleState(bottles);
  }

  /// `[[source, destination], ...]`
  static List<List<int>> encodeMoves(Iterable<MoveModel> moves) => [
    for (final m in moves) [m.source, m.destination],
  ];

  static List<MoveModel> decodeMoves(Object? json, {int maxMoves = 100000}) {
    if (json is! List || json.length > maxMoves) {
      throw const FormatException('moves must be a list');
    }
    final out = <MoveModel>[];
    for (final m in json) {
      if (m is! List || m.length != 2 || m[0] is! int || m[1] is! int) {
        throw const FormatException('bad move');
      }
      final s = m[0] as int, d = m[1] as int;
      if (s < 0 || d < 0 || s >= maxBottles || d >= maxBottles) {
        throw const FormatException('move index out of range');
      }
      out.add(MoveModel(s, d));
    }
    return out;
  }
}
