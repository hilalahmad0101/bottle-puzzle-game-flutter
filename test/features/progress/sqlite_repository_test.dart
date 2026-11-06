import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/sqlite_support.dart';

SavedGame fullSave(int level, {int moves = 2, int variant = 0}) {
  final lv = const LevelGenerator().generate(level, variant: variant);
  final list = [for (var i = 0; i < moves; i++) lv.solution[i]];
  return SavedGame(
    level: level,
    variant: variant,
    generatorVersion: kGeneratorVersion,
    moves: list,
    seed: lv.seed,
    originalPuzzle: lv.puzzle,
    currentPuzzle: PuzzleState.fromIds([
      [0],
      [],
    ]),
    difficultyIndex: lv.difficulty.index,
    par: lv.solution.length,
    fingerprint: lv.fingerprint,
  );
}

Future<int> count(Database db, String table) async =>
    Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table'))!;

void main() {
  group('save and restore everything', () {
    test(
      'every kind of data survives closing and reopening the file',
      () async {
        final dir = tempDir();
        final path = dbPathIn(dir);
        final save = fullSave(8, moves: 3);
        final original = PlayerProgress.empty
            .withCompletion(level: 1, stars: 3, moves: 3)
            .withCompletion(level: 2, stars: 2, moves: 9)
            .withCompletion(
              level: 2,
              stars: 1,
              moves: 5,
            ) // best moves 5, best stars 2, completions 2
            .withSavedGame(save)
            .withHint(8, requested: 4, shown: 3)
            .withHint(2, requested: 1);

        final a = repoAt(path);
        await a.loadProgress();
        await a.saveProgress(original);
        await a.saveSettings(
          const AppSettings(
            soundEffects: false,
            speed: AnimationSpeed.fast,
            colorAssist: ColorAssist.both,
            bottleStyleId: 'crystal_prism',
          ),
        );
        await a.close();

        final b = repoAt(path);
        final back = await b.loadProgress();
        expect(back.records, original.records);
        expect(back.recordOf(2)!.completions, 2);
        expect(back.saved[8], save);
        expect(back.saved[8]!.originalPuzzle, save.originalPuzzle);
        expect(back.saved[8]!.moves, save.moves);
        expect(back.saved[8]!.moveCount, 3);
        expect(back.hints, original.hints);
        expect(back.totalHintsShown, 3);
        expect(back.lastPlayedLevel, 8);
        expect(back.unlockedStyles, original.unlockedStyles);
        final s = await b.loadSettings();
        expect(s.soundEffects, isFalse);
        expect(s.speed, AnimationSpeed.fast);
        expect(s.colorAssist, ColorAssist.both);
        expect(s.bottleStyleId, 'crystal_prism');
        await b.close();
      },
    );

    test('an empty database loads as a brand new player', () async {
      final repo = repoAt(dbPathIn(tempDir()));
      final p = await repo.loadProgress();
      expect(p.currentLevel, 1);
      expect(p.records, isEmpty);
      expect(p.saved, isEmpty);
      expect(await repo.loadSettings(), const AppSettings());
      await repo.close();
    });

    test(
      'saved games keep their order (newest last) across restarts',
      () async {
        final path = dbPathIn(tempDir());
        var p = PlayerProgress.empty;
        for (final l in [1, 2, 3]) {
          p = p.withSavedGame(fullSave(l, moves: 1));
        }
        p = p.withSavedGame(fullSave(1, moves: 2)); // level 1 becomes newest
        final a = repoAt(path);
        await a.loadProgress();
        await a.saveProgress(p);
        await a.close();
        final back = await repoAt(path).loadProgress();
        expect(back.saved.keys.toList(), [2, 3, 1]);
        expect(back.lastPlayedLevel, 1);
      },
    );

    test(
      'at most ten unfinished games are kept, in the database too',
      () async {
        final path = dbPathIn(tempDir());
        var p = PlayerProgress.empty;
        final a = repoAt(path);
        await a.loadProgress();
        for (var l = 1; l <= 14; l++) {
          p = p.withSavedGame(
            fullSave(
              l <= 5 ? l : 3,
              moves: 1,
            ).withMoves(const [MoveModel(0, 1)]).copyLevel(l),
          );
          await a.saveProgress(p);
        }
        await a.close();
        final db = await rawDb(path);
        expect(await count(db, 'saved_games'), PlayerProgress.maxSavedGames);
        await db.close();
      },
    );
  });

  group('writes are minimal, ordered and safe', () {
    test('only what changed is written (other rows are left alone)', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      final p0 = await repo.loadProgress();
      final p1 = p0
          .withCompletion(level: 1, stars: 3, moves: 3)
          .withSavedGame(fullSave(5, moves: 1));
      await repo.saveProgress(p1);

      // Someone else edits an unrelated row...
      final db = await repo.database;
      await db.update('completed_levels', {
        'best_moves': 99,
      }, where: 'level = 1');

      // ...then a save changes only the saved game.
      await repo.saveProgress(p1.withSavedGame(fullSave(5, moves: 2)));
      final row = (await db.query(
        'completed_levels',
        where: 'level = 1',
      )).single;
      expect(
        row['best_moves'],
        99,
        reason: 'the unchanged record was not rewritten',
      );
      expect((await db.query('saved_games')).single['move_count'], 2);
      await repo.close();
    });

    test('a save can never delete a recorded level', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      await repo.loadProgress();
      final withTwo = PlayerProgress.empty
          .withCompletion(level: 1, stars: 3, moves: 3)
          .withCompletion(level: 2, stars: 2, moves: 8);
      await repo.saveProgress(withTwo);
      await repo.saveProgress(
        PlayerProgress.empty,
      ); // e.g. a bug that lost state in memory
      await repo.close();
      final back = await repoAt(path).loadProgress();
      expect(back.records.keys, [1, 2]);
    });

    test('a finished or abandoned saved game is removed', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      await repo.loadProgress();
      final withSave = PlayerProgress.empty.withSavedGame(fullSave(3));
      await repo.saveProgress(withSave);
      await repo.saveProgress(withSave.withoutSavedGame(3));
      final db = await repo.database;
      expect(await count(db, 'saved_games'), 0);
      await repo.close();
    });

    test('200 rapid saves end with the LAST one, in order', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      var p = await repo.loadProgress();
      final lv = const LevelGenerator().generate(40);
      final futures = <Future<void>>[];
      for (var n = 1; n <= 200; n++) {
        final moves = [for (var i = 0; i < n % 9 + 1; i++) lv.solution[i]];
        p = p.withSavedGame(
          SavedGame(
            level: 40,
            variant: 0,
            generatorVersion: kGeneratorVersion,
            moves: moves,
            seed: n,
          ),
        );
        futures.add(repo.saveProgress(p));
      }
      await Future.wait(futures);
      final back = (await repoAt(path).loadProgress()).saved[40]!;
      expect(back.seed, 200);
      expect(back.moves.length, 200 % 9 + 1);
      await repo.close();
    });

    test('flush returns only after everything accepted is on disk', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      final p0 = await repo.loadProgress();
      final f = repo.saveProgress(
        p0.withCompletion(level: 1, stars: 3, moves: 3),
      ); // not awaited
      await repo.flush();
      final fresh = await repoAt(path).loadProgress();
      expect(fresh.recordOf(1), isNotNull);
      await f;
      await repo.close();
    });

    test(
      'a completion is ATOMIC: if any part fails, none of it is applied',
      () async {
        final path = dbPathIn(tempDir());
        final repo = repoAt(path);
        final p0 = await repo.loadProgress();
        final withSave = p0.withSavedGame(fullSave(3));
        await repo.saveProgress(withSave);

        // The completion removes the saved game and adds a record... plus one
        // impossible row (5 stars) that the database must refuse.
        final bad = PlayerProgress(
          records: {
            3: const LevelRecord(stars: 3, bestMoves: 7),
            4: const LevelRecord(stars: 5, bestMoves: 1),
          },
          saved: const {},
          lastPlayedLevel: 3,
        );
        await expectLater(
          repo.saveProgress(bad),
          throwsA(isA<DatabaseException>()),
        );

        final db = await repo.database;
        expect(
          await count(db, 'saved_games'),
          1,
          reason: 'the saved game was NOT removed',
        );
        expect(
          await count(db, 'completed_levels'),
          0,
          reason: 'the record was NOT half-written',
        );

        // The next valid save succeeds and brings everything up to date.
        await repo.saveProgress(
          withSave.withCompletion(level: 3, stars: 3, moves: 7),
        );
        expect(await count(db, 'saved_games'), 0);
        expect(await count(db, 'completed_levels'), 1);
        await repo.close();
      },
    );

    test(
      'a write failure leaves the data for the next attempt (nothing is lost)',
      () async {
        final path = dbPathIn(tempDir());
        final repo = repoAt(path);
        final p0 = await repo.loadProgress();
        final good = p0.withCompletion(level: 1, stars: 3, moves: 3);
        final bad = good.withCompletion(level: 2, stars: 1, moves: 4);
        final db = await repo.database;
        await db.execute(
          'CREATE TRIGGER block BEFORE INSERT ON completed_levels WHEN NEW.level = 2 BEGIN SELECT RAISE(ABORT, "disk full"); END',
        );
        await expectLater(repo.saveProgress(bad), throwsA(anything));
        await db.execute('DROP TRIGGER block');
        await repo.flush(); // retries what could not be written
        final back = await repoAt(path).loadProgress();
        expect(back.records.keys, [1, 2]);
        await repo.close();
      },
    );

    test('close is safe to call twice and writes pending data', () async {
      final path = dbPathIn(tempDir());
      final repo = repoAt(path);
      final p0 = await repo.loadProgress();
      unawaited(
        repo.saveProgress(p0.withCompletion(level: 1, stars: 2, moves: 5)),
      );
      await repo.close();
      await repo.close();
      expect((await repoAt(path).loadProgress()).recordOf(1)!.stars, 2);
    });
  });

  group('loading damaged data', () {
    test(
      'a saved game with unreadable moves is dropped; everything else loads',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        final p0 = await a.loadProgress();
        await a.saveProgress(
          p0
              .withCompletion(level: 1, stars: 3, moves: 3)
              .withSavedGame(fullSave(5))
              .withSavedGame(fullSave(6)),
        );
        final db = await a.database;
        await db.update('saved_games', {
          'moves': 'this is not json',
        }, where: 'level = 5');
        await a.close();

        final b = repoAt(path);
        final p = await b.loadProgress();
        expect(p.records.keys, [1]);
        expect(p.saved.keys, [6]);
        expect(b.takeNotices().single, contains('damaged'));
        final db2 = await b.database;
        expect(
          await count(db2, 'saved_games'),
          1,
          reason: 'the unrestorable row is removed',
        );
        await b.close();
      },
    );

    test('moves with the wrong shape are rejected row by row', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      final p0 = await a.loadProgress();
      await a.saveProgress(
        p0
            .withSavedGame(fullSave(5))
            .withSavedGame(fullSave(6))
            .withSavedGame(fullSave(7)),
      );
      final db = await a.database;
      await db.update('saved_games', {
        'moves': jsonEncode([
          [0],
        ]),
      }, where: 'level = 5');
      await db.update('saved_games', {
        'moves': jsonEncode([
          ['a', 'b'],
        ]),
      }, where: 'level = 6');
      await a.close();
      final p = await repoAt(path).loadProgress();
      expect(p.saved.keys, [7]);
    });

    test('a damaged SNAPSHOT keeps the game (moves) and falls back to rebuilding the level', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      final p0 = await a.loadProgress();
      await a.saveProgress(p0.withSavedGame(fullSave(5, moves: 2)));
      final db = await a.database;
      await db.update('saved_games', {
        'original_state': '[[4,1,2',
      }, where: 'level = 5');
      await a.close();

      final b = repoAt(path);
      final g = (await b.loadProgress()).saved[5]!;
      expect(g.moves.length, 2);
      expect(g.hasSnapshot, isFalse);
      expect(b.takeNotices().join(), contains('snapshot was damaged'));
      await b.close();
    });

    test(
      'an impossible snapshot (empty, over-full) is treated as damaged',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        final p0 = await a.loadProgress();
        await a.saveProgress(p0.withSavedGame(fullSave(5)));
        final db = await a.database;
        await db.update('saved_games', {
          'original_state': jsonEncode([
            [2, 1, 1, 1],
          ]),
        }, where: 'level = 5');
        await a.close();
        final g = (await repoAt(path).loadProgress()).saved[5]!;
        expect(g.hasSnapshot, isFalse);
      },
    );

    test(
      'out-of-range difficulty / par / seed are ignored, not trusted',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        final p0 = await a.loadProgress();
        await a.saveProgress(p0.withSavedGame(fullSave(5)));
        final db = await a.database;
        await db.update('saved_games', {
          'difficulty': 99,
          'par': -3,
        }, where: 'level = 5');
        await a.close();
        final g = (await repoAt(path).loadProgress()).saved[5]!;
        expect(g.difficultyIndex, isNull);
        expect(g.par, isNull);
      },
    );

    test(
      'a saved game for a level that is already completed is not offered again',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        final p0 = await a.loadProgress();
        await a.saveProgress(p0.withSavedGame(fullSave(5)));
        final db = await a.database;
        await db.insert('completed_levels', {
          'level': 5,
          'stars': 2,
          'best_moves': 9,
        });
        await a.close();
        final p = await repoAt(path).loadProgress();
        expect(p.saved, isEmpty);
        expect(p.isCompleted(5), isTrue);
      },
    );

    test('a damaged setting falls back alone; the others are kept', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      await a.loadProgress();
      await a.saveSettings(
        const AppSettings(haptics: false, speed: AnimationSpeed.fast),
      );
      final db = await a.database;
      await db.update('settings', {'value': '{{{'}, where: "key = 'speed'");
      await db.update('settings', {'value': '"warp"'}, where: "key = 'motion'");
      await a.close();
      final s = await repoAt(path).loadSettings();
      expect(s.haptics, isFalse);
      expect(s.speed, AnimationSpeed.normal);
      expect(s.motion, MotionPreference.system);
    });

    test('no damage means no notices', () async {
      final repo = repoAt(dbPathIn(tempDir()));
      final p0 = await repo.loadProgress();
      await repo.saveProgress(
        p0
            .withCompletion(level: 1, stars: 3, moves: 3)
            .withSavedGame(fullSave(5)),
      );
      await repo.close();
      final b = repoAt(dbPathIn(tempDir()));
      await b.loadProgress();
      expect(b.takeNotices(), isEmpty);
    });
  });

  group('very high level numbers', () {
    const big = [1000000, 4294967296, 1 << 40, 9007199254740993, 1 << 62];

    test(
      'completed levels, saved games and hint stats at huge levels are exact',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        var p = await a.loadProgress();
        for (final l in big) {
          p = p
              .withCompletion(level: l, stars: 2, moves: 11)
              .withHint(l, requested: 2, shown: 1);
        }
        const savedLevel = 1 << 61; // unfinished, so it is not in `big`
        final lv = const LevelGenerator().generate(savedLevel);
        p = p.withSavedGame(
          SavedGame(
            level: savedLevel,
            variant: 0,
            generatorVersion: kGeneratorVersion,
            moves: const [MoveModel(0, 1)],
            seed: lv.seed,
            originalPuzzle: lv.puzzle,
            difficultyIndex: 3,
            par: lv.solution.length,
            fingerprint: lv.fingerprint,
          ),
        );
        await a.saveProgress(p);
        await a.close();

        final b = repoAt(path);
        final back = await b.loadProgress();
        expect(back.records.keys.toSet(), big.toSet());
        for (final l in big) {
          expect(back.recordOf(l)!.bestMoves, 11, reason: 'level $l');
          expect(back.hintsOf(l).shown, 1);
        }
        expect(back.saved[savedLevel]!.originalPuzzle, lv.puzzle);
        expect(back.lastPlayedLevel, savedLevel);
        await b.close();
      },
    );

    test('the current level is still the first unfinished one', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      final p = (await a.loadProgress()).withCompletion(
        level: 1 << 40,
        stars: 3,
        moves: 20,
      );
      await a.saveProgress(p);
      await a.close();
      expect(
        (await repoAt(path).loadProgress()).currentLevel,
        1,
        reason: 'levels cannot be skipped',
      );
    });

    test('a long unbroken run of completed levels loads and reports the next level', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      var p = await a.loadProgress();
      final records = {
        for (var l = 1; l <= 20000; l++)
          l: LevelRecord(stars: 1 + l % 3, bestMoves: 20 + l % 7),
      };
      p = PlayerProgress(records: records);
      await a.saveProgress(p);
      await a.close();
      final back = await repoAt(path).loadProgress();
      expect(back.currentLevel, 20001);
      expect(back.completedCount, 20000);
      expect(back.totalStars, p.totalStars);
    });
  });

  group('extra-bottle flag', () {
    test(
      'a boosted game is stored, reloaded and a standard one is not',
      () async {
        final path = dbPathIn(tempDir());
        final a = repoAt(path);
        await a.loadProgress();
        final plain = fullSave(4);
        final boosted = SavedGame(
          level: 5,
          variant: plain.variant,
          generatorVersion: plain.generatorVersion,
          moves: plain.moves,
          seed: plain.seed,
          originalPuzzle: plain.originalPuzzle,
          currentPuzzle: plain.currentPuzzle,
          difficultyIndex: plain.difficultyIndex,
          par: plain.par,
          fingerprint: plain.fingerprint,
          boosted: true,
        );
        await a.saveProgress(
          PlayerProgress.empty.withSavedGame(plain).withSavedGame(boosted),
        );
        await a.close();

        final b = repoAt(path);
        final p = await b.loadProgress();
        expect(p.saved[4]!.boosted, isFalse);
        expect(p.saved[5]!.boosted, isTrue);
        expect(p.saved[5], boosted);
        await b.close();
      },
    );

    test('the flag is part of a game\'s identity', () {
      final g = fullSave(4);
      final b = SavedGame(
        level: g.level,
        variant: g.variant,
        generatorVersion: g.generatorVersion,
        moves: g.moves,
        seed: g.seed,
        originalPuzzle: g.originalPuzzle,
        currentPuzzle: g.currentPuzzle,
        difficultyIndex: g.difficultyIndex,
        par: g.par,
        fingerprint: g.fingerprint,
        boosted: true,
      );
      expect(b, isNot(g));
      expect(g.withMoves(g.moves).boosted, isFalse);
      expect(b.withMoves(b.moves).boosted, isTrue);
    });

    test('the booster setting is stored and survives a restart', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      await a.loadProgress();
      expect((await a.loadSettings()).extraBottleBooster, isFalse);
      await a.saveSettings(const AppSettings(extraBottleBooster: true));
      await a.close();
      final b = repoAt(path);
      await b.loadProgress();
      expect((await b.loadSettings()).extraBottleBooster, isTrue);
      await b.close();
    });
  });

  group('settings', () {
    test('every field is stored and updated in place', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      await a.loadProgress();
      await a.saveSettings(const AppSettings(haptics: false));
      await a.saveSettings(
        const AppSettings(haptics: true, motion: MotionPreference.on),
      );
      final db = await a.database;
      expect(
        await count(db, 'settings'),
        9,
        reason: 'one row per setting, updated not duplicated',
      );
      await a.close();
      final s = await repoAt(path).loadSettings();
      expect(s.haptics, isTrue);
      expect(s.motion, MotionPreference.on);
    });
  });

  group('notices', () {
    test('are returned once and cleared', () async {
      final repo = repoAt(dbPathIn(tempDir()));
      await repo.loadProgress();
      expect(repo.takeNotices(), isEmpty);
    });
  });
}

extension on SavedGame {
  SavedGame copyLevel(int newLevel) => SavedGame(
    level: newLevel,
    variant: variant,
    generatorVersion: generatorVersion,
    moves: moves,
    seed: seed,
    originalPuzzle: originalPuzzle,
    currentPuzzle: currentPuzzle,
    difficultyIndex: difficultyIndex,
    par: par,
    fingerprint: fingerprint,
  );
}

void unawaited(Future<void> f) {}
