import '../game_engine.dart';
import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';

/// Replays moves through the real [GameEngine].
abstract final class SolutionVerifier {
  /// True iff every move is legal in order and the final state is completed.
  static bool verify(PuzzleState start, Iterable<MoveModel> moves) {
    if (!PourRules.isValid(start)) return false;
    final engine = GameEngine(start);
    for (final m in moves) {
      if (!engine.applyMove(m).isSuccess) return false;
    }
    return engine.isLevelCompleted();
  }
}
