/// Thresholds (maximum moves) for each star level of one puzzle.
final class StarThresholds {
  const StarThresholds({required this.three, required this.two});

  /// Finishing in at most this many moves earns three stars.
  final int three;

  /// ... two stars.
  final int two;
}

/// The documented scoring rules (also shown to the player).
///
///  * PAR is the length of the best known solution of the level (proven
///    shortest for tutorials and small boards, otherwise the best the
///    solver found, so it is an upper bound on the true optimum).
///  * 3 stars: moves <= ceil(par x 1.25)  (never less than par)
///  * 2 stars: moves <= ceil(par x 1.75)
///  * 1 star: the level is solved.
///  * MOVES are the pours on the board when the level is solved: an undone
///    pour is not counted. Hints, restarts and pauses never change the
///    rating.
abstract final class StarRating {
  static const double threeStarFactor = 1.25;
  static const double twoStarFactor = 1.75;

  static StarThresholds thresholds(int par) {
    assert(par >= 1, 'par must be at least 1');
    final p = par < 1 ? 1 : par;
    final three = _ceil(p * threeStarFactor);
    final two = _ceil(p * twoStarFactor);
    return StarThresholds(
      three: three < p ? p : three,
      two: two < three ? three : two,
    );
  }

  static int _ceil(double v) {
    final c = v.ceil();
    // Guard against 5.000000000000001 style float noise.
    return (c - v) > 1 - 1e-9 ? c - 1 : c;
  }

  /// Stars (1..3) for a solved level.
  static int starsFor({required int moves, required int par}) {
    assert(moves >= 1, 'a solved level needs at least one move');
    final t = thresholds(par);
    if (moves <= t.three) return 3;
    if (moves <= t.two) return 2;
    return 1;
  }
}
