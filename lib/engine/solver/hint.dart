import '../models/color_unit.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';
import 'puzzle_solver.dart';
import 'solution_verifier.dart';
import 'solver_config.dart';
import 'solver_result.dart';

/// A suggested pour. The UI highlights [sourceIndex] and [destinationIndex].
final class Hint {
  const Hint({
    required this.move,
    required this.color,
    required this.quantity,
    required this.movesRemaining,
  });

  final MoveModel move;
  final ColorUnit color;
  final int quantity;

  /// Length of the known solution from the hinted state. This is the length
  /// of a valid solution, not a claim that it is the shortest.
  final int movesRemaining;

  int get sourceIndex => move.source;
  int get destinationIndex => move.destination;
}

enum HintStatus {
  available,
  alreadySolved,
  unsolvable,
  budgetExceeded,

  /// The request was superseded (the player moved) or cancelled.
  stale,
  invalidState,
}

final class HintResult {
  const HintResult(this.status, {this.hint, this.solve});

  final HintStatus status;
  final Hint? hint;
  final SolveResult? solve;

  static const stale = HintResult(HintStatus.stale);
}

/// Pure hint logic: caches the last solution path so consecutive hints are
/// free while the player follows it, and re-solves from the actual current
/// state when the player has deviated.
class HintPlanner {
  HintPlanner({
    this.solver = const PuzzleSolver(),
    this.config = const SolverConfig(),
  });

  final PuzzleSolver solver;
  final SolverConfig config;

  List<PuzzleState> _states = const [];
  List<MoveModel> _moves = const [];

  /// Synchronous hint (blocks; use `HintController` from UI code).
  HintResult hint(PuzzleState state) {
    final cached = cachedHint(state);
    if (cached != null) return HintResult(HintStatus.available, hint: cached);
    return fromSolve(state, solver.solve(state, config: config));
  }

  /// Hint from the cached path if [state] is exactly on it, else null.
  Hint? cachedHint(PuzzleState state) {
    for (var i = 0; i < _moves.length; i++) {
      if (_states[i] == state) {
        return _makeHint(state, _moves[i], _moves.length - i);
      }
    }
    return null;
  }

  /// Converts a solver result for [state] into a hint, caching its path.
  HintResult fromSolve(PuzzleState state, SolveResult r) {
    switch (r.status) {
      case SolverStatus.alreadySolved:
        _clear();
        return HintResult(HintStatus.alreadySolved, solve: r);
      case SolverStatus.unsolvable:
        _clear();
        return HintResult(HintStatus.unsolvable, solve: r);
      case SolverStatus.budgetExceeded:
        _clear();
        return HintResult(HintStatus.budgetExceeded, solve: r);
      case SolverStatus.cancelled:
        return HintResult.stale;
      case SolverStatus.invalidState:
        _clear();
        return HintResult(HintStatus.invalidState, solve: r);
      case SolverStatus.solved:
        if (!SolutionVerifier.verify(state, r.moves)) {
          _clear();
          return HintResult(HintStatus.invalidState, solve: r);
        }
        _adopt(state, r.moves);
        final h = _makeHint(state, r.moves.first, r.moves.length);
        return h == null
            ? HintResult(HintStatus.invalidState, solve: r)
            : HintResult(HintStatus.available, hint: h, solve: r);
    }
  }

  void _adopt(PuzzleState start, List<MoveModel> moves) {
    final states = <PuzzleState>[start];
    var cur = start;
    for (final m in moves) {
      cur = PourRules.apply(cur, m).resultingState;
      states.add(cur);
    }
    _states = states;
    _moves = moves;
  }

  void _clear() {
    _states = const [];
    _moves = const [];
  }

  /// Final guard: a hint is only ever produced for a move that is legal in
  /// exactly [state].
  Hint? _makeHint(PuzzleState state, MoveModel m, int remaining) {
    if (!PourRules.canPour(state, m.source, m.destination)) return null;
    return Hint(
      move: m,
      color: state.bottles[m.source].topColor!,
      quantity: PourRules.getPourableUnits(state, m.source, m.destination),
      movesRemaining: remaining,
    );
  }
}
