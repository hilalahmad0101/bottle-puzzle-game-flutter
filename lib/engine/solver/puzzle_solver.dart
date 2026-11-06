import '../models/bottle_model.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';
import 'min_heap.dart';
import 'solution_verifier.dart';
import 'solver_config.dart';
import 'solver_result.dart';
import 'state_key.dart';

/// Synchronous solver. Runs on the calling isolate and may take a long time
/// on hard puzzles, so UI code must use `SolverService` instead.
///
/// Guarantees:
///  * every returned solution is replayed through the real [GameEngine];
///  * `unsolvable` is only returned when proven (counting argument or the
///    whole reachable space exhausted);
///  * `isOptimal` is only set for a completed breadth-first search.
class PuzzleSolver {
  const PuzzleSolver();

  SolveResult solve(
    PuzzleState state, {
    SolverConfig config = const SolverConfig(),
    bool Function()? isCancelled,
  }) {
    final sw = Stopwatch()..start();
    SolveResult done(SolverStatus status) =>
        SolveResult(status: status, elapsed: sw.elapsed);

    if (!PourRules.isValid(state)) return done(SolverStatus.invalidState);
    if (PourRules.isCompleted(state)) {
      return SolveResult(
        status: SolverStatus.alreadySolved,
        isOptimal: true,
        elapsed: sw.elapsed,
      );
    }
    if (_provablyUnsolvable(state)) return done(SolverStatus.unsolvable);

    final keyer = StateKeyer(state);
    final ctx = _Ctx(config, sw, isCancelled);

    switch (config.strategy) {
      case SolverStrategy.bfs:
        return _search(
          state,
          keyer,
          ctx,
          bestFirst: false,
          limit: config.maxNodes,
        );
      case SolverStrategy.bestFirst:
        return _search(
          state,
          keyer,
          ctx,
          bestFirst: true,
          limit: config.maxNodes,
        );
      case SolverStrategy.auto:
        final bfsLimit = config.bfsNodeBudget < config.maxNodes
            ? config.bfsNodeBudget
            : config.maxNodes;
        final first = _search(
          state,
          keyer,
          ctx,
          bestFirst: false,
          limit: bfsLimit,
        );
        if (first.status != SolverStatus.budgetExceeded) return first;
        final remaining = config.maxNodes - first.nodesGenerated;
        if (remaining <= 0) return first;
        final second = _search(
          state,
          keyer,
          ctx,
          bestFirst: true,
          limit: remaining,
        );
        return SolveResult(
          status: second.status,
          moves: second.moves,
          isOptimal: false,
          strategyUsed: second.strategyUsed,
          nodesGenerated: first.nodesGenerated + second.nodesGenerated,
          nodesExpanded: first.nodesExpanded + second.nodesExpanded,
          elapsed: sw.elapsed,
        );
    }
  }

  /// Necessary conditions for the win rule (uniform capacity only): each
  /// colour's units must fill whole bottles, and those bottles must exist.
  static bool _provablyUnsolvable(PuzzleState s) {
    if (s.bottles.isEmpty) return false;
    final cap = s.bottles.first.capacity;
    if (s.bottles.any((b) => b.capacity != cap)) return false;
    var bottlesNeeded = 0;
    for (final count in s.colorCounts.values) {
      if (count % cap != 0) return true;
      bottlesNeeded += count ~/ cap;
    }
    return bottlesNeeded > s.bottleCount;
  }

  /// Heuristic (inadmissible, only guides best-first): colour segments in
  /// every unsolved bottle, plus one for a pure-but-unfilled bottle.
  static int _heuristic(PuzzleState s) {
    var h = 0;
    for (final b in s.bottles) {
      if (b.isEmpty || b.isSolvedBottle) continue;
      var segments = 1;
      for (var i = 1; i < b.length; i++) {
        if (b.units[i] != b.units[i - 1]) segments++;
      }
      h += segments;
    }
    return h;
  }

  /// Pouring a whole single-colour bottle into an identical empty bottle
  /// only permutes bottles; the canonical key would reject it anyway.
  static bool _pointless(BottleModel src, BottleModel dst, int qty) =>
      dst.isEmpty &&
      dst.capacity == src.capacity &&
      qty == src.length &&
      src.topGroupSize == src.length;

  SolveResult _search(
    PuzzleState root,
    StateKeyer keyer,
    _Ctx ctx, {
    required bool bestFirst,
    required int limit,
  }) {
    final strategy = bestFirst ? SolverStrategy.bestFirst : SolverStrategy.bfs;
    final weight = ctx.config.heuristicWeight;

    // Node storage as parallel lists; states are released once expanded.
    final states = <PuzzleState?>[root];
    final parent = <int>[-1];
    final moveCode = <int>[0];
    final depth = <int>[0];
    final visited = <String>{keyer.key(root)};
    final heap = MinHeap();
    if (bestFirst) heap.push(weight * _heuristic(root), 0);
    var head = 0;
    var expanded = 0;

    SolveResult stop(SolverStatus status) => SolveResult(
      status: status,
      strategyUsed: strategy,
      nodesGenerated: states.length,
      nodesExpanded: expanded,
      elapsed: ctx.sw.elapsed,
    );

    while (bestFirst ? !heap.isEmpty : head < states.length) {
      if ((expanded & 63) == 0) {
        if (ctx.isCancelled?.call() ?? false) {
          return stop(SolverStatus.cancelled);
        }
        final max = ctx.config.maxDuration;
        if (max != null && ctx.sw.elapsed > max) {
          return stop(SolverStatus.budgetExceeded);
        }
      }
      final idx = bestFirst ? heap.pop() : head++;
      final cur = states[idx]!;
      states[idx] = null;
      expanded++;

      final n = cur.bottleCount;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          if (!PourRules.canPour(cur, i, j)) continue;
          final qty = PourRules.getPourableUnits(cur, i, j);
          if (_pointless(cur.bottles[i], cur.bottles[j], qty)) continue;
          final child = PourRules.apply(cur, MoveModel(i, j)).resultingState;
          if (!visited.add(keyer.key(child))) continue;

          if (states.length >= limit) return stop(SolverStatus.budgetExceeded);
          final childIdx = states.length;
          states.add(child);
          parent.add(idx);
          moveCode.add((i << 16) | j);
          depth.add(depth[idx] + 1);

          if (PourRules.isCompleted(child)) {
            final moves = <MoveModel>[];
            for (var k = childIdx; parent[k] != -1; k = parent[k]) {
              moves.add(MoveModel(moveCode[k] >> 16, moveCode[k] & 0xFFFF));
            }
            final path = moves.reversed.toList();
            if (!SolutionVerifier.verify(root, path)) {
              throw StateError('Solver produced an invalid solution');
            }
            return SolveResult(
              status: SolverStatus.solved,
              moves: path,
              isOptimal: !bestFirst,
              strategyUsed: strategy,
              nodesGenerated: states.length,
              nodesExpanded: expanded,
              elapsed: ctx.sw.elapsed,
            );
          }
          if (bestFirst) {
            heap.push(depth[childIdx] + weight * _heuristic(child), childIdx);
          }
        }
      }
    }
    // Frontier exhausted without hitting a limit: whole reachable space
    // (modulo bottle permutation) explored, no solution exists.
    return stop(SolverStatus.unsolvable);
  }
}

final class _Ctx {
  _Ctx(this.config, this.sw, this.isCancelled);
  final SolverConfig config;
  final Stopwatch sw;
  final bool Function()? isCancelled;
}
