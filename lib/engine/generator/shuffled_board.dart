import '../models/bottle_model.dart';
import '../models/color_unit.dart';
import '../models/puzzle_state.dart';
import 'seeded_random.dart';

/// Builds a classic random board (every colour exactly `capacity` times,
/// all colour bottles full, `empties` empty bottles in random slots).
///
/// This board is NOT known to be solvable; the generator only accepts it
/// after the solver has found and the engine has replayed a solution.
abstract final class ShuffledBoard {
  static PuzzleState build({
    required int colors,
    required int empties,
    required int capacity,
    required SeededRandom rng,
  }) {
    final units = [
      for (var c = 0; c < colors; c++)
        for (var k = 0; k < capacity; k++) c,
    ];
    rng.shuffle(units);
    final total = colors + empties;
    final order = List<int>.generate(total, (i) => i);
    rng.shuffle(order);
    final bottles = List<BottleModel>.filled(
      total,
      BottleModel(capacity: capacity),
    );
    for (var b = 0; b < colors; b++) {
      bottles[order[b]] = BottleModel(
        capacity: capacity,
        units: units
            .sublist(b * capacity, (b + 1) * capacity)
            .map(ColorUnit.new),
      );
    }
    return PuzzleState(bottles);
  }
}
