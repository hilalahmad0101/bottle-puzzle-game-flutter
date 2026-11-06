import '../models/move_model.dart';
import '../models/move_result.dart';
import '../models/puzzle_state.dart';

/// Pure, stateless puzzle rules. [GameEngine] is a thin session wrapper
/// around these.
abstract final class PourRules {
  static bool _inRange(PuzzleState s, int i) => i >= 0 && i < s.bottleCount;

  /// Returns null when pouring is legal, otherwise the reason it is not.
  static MoveFailure? validate(PuzzleState s, int source, int destination) {
    if (!_inRange(s, source) || !_inRange(s, destination)) {
      return MoveFailure.invalidIndex;
    }
    if (source == destination) return MoveFailure.sameBottle;
    final src = s.bottles[source];
    final dst = s.bottles[destination];
    if (src.isEmpty) return MoveFailure.sourceEmpty;
    if (dst.isFull) return MoveFailure.destinationFull;
    if (!dst.isEmpty && dst.topColor != src.topColor) {
      return MoveFailure.colorMismatch;
    }
    return null;
  }

  static bool canPour(PuzzleState s, int source, int destination) =>
      validate(s, source, destination) == null;

  /// Units that a pour from [source] to [destination] would move:
  /// min(top group size, free space). 0 if the pour is illegal.
  static int getPourableUnits(PuzzleState s, int source, int destination) {
    if (!canPour(s, source, destination)) return 0;
    final group = s.bottles[source].topGroupSize;
    final space = s.bottles[destination].availableSpace;
    return group < space ? group : space;
  }

  /// Free space in a bottle; 0 for an invalid index.
  static int getAvailableSpace(PuzzleState s, int index) =>
      _inRange(s, index) ? s.bottles[index].availableSpace : 0;

  static MoveResult apply(PuzzleState s, MoveModel move) {
    final failure = validate(s, move.source, move.destination);
    if (failure != null) {
      return MoveResult.failure(move: move, failure: failure, previousState: s);
    }
    final src = s.bottles[move.source];
    final dst = s.bottles[move.destination];
    final qty = getPourableUnits(s, move.source, move.destination);
    final color = src.topColor!;
    final newSrc = src.withTopRemoved(qty);
    final newDst = dst.withAdded(color, qty);
    return MoveResult.success(
      move: move,
      color: color,
      quantity: qty,
      sourceBefore: src,
      destinationBefore: dst,
      sourceAfter: newSrc,
      destinationAfter: newDst,
      previousState: s,
      resultingState: s.replacing({
        move.source: newSrc,
        move.destination: newDst,
      }),
    );
  }

  /// All legal moves, in (source, destination) index order.
  static List<MoveModel> legalMoves(PuzzleState s) => [
    for (var i = 0; i < s.bottleCount; i++)
      for (var j = 0; j < s.bottleCount; j++)
        if (canPour(s, i, j)) MoveModel(i, j),
  ];

  /// Every non-empty bottle is full and single-coloured.
  static bool isCompleted(PuzzleState s) =>
      s.bottles.every((b) => b.isEmpty || b.isSolvedBottle);

  /// Structural invariants: every bottle valid (capacity > 0, not overfilled).
  static bool isValid(PuzzleState s) => s.bottles.every((b) => b.isValid);
}
