import '../models/move_model.dart';
import 'solver_config.dart';

enum SolverStatus {
  /// A verified solution was found ([SolveResult.moves]).
  solved,

  /// The puzzle was already complete; there are no moves to make.
  alreadySolved,

  /// PROVEN unsolvable: either a counting argument or an exhausted search.
  unsolvable,

  /// Search limit hit; solvability is unknown.
  budgetExceeded,

  /// Cancelled by the caller; solvability is unknown.
  cancelled,

  /// The input state violates structural invariants.
  invalidState,
}

final class SolveResult {
  SolveResult({
    required this.status,
    Iterable<MoveModel> moves = const [],
    this.isOptimal = false,
    this.strategyUsed,
    this.nodesGenerated = 0,
    this.nodesExpanded = 0,
    this.elapsed = Duration.zero,
  }) : moves = List.unmodifiable(moves);

  final SolverStatus status;

  /// Moves using the caller's real bottle indices. Empty unless solved.
  final List<MoveModel> moves;

  /// True ONLY when the move count is proven minimal (completed BFS, or
  /// already solved). Never set for best-first results.
  final bool isOptimal;

  final SolverStrategy? strategyUsed;
  final int nodesGenerated;
  final int nodesExpanded;
  final Duration elapsed;

  bool get isSolved =>
      status == SolverStatus.solved || status == SolverStatus.alreadySolved;

  @override
  String toString() =>
      'SolveResult($status, ${moves.length} moves, optimal=$isOptimal, '
      'strategy=$strategyUsed, generated=$nodesGenerated)';
}
