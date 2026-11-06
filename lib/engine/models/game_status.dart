enum GameStatus {
  /// Legal moves remain and the puzzle is not solved.
  inProgress,

  /// Every non-empty bottle is full of a single colour.
  completed,

  /// Not solved, and no legal move exists.
  stuck,
}
