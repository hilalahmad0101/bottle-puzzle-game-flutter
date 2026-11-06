import '../models/move_model.dart';
import '../models/puzzle_state.dart';
import '../rules/pour_rules.dart';
import '../solver/solution_verifier.dart';

/// Mathematical validity checks for a level. Returns human-readable
/// problems; an empty list means the level is acceptable.
abstract final class LevelValidator {
  static List<String> problems(
    PuzzleState puzzle,
    List<MoveModel> solution, {
    int minEmptyBottles = 1,
    int? maxBottles,
  }) {
    final out = <String>[];
    if (puzzle.bottles.isEmpty) return ['no bottles'];
    if (!PourRules.isValid(puzzle)) out.add('structurally invalid state');

    final cap = puzzle.bottles.first.capacity;
    if (puzzle.bottles.any((b) => b.capacity != cap)) {
      out.add('bottle capacities differ');
    }
    for (final e in puzzle.colorCounts.entries) {
      if (e.value != cap) {
        out.add('colour ${e.key} appears ${e.value} times, expected $cap');
      }
    }
    final empties = puzzle.bottles.where((b) => b.isEmpty).length;
    if (empties < minEmptyBottles) {
      out.add('only $empties empty bottles, need $minEmptyBottles');
    }
    if (maxBottles != null && puzzle.bottleCount > maxBottles) {
      out.add('${puzzle.bottleCount} bottles exceeds $maxBottles');
    }
    if (PourRules.isCompleted(puzzle)) out.add('already completed');
    if (!SolutionVerifier.verify(puzzle, solution)) {
      out.add('solution does not replay to a win');
    }
    return out;
  }
}
