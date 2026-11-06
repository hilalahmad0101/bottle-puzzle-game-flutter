import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/difficulty.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/application/playable_level.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';

SavedGame snap(int level, {int moves = 1}) {
  final lv = const LevelGenerator().generate(level);
  return SavedGame(
    level: level,
    variant: 0,
    generatorVersion: kGeneratorVersion,
    moves: [for (var i = 0; i < moves; i++) lv.solution[i]],
    seed: lv.seed,
    originalPuzzle: lv.puzzle,
    currentPuzzle: lv.puzzle,
    difficultyIndex: lv.difficulty.index,
    par: lv.solution.length,
    fingerprint: lv.fingerprint,
  );
}

void main() {
  group('hint statistics', () {
    test('requests and shown hints accumulate per level', () {
      var p = PlayerProgress.empty
          .withHint(4, requested: 1)
          .withHint(4, requested: 1, shown: 1)
          .withHint(9, shown: 2);
      expect(p.hintsOf(4).requested, 2);
      expect(p.hintsOf(4).shown, 1);
      expect(p.hintsOf(9).shown, 2);
      expect(p.hintsOf(77), const HintStat());
      expect(p.totalHintsShown, 3);
      expect(p.totalHintsRequested, 2);
    });

    test('adding nothing returns the very same object', () {
      final p = PlayerProgress.empty.withHint(1, requested: 1);
      expect(identical(p.withHint(1), p), isTrue);
    });

    test('completing a level keeps its hint statistics', () {
      final p = PlayerProgress.empty
          .withHint(1, requested: 2, shown: 2)
          .withCompletion(level: 1, stars: 3, moves: 3);
      expect(p.hintsOf(1).shown, 2);
    });
  });

  group('unlocked styles', () {
    test('crossing a star threshold unlocks and remembers the style', () {
      var p = PlayerProgress.empty;
      for (var l = 1; l <= 4; l++) {
        p = p.withCompletion(level: l, stars: 3, moves: 9);
      }
      expect(p.unlockedStyles, isNot(contains('crystal_prism')));
      p = p.withCompletion(level: 5, stars: 3, moves: 9);
      expect(p.unlockedStyles, contains('crystal_prism'));
      expect(p.isStyleUnlocked('crystal_prism'), isTrue);
      expect(p.isStyleUnlocked('royal_glass'), isFalse);
    });

    test(
      'the free style is always available; unknown styles count as free',
      () {
        expect(PlayerProgress.empty.isStyleUnlocked('alchemy_classic'), isTrue);
        expect(PlayerProgress.empty.isStyleUnlocked('something_new'), isTrue);
      },
    );

    test('a stored unlock is never revoked, whatever the star total', () {
      final p = PlayerProgress(unlockedStyles: const {'royal_glass'});
      expect(p.totalStars, 0);
      expect(p.isStyleUnlocked('royal_glass'), isTrue);
    });

    test('unlocks only ever grow', () {
      var p = PlayerProgress(
        records: {
          for (var l = 1; l <= 5; l++)
            l: const LevelRecord(stars: 3, bestMoves: 9),
        },
      ).normalized();
      final before = p.unlockedStyles;
      p = p.withCompletion(level: 6, stars: 1, moves: 40);
      expect(p.unlockedStyles, containsAll(before));
    });

    test(
      'normalizing adds what the stars have earned, and is a no-op otherwise',
      () {
        final earned = PlayerProgress(
          records: {
            for (var l = 1; l <= 15; l++)
              l: const LevelRecord(stars: 3, bestMoves: 9),
          },
        );
        expect(
          earned.normalized().unlockedStyles,
          containsAll(['crystal_prism', 'royal_glass']),
        );
        final none = PlayerProgress.empty;
        expect(identical(none.normalized(), none), isTrue);
      },
    );

    test('repeating a completed level cannot unlock anything extra', () {
      var p = PlayerProgress.empty;
      for (var l = 1; l <= 5; l++) {
        p = p.withCompletion(level: l, stars: 3, moves: 9);
      }
      final styles = p.unlockedStyles;
      final stars = p.totalStars;
      for (var i = 0; i < 10; i++) {
        p = p.withCompletion(level: 3, stars: 3, moves: 9);
      }
      expect(p.totalStars, stars);
      expect(p.unlockedStyles, styles);
      expect(p.recordOf(3)!.completions, 11);
    });
  });

  group('completion records', () {
    test('count completions, keep best stars and fewest moves', () {
      var p = PlayerProgress.empty.withCompletion(
        level: 2,
        stars: 1,
        moves: 20,
      );
      p = p.withCompletion(level: 2, stars: 3, moves: 25);
      p = p.withCompletion(level: 2, stars: 2, moves: 11);
      final r = p.recordOf(2)!;
      expect(r.stars, 3);
      expect(r.bestMoves, 11);
      expect(r.completions, 3);
    });

    test('value equality (used to find what changed)', () {
      expect(
        const LevelRecord(stars: 2, bestMoves: 5),
        const LevelRecord(stars: 2, bestMoves: 5),
      );
      expect(
        const LevelRecord(stars: 2, bestMoves: 5),
        isNot(const LevelRecord(stars: 3, bestMoves: 5)),
      );
      expect(
        const LevelRecord(stars: 2, bestMoves: 5),
        isNot(const LevelRecord(stars: 2, bestMoves: 5, completions: 2)),
      );
    });
  });

  group('saved game snapshot', () {
    test('carries the original puzzle, seed, difficulty, par and moves', () {
      final g = snap(8, moves: 2);
      expect(g.hasSnapshot, isTrue);
      expect(g.moveCount, 2);
      expect(g.originalPuzzle, isA<PuzzleState>());
      expect(g.par, greaterThan(0));
    });

    test('equal by value, different when anything differs', () {
      expect(snap(8), snap(8));
      expect(snap(8).hashCode, snap(8).hashCode);
      expect(snap(8), isNot(snap(8, moves: 2)));
      expect(snap(8), isNot(snap(9)));
    });

    test('withMoves replaces the history and keeps the snapshot', () {
      final g = snap(8, moves: 2).withMoves([const MoveModel(0, 1)]);
      expect(g.moves, [const MoveModel(0, 1)]);
      expect(g.originalPuzzle, snap(8).originalPuzzle);
    });

    test('a legacy save has no snapshot', () {
      final g = SavedGame(
        level: 3,
        variant: 0,
        generatorVersion: 1,
        moves: const [],
      );
      expect(g.hasSnapshot, isFalse);
      expect(PlayableLevel.fromSaved(g), isNull);
    });

    test('saved games are immutable', () {
      final g = snap(8, moves: 1);
      expect(() => g.moves.add(const MoveModel(0, 1)), throwsUnsupportedError);
    });
  });

  group('PlayableLevel', () {
    test('a level built from a save equals the level that was saved', () {
      final gen = const LevelGenerator().generate(40);
      final level = PlayableLevel.fromGenerated(gen);
      final back = PlayableLevel.fromSaved(
        level.toSaved(const [MoveModel(0, 1)], gen.puzzle),
      )!;
      expect(back.levelNumber, 40);
      expect(back.puzzle, gen.puzzle);
      expect(back.seed, gen.seed);
      expect(back.difficulty, gen.difficulty);
      expect(back.par, gen.solution.length);
      expect(back.generatorVersion, gen.generatorVersion);
      expect(back.fingerprint, gen.fingerprint);
    });

    test('incomplete or impossible snapshots are refused', () {
      final base = snap(8);
      SavedGame withBits({int? seed, int? par, int? d, bool puzzle = true}) =>
          SavedGame(
            level: 8,
            variant: 0,
            generatorVersion: 1,
            moves: const [],
            seed: seed,
            par: par,
            difficultyIndex: d,
            originalPuzzle: puzzle ? base.originalPuzzle : null,
          );
      expect(
        PlayableLevel.fromSaved(withBits(seed: 1, par: 4, d: 1)),
        isNotNull,
      );
      expect(PlayableLevel.fromSaved(withBits(par: 4, d: 1)), isNull);
      expect(PlayableLevel.fromSaved(withBits(seed: 1, d: 1)), isNull);
      expect(PlayableLevel.fromSaved(withBits(seed: 1, par: 4)), isNull);
      expect(
        PlayableLevel.fromSaved(withBits(seed: 1, par: 4, d: 1, puzzle: false)),
        isNull,
      );
      expect(PlayableLevel.fromSaved(withBits(seed: 1, par: 4, d: 9)), isNull);
      expect(PlayableLevel.fromSaved(withBits(seed: 1, par: 4, d: -1)), isNull);
      expect(Difficulty.values.length, 4);
    });
  });
}
