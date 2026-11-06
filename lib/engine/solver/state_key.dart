import '../models/bottle_model.dart';
import '../models/puzzle_state.dart';

/// Produces canonical keys for visited-state detection.
///
/// Two states get the same key iff one is a permutation of the other's
/// bottles (each bottle = capacity + contents). That is safe because
/// solvability and shortest-solution length do not depend on bottle order.
/// Colour ids are NOT relabelled, so the key never merges states that could
/// differ.
///
/// The key is an exact string, not a lossy hash, so there are no collisions.
final class StateKeyer {
  StateKeyer(PuzzleState root) : _compact = _fitsCompact(root);

  final bool _compact;

  static const int _maxCode = 0xFFF0;
  static const String _sep = '￿';

  static bool _fitsCompact(PuzzleState s) {
    for (final b in s.bottles) {
      if (b.capacity > _maxCode) return false;
      for (final u in b.units) {
        if (u.id < 0 || u.id > _maxCode - 1) return false;
      }
    }
    return true;
  }

  String key(PuzzleState s) {
    final parts = <String>[for (final b in s.bottles) _bottleKey(b)]..sort();
    return parts.join(_compact ? _sep : '|');
  }

  String _bottleKey(BottleModel b) {
    if (_compact) {
      final codes = List<int>.filled(b.length + 1, 0);
      codes[0] = b.capacity;
      for (var i = 0; i < b.length; i++) {
        codes[i + 1] = b.units[i].id + 1;
      }
      return String.fromCharCodes(codes);
    }
    return '${b.capacity}:${b.units.map((u) => u.id).join(',')}';
  }
}
