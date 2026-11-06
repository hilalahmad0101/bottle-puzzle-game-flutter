import 'bottle_model.dart';
import 'color_unit.dart';
import 'move_model.dart';
import 'puzzle_state.dart';

/// Why a pour was rejected.
enum MoveFailure {
  invalidIndex,
  sameBottle,
  sourceEmpty,
  destinationFull,
  colorMismatch,
}

/// Outcome of a move attempt. Contains everything a presentation layer needs
/// to animate it, without the engine knowing anything about animation.
///
/// On failure, [failure] is set, [quantity] is 0, [color] is null and
/// [resultingState] equals [previousState].
final class MoveResult {
  const MoveResult.success({
    required this.move,
    required ColorUnit this.color,
    required this.quantity,
    required this.sourceBefore,
    required this.destinationBefore,
    required this.sourceAfter,
    required this.destinationAfter,
    required this.previousState,
    required this.resultingState,
  }) : failure = null;

  const MoveResult.failure({
    required this.move,
    required MoveFailure this.failure,
    required this.previousState,
  }) : color = null,
       quantity = 0,
       sourceBefore = null,
       destinationBefore = null,
       sourceAfter = null,
       destinationAfter = null,
       resultingState = previousState;

  final MoveModel move;
  final MoveFailure? failure;

  /// Liquid colour moved (null on failure).
  final ColorUnit? color;

  /// Units moved (0 on failure).
  final int quantity;

  final BottleModel? sourceBefore;
  final BottleModel? destinationBefore;
  final BottleModel? sourceAfter;
  final BottleModel? destinationAfter;

  final PuzzleState previousState;
  final PuzzleState resultingState;

  bool get isSuccess => failure == null;

  /// The same pour seen backwards, for animating an undo: the liquid that was
  /// poured is poured back from the destination into the source. Describes
  /// the same change in reverse ([previousState] and [resultingState] swap);
  /// it is a picture of the undo, not a legal forward move. Only for
  /// successful results.
  MoveResult get reversed {
    assert(isSuccess, 'Only a successful pour can be reversed');
    return MoveResult.success(
      move: MoveModel(move.destination, move.source),
      color: color!,
      quantity: quantity,
      sourceBefore: destinationAfter!,
      destinationBefore: sourceAfter!,
      sourceAfter: destinationBefore!,
      destinationAfter: sourceBefore!,
      previousState: resultingState,
      resultingState: previousState,
    );
  }

  int get sourceIndex => move.source;
  int get destinationIndex => move.destination;
}
