import '../models/move_model.dart';
import '../models/puzzle_state.dart';

/// Handcrafted levels 1-5. Solutions are proven shortest (exhaustive BFS)
/// and are re-verified against the real engine whenever a tutorial is
/// loaded and in the test suite.
final class TutorialLevel {
  const TutorialLevel(this.bottles, this.moves);

  final List<List<int>> bottles;
  final List<List<int>> moves; // [source, destination]

  PuzzleState get puzzle => PuzzleState.fromIds(bottles);
  List<MoveModel> get solution => [
    for (final m in moves) MoveModel(m[0], m[1]),
  ];
}

abstract final class TutorialLevels {
  /// Index 0 = level 1.
  static const List<TutorialLevel> all = [
    // 1. Two colours, one empty bottle: learn "pour onto same colour".
    TutorialLevel(
      [
        [0, 0, 0, 1],
        [1, 1, 1, 0],
        [],
      ],
      [
        [0, 2],
        [1, 0],
        [1, 2],
      ],
    ),
    // 2. Three colours in clean pairs: learn to use the empty bottles.
    TutorialLevel(
      [
        [0, 0, 1, 1],
        [1, 1, 2, 2],
        [2, 2, 0, 0],
        [],
        [],
      ],
      [
        [0, 3],
        [2, 0],
        [1, 2],
        [1, 3],
      ],
    ),
    // 3. Alternating colours: learn to plan the order of pours.
    TutorialLevel(
      [
        [0, 1, 0, 1],
        [1, 0, 1, 0],
        [],
        [],
      ],
      [
        [0, 2],
        [1, 0],
        [1, 2],
        [0, 1],
        [0, 2],
        [1, 0],
        [1, 2],
      ],
    ),
    // 4. Three colours, fully interleaved.
    TutorialLevel(
      [
        [0, 1, 2, 0],
        [1, 2, 0, 1],
        [2, 0, 1, 2],
        [],
        [],
      ],
      [
        [0, 3],
        [2, 0],
        [1, 2],
        [1, 3],
        [0, 1],
        [2, 0],
        [2, 3],
        [1, 2],
        [0, 1],
        [0, 3],
      ],
    ),
    // 5. Four colours, Latin-square arrangement.
    TutorialLevel(
      [
        [0, 1, 2, 3],
        [1, 2, 3, 0],
        [2, 3, 0, 1],
        [3, 0, 1, 2],
        [],
        [],
      ],
      [
        [0, 4],
        [3, 0],
        [2, 3],
        [1, 2],
        [1, 4],
        [0, 1],
        [3, 0],
        [2, 3],
        [2, 4],
        [1, 2],
        [0, 1],
        [3, 0],
        [3, 4],
      ],
    ),
  ];
}
