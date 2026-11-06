import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';

SavedGame game(int level, {int moves = 2}) => SavedGame(
  level: level,
  variant: 0,
  generatorVersion: 1,
  moves: [for (var i = 0; i < moves; i++) MoveModel(i, i + 1)],
);

void main() {
  group('unlocking', () {
    test('a new player starts at level 1 with only level 1 unlocked', () {
      final p = PlayerProgress.empty;
      expect(p.currentLevel, 1);
      expect(p.isUnlocked(1), isTrue);
      expect(p.isUnlocked(2), isFalse);
      expect(p.isUnlocked(0), isFalse);
      expect(p.isUnlocked(-3), isFalse);
      expect(p.completedCount, 0);
      expect(p.totalStars, 0);
    });

    test('completing a level unlocks the next, in order', () {
      var p = PlayerProgress.empty.withCompletion(level: 1, stars: 3, moves: 3);
      expect(p.currentLevel, 2);
      expect(p.isCompleted(1), isTrue);
      expect(p.isUnlocked(2), isTrue);
      expect(p.isUnlocked(3), isFalse);
      p = p.withCompletion(level: 2, stars: 1, moves: 9);
      expect(p.currentLevel, 3);
    });

    test(
      'levels cannot be skipped: a gap keeps the current level at the gap',
      () {
        // Level 3 completed while 2 is not (only possible via bad data).
        final p = PlayerProgress(
          records: {
            1: const LevelRecord(stars: 3, bestMoves: 3),
            3: const LevelRecord(stars: 2, bestMoves: 8),
          },
        );
        expect(p.currentLevel, 2);
        expect(p.isUnlocked(3), isFalse);
      },
    );

    test('works for very high levels', () {
      final p = PlayerProgress(
        records: {
          for (var l = 1; l <= 5000; l++)
            l: const LevelRecord(stars: 3, bestMoves: 20),
        },
      );
      expect(p.currentLevel, 5001);
      expect(p.totalStars, 15000);
      expect(p.completedCount, 5000);
    });
  });

  group('records', () {
    test('keeps the best stars and the fewest moves independently', () {
      var p = PlayerProgress.empty.withCompletion(
        level: 5,
        stars: 2,
        moves: 20,
      );
      p = p.withCompletion(
        level: 5,
        stars: 1,
        moves: 15,
      ); // fewer moves, fewer stars
      expect(p.recordOf(5)!.stars, 2);
      expect(p.recordOf(5)!.bestMoves, 15);
      p = p.withCompletion(level: 5, stars: 3, moves: 30);
      expect(p.recordOf(5)!.stars, 3);
      expect(p.recordOf(5)!.bestMoves, 15);
    });

    test('totals and per-range summaries', () {
      final p = PlayerProgress(
        records: {
          1: const LevelRecord(stars: 3, bestMoves: 3),
          2: const LevelRecord(stars: 2, bestMoves: 5),
          3: const LevelRecord(stars: 1, bestMoves: 9),
          11: const LevelRecord(stars: 3, bestMoves: 9),
        },
      );
      expect(p.totalStars, 9);
      expect(p.starsIn(1, 10), 6);
      expect(p.completedIn(1, 10), 3);
      expect(p.completedIn(11, 20), 1);
    });

    test('completing a level drops its saved game', () {
      var p = PlayerProgress.empty.withSavedGame(game(1));
      expect(p.saved.containsKey(1), isTrue);
      p = p.withCompletion(level: 1, stars: 3, moves: 3);
      expect(p.saved.containsKey(1), isFalse);
    });
  });

  group('saved games', () {
    test('continueGame is the last played level, if unfinished', () {
      var p = PlayerProgress.empty
          .withSavedGame(game(1))
          .withSavedGame(game(2));
      expect(p.continueGame!.level, 2);
      p = p.withLastPlayed(1);
      expect(p.continueGame!.level, 1);
      p = p.withoutSavedGame(1);
      expect(p.continueGame, isNull);
    });

    test('only the newest few are kept', () {
      var p = PlayerProgress.empty;
      for (var l = 1; l <= PlayerProgress.maxSavedGames + 5; l++) {
        p = p.withSavedGame(game(l));
      }
      expect(p.saved.length, PlayerProgress.maxSavedGames);
      expect(p.saved.containsKey(1), isFalse);
      expect(p.saved.containsKey(PlayerProgress.maxSavedGames + 5), isTrue);
    });

    test('re-saving a level replaces it and makes it the newest', () {
      var p = PlayerProgress.empty
          .withSavedGame(game(1, moves: 1))
          .withSavedGame(game(2));
      p = p.withSavedGame(game(1, moves: 4));
      expect(p.saved[1]!.moves.length, 4);
      expect(p.saved.keys.last, 1);
    });

    test('immutability', () {
      final p = PlayerProgress.empty;
      final q = p.withCompletion(level: 1, stars: 3, moves: 3);
      expect(p.completedCount, 0);
      expect(q.completedCount, 1);
      expect(
        () => q.records[9] = const LevelRecord(stars: 1, bestMoves: 1),
        throwsUnsupportedError,
      );
    });
  });

  group('serialisation', () {
    test('round trip keeps everything', () {
      final p = PlayerProgress.empty
          .withCompletion(level: 1, stars: 3, moves: 3)
          .withCompletion(level: 2, stars: 2, moves: 7)
          .withSavedGame(game(3, moves: 5));
      final back = PlayerProgress.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.records.keys, p.records.keys);
      expect(back.recordOf(2)!.stars, 2);
      expect(back.recordOf(2)!.bestMoves, 7);
      expect(back.saved[3]!.moves, p.saved[3]!.moves);
      expect(back.lastPlayedLevel, 3);
      expect(back.currentLevel, p.currentLevel);
    });

    test('garbage never throws and yields a usable state', () {
      for (final bad in [
        null,
        5,
        'x',
        <Object?>[],
        {'records': 3},
        {'saved': 'no'},
        {
          'records': {'a': 1},
        },
      ]) {
        expect(() => PlayerProgress.fromJson(bad), returnsNormally);
        expect(PlayerProgress.fromJson(bad).currentLevel, 1);
      }
    });

    test('bad entries are skipped, good ones kept', () {
      final p = PlayerProgress.fromJson({
        'records': {
          '1': {'stars': 3, 'bestMoves': 3},
          '2': {'stars': 9, 'bestMoves': 3}, // impossible star count
          'x': {'stars': 1, 'bestMoves': 1},
          '4': 'nope',
          '0': {'stars': 1, 'bestMoves': 1}, // level 0 does not exist
        },
        'saved': [
          {
            'level': 7,
            'variant': 0,
            'generatorVersion': 1,
            'moves': [
              [0, 1],
            ],
          },
          {
            'level': 8,
            'variant': 0,
            'generatorVersion': 1,
            'moves': [
              [0],
            ],
          }, // broken move
          {'level': 'q'},
        ],
        'last': 7,
      });
      expect(p.records.keys, [1]);
      expect(p.saved.keys, [7]);
      expect(p.lastPlayedLevel, 7);
    });

    test('a saved game for an already completed level is ignored', () {
      final p = PlayerProgress.fromJson({
        'records': {
          '1': {'stars': 3, 'bestMoves': 3},
        },
        'saved': [
          {'level': 1, 'variant': 0, 'generatorVersion': 1, 'moves': []},
        ],
      });
      expect(p.saved, isEmpty);
    });
  });
}
