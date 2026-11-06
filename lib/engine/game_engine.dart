import 'models/game_status.dart';
import 'models/move_model.dart';
import 'models/move_result.dart';
import 'models/puzzle_state.dart';
import 'rules/pour_rules.dart';

/// A single play session of one level: current state plus undo history.
///
/// Pure Dart; no Flutter, no animation. Presentation layers consume the
/// [MoveResult] returned by [applyMove].
class GameEngine {
  GameEngine(this.initialState)
    : assert(PourRules.isValid(initialState), 'Invalid initial state'),
      _current = initialState;

  final PuzzleState initialState;
  PuzzleState _current;
  final List<MoveResult> _history = [];

  PuzzleState get state => _current;

  /// Successful moves made so far (oldest first), unmodifiable.
  List<MoveResult> get history => List.unmodifiable(_history);
  int get moveCount => _history.length;
  bool get canUndo => _history.isNotEmpty;

  GameStatus get status {
    if (isLevelCompleted()) return GameStatus.completed;
    if (getLegalMoves().isEmpty) return GameStatus.stuck;
    return GameStatus.inProgress;
  }

  bool canPour(int source, int destination) =>
      PourRules.canPour(_current, source, destination);

  int getPourableUnits(int source, int destination) =>
      PourRules.getPourableUnits(_current, source, destination);

  int getAvailableSpace(int bottleIndex) =>
      PourRules.getAvailableSpace(_current, bottleIndex);

  List<MoveModel> getLegalMoves() => PourRules.legalMoves(_current);

  bool isLevelCompleted() => PourRules.isCompleted(_current);

  /// Checks structural invariants of the current state.
  bool isStateValid() => PourRules.isValid(_current);

  /// Attempts a pour. Failed moves leave the engine unchanged and are not
  /// added to the undo history.
  MoveResult applyMove(MoveModel move) {
    final result = PourRules.apply(_current, move);
    if (result.isSuccess) {
      _current = result.resultingState;
      _history.add(result);
    }
    return result;
  }

  /// Reverts the last successful move. Returns it (with its original
  /// previous/resulting states, so a UI can animate the reverse), or null
  /// when there is nothing to undo.
  MoveResult? undoMove() {
    if (_history.isEmpty) return null;
    final last = _history.removeLast();
    _current = last.previousState;
    return last;
  }

  /// Restores the initial state and clears history.
  void resetLevel() {
    _current = initialState;
    _history.clear();
  }
}
