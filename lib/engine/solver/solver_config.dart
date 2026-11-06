/// Search strategy used by [PuzzleSolver].
enum SolverStrategy {
  /// Breadth-first search first (optimal when it finishes within its
  /// budget), then fall back to weighted best-first search.
  auto,

  /// Breadth-first search only. A solution it returns is proven shortest.
  bfs,

  /// Weighted best-first search only. Fast on large puzzles; solutions are
  /// valid but NOT guaranteed shortest.
  bestFirst,
}

/// Limits and tuning for a solve. Node limits are deterministic; the
/// optional time limit is not (it depends on the machine).
final class SolverConfig {
  const SolverConfig({
    this.strategy = SolverStrategy.auto,
    this.maxNodes = 300000,
    this.maxDuration,
    this.bfsNodeBudget = 40000,
    this.heuristicWeight = 3.0,
  }) : assert(maxNodes > 0),
       assert(bfsNodeBudget > 0),
       assert(heuristicWeight >= 0);

  final SolverStrategy strategy;

  /// Maximum number of distinct states the search may generate (this bounds
  /// memory). Exceeding it yields `SolverStatus.budgetExceeded`.
  final int maxNodes;

  /// Optional wall-clock limit.
  final Duration? maxDuration;

  /// In [SolverStrategy.auto]: nodes BFS may use before switching to
  /// best-first search.
  final int bfsNodeBudget;

  /// Weight on the (inadmissible) heuristic in best-first search:
  /// f = g + weight * h. Higher is greedier and faster, with longer paths.
  final double heuristicWeight;
}
