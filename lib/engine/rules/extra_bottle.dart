import '../models/bottle_model.dart';
import '../models/puzzle_state.dart';
import 'pour_rules.dart';

/// The optional "extra bottle" booster, kept apart from the standard rules.
///
/// It is nothing more than ONE additional EMPTY bottle appended after the
/// level's own bottles. That is deliberately all it is:
///  * **validity** – the result is an ordinary [PuzzleState]: same colour
///    totals, same capacity, one more (empty) bottle. [PourRules.isValid]
///    holds for it exactly as for any level;
///  * **winning** – the win rule ("every non-empty bottle is full and one
///    colour") already ignores empty bottles, so a boosted level is won by the
///    very same test and the extra bottle may end up empty or used;
///  * **solver** – the solver only sees a [PuzzleState]; a boosted board is
///    solved like any other. Because the new bottle only ADDS options, a level
///    that was solvable stays solvable, with a solution no longer than before;
///  * **indices** – the new bottle is last, so every existing bottle keeps its
///    index and a recorded move list stays meaningful.
///
/// Nothing here is called unless the player has switched the booster on and
/// used it, so standard play never touches this file.
abstract final class ExtraBottle {
  /// A board never grows past this many bottles with the booster (layouts and
  /// the save codec have to stay sane).
  static const int maxBottlesWithBooster = 24;

  /// Whether [state] can take an extra bottle.
  static bool canAdd(PuzzleState state) =>
      state.bottles.isNotEmpty &&
      state.bottleCount < maxBottlesWithBooster &&
      PourRules.isValid(state);

  /// [state] plus one empty bottle at the end (same capacity as the others).
  /// Throws [StateError] when [canAdd] is false.
  static PuzzleState add(PuzzleState state) {
    if (!canAdd(state)) {
      throw StateError('An extra bottle cannot be added to this puzzle.');
    }
    final capacity = state.bottles.map((b) => b.capacity).reduce(_max);
    return PuzzleState([...state.bottles, BottleModel(capacity: capacity)]);
  }

  static int _max(int a, int b) => a > b ? a : b;
}
