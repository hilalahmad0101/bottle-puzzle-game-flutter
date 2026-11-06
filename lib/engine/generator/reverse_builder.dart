import '../models/bottle_model.dart';
import '../models/color_unit.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';
import 'seeded_random.dart';

/// A scrambled puzzle together with the forward moves that solve it.
final class ReverseBuild {
  ReverseBuild(this.puzzle, Iterable<MoveModel> solution)
    : solution = List.unmodifiable(solution);

  final PuzzleState puzzle;

  /// Forward moves (in play order) that take [puzzle] to a solved state.
  /// Every move was checked against the real engine rules during
  /// construction.
  final List<MoveModel> solution;
}

/// Builds puzzles by scrambling a SOLVED board with reverse pours, so every
/// result is solvable by construction.
///
/// A reverse step is only *proposed* by this class. It is accepted only if
/// the real engine, applying the corresponding forward move to the proposed
/// previous state, succeeds, moves exactly the proposed amount, and yields
/// exactly the current state. So the recorded solution is legal under the
/// actual rules and reconstructs each earlier state exactly.
///
/// Only "classic" results are returned: every non-empty bottle is full and
/// exactly `empties` bottles are empty. A random reverse walk usually leaves
/// the spare bottles partly filled, so classic boards are found by bounded
/// rejection sampling (cheap: no solver is involved).
abstract final class ReverseBuilder {
  /// Number of independent scrambles tried before giving up (-> null).
  static const int maxScrambles = 80;

  static ReverseBuild? build({
    required int colors,
    required int empties,
    required int capacity,
    required int steps,
    required SeededRandom rng,
  }) {
    for (var s = 0; s < maxScrambles; s++) {
      final r = _scramble(colors, empties, capacity, steps, rng);
      if (r != null) return r;
    }
    return null;
  }

  static ReverseBuild? _scramble(
    int colors,
    int empties,
    int capacity,
    int steps,
    SeededRandom rng,
  ) {
    final total = colors + empties;
    // Random slot for each bottle so empties/colours are not positional.
    final order = List<int>.generate(total, (i) => i);
    rng.shuffle(order);
    final bottles = List<BottleModel>.filled(
      total,
      BottleModel(capacity: capacity),
    );
    for (var c = 0; c < colors; c++) {
      bottles[order[c]] = BottleModel(
        capacity: capacity,
        units: List.filled(capacity, ColorUnit(c)),
      );
    }
    var state = PuzzleState(bottles);

    final forward = <MoveModel>[]; // recorded newest-first
    final limit = steps * 3;
    var tries = 0;
    final maxTries = limit * 30 + 200;
    while (forward.length < limit && tries++ < maxTries) {
      if (forward.length >= steps && _isClassic(state, empties)) {
        return ReverseBuild(state, forward.reversed);
      }
      final next = _reverseStep(state, rng);
      if (next == null) continue;
      forward.add(next.forward);
      state = next.previous;
    }
    if (forward.length >= steps && _isClassic(state, empties)) {
      return ReverseBuild(state, forward.reversed);
    }
    return null;
  }

  /// Every non-empty bottle is full and exactly [empties] bottles are empty.
  static bool _isClassic(PuzzleState s, int empties) {
    var empty = 0;
    for (final b in s.bottles) {
      if (b.isEmpty) {
        empty++;
      } else if (!b.isFull) {
        return false;
      }
    }
    return empty == empties;
  }

  static ({PuzzleState previous, MoveModel forward})? _reverseStep(
    PuzzleState current,
    SeededRandom rng,
  ) {
    final n = current.bottleCount;
    final y = rng.nextInt(n); // forward DESTINATION; we un-pour from it
    final yb = current.bottles[y];
    if (yb.isEmpty) return null;
    final color = yb.topColor!;
    final group = yb.topGroupSize;
    // Valid un-pours: fewer than the whole top group (the rest still has the
    // same colour on top), or the whole bottle if it is a single colour
    // (the destination was empty before).
    final options = <int>[
      for (var k = 1; k < group; k++) k,
      if (group == yb.length) yb.length,
    ];
    if (options.isEmpty) return null;
    final k = rng.pick(options);

    // Forward SOURCE: must have room. Prefer sources whose top differs from
    // [color]; those produce real mixing.
    final sources = <int>[
      for (var x = 0; x < n; x++)
        if (x != y && current.bottles[x].availableSpace >= k) x,
    ];
    if (sources.isEmpty) return null;
    final mixing = [
      for (final x in sources)
        if (!current.bottles[x].isEmpty && current.bottles[x].topColor != color)
          x,
    ];
    final x = (mixing.isNotEmpty && rng.chance(0.8))
        ? rng.pick(mixing)
        : rng.pick(sources);

    final previous = current.replacing({
      x: current.bottles[x].withAdded(color, k),
      y: yb.withTopRemoved(k),
    });

    // Authoritative check with the real engine.
    final forward = MoveModel(x, y);
    final result = PourRules.apply(previous, forward);
    if (!result.isSuccess ||
        result.quantity != k ||
        result.resultingState != current) {
      return null;
    }
    return (previous: previous, forward: forward);
  }
}
