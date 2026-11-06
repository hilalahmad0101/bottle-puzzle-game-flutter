import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/progression/star_rating.dart';

void main() {
  group('documented rules', () {
    test('3 stars: <= ceil(par x 1.25), 2 stars: <= ceil(par x 1.75)', () {
      final t = StarRating.thresholds(10);
      expect(t.three, 13); // ceil(12.5)
      expect(t.two, 18); // ceil(17.5)
      expect(StarRating.thresholds(20).three, 25);
      expect(StarRating.thresholds(20).two, 35);
      expect(StarRating.thresholds(3).three, 4); // ceil(3.75)
      expect(StarRating.thresholds(3).two, 6); // ceil(5.25)
    });

    test('exactly on a threshold still earns the stars', () {
      expect(StarRating.starsFor(moves: 13, par: 10), 3);
      expect(StarRating.starsFor(moves: 14, par: 10), 2);
      expect(StarRating.starsFor(moves: 18, par: 10), 2);
      expect(StarRating.starsFor(moves: 19, par: 10), 1);
    });

    test('par itself and anything better is 3 stars', () {
      for (var par = 1; par <= 60; par++) {
        expect(
          StarRating.starsFor(moves: par, par: par),
          3,
          reason: 'par $par',
        );
        if (par > 1) expect(StarRating.starsFor(moves: par - 1, par: par), 3);
      }
    });

    test('finishing is always at least 1 star, however long it took', () {
      expect(StarRating.starsFor(moves: 500, par: 5), 1);
      expect(StarRating.starsFor(moves: 100000, par: 40), 1);
    });
  });

  group('invariants', () {
    test('thresholds are ordered and never below par', () {
      for (var par = 1; par <= 200; par++) {
        final t = StarRating.thresholds(par);
        expect(t.three, greaterThanOrEqualTo(par));
        expect(t.two, greaterThanOrEqualTo(t.three));
      }
    });

    test('stars never increase as moves increase', () {
      for (final par in [1, 3, 7, 13, 29, 40]) {
        var prev = 4;
        for (var moves = 1; moves <= par * 3; moves++) {
          final s = StarRating.starsFor(moves: moves, par: par);
          expect(s, lessThanOrEqualTo(prev), reason: 'par $par moves $moves');
          expect(s, inInclusiveRange(1, 3));
          prev = s;
        }
      }
    });

    test('no floating point surprises at exact multiples', () {
      // par 4 x 1.25 = 5 exactly; par 8 x 1.75 = 14 exactly.
      expect(StarRating.thresholds(4).three, 5);
      expect(StarRating.thresholds(8).two, 14);
      expect(StarRating.thresholds(20).three, 25);
      expect(StarRating.thresholds(12).three, 15);
    });

    test('the tutorials give sensible, achievable targets', () {
      // Tutorial pars (proven shortest): 3, 4, 7, 10, 13.
      for (final par in [3, 4, 7, 10, 13]) {
        expect(StarRating.starsFor(moves: par, par: par), 3);
        expect(StarRating.thresholds(par).three, lessThan(par * 2));
      }
    });
  });
}
