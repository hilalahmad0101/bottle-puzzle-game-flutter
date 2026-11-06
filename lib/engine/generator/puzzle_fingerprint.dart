import '../models/puzzle_state.dart';
import '../solver/state_key.dart';
import 'seeded_random.dart';

/// Compact identity of a puzzle layout, ignoring bottle order.
///
/// 64 bits (two independent 32-bit FNV-1a runs) of the exact canonical key.
/// It is good for "have I seen this recently?" checks, NOT a proof of
/// uniqueness: collisions are possible in principle, and distinct level
/// numbers may legitimately share a layout, especially at low colour counts.
abstract final class PuzzleFingerprint {
  static String of(PuzzleState state) {
    final key = StateKeyer(state).key(state);
    final units = key.codeUnits;
    final a = StableHash.words(units);
    final b = StableHash.words(units, basis: 0x9E3779B1);
    return a.toRadixString(16).padLeft(8, '0') +
        b.toRadixString(16).padLeft(8, '0');
  }
}
