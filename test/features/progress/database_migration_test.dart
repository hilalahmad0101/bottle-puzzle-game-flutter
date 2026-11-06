import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/generator/generator_version.dart';
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/features/progress/data/database/migrations.dart';
import 'package:prism_pour/features/progress/data/legacy_prefs.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/sqlite_support.dart';

Future<Set<String>> tablesOf(Database db) async => {
  for (final r in await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  ))
    r['name']! as String,
};

Future<Set<String>> columnsOf(Database db, String table) async => {
  for (final r in await db.rawQuery('PRAGMA table_info($table)'))
    r['name']! as String,
};

Future<int> userVersion(Database db) async =>
    Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'))!;

/// A database exactly as the FIRST released schema (version 1) left it:
/// moves-only saved games, no hint or unlock tables.
Future<String> buildV1Database(Directory dir) async {
  final path = dbPathIn(dir);
  final db = await testFactory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, v) => Migrations.run(db, 0, 1),
    ),
  );
  await db.insert('completed_levels', {
    'level': 1,
    'stars': 3,
    'best_moves': 3,
    'completions': 1,
  });
  await db.insert('completed_levels', {
    'level': 2,
    'stars': 2,
    'best_moves': 7,
    'completions': 2,
  });
  await db.insert('saved_games', {
    'level': 3,
    'variant': 0,
    'generator_version': kGeneratorVersion,
    'moves': jsonEncode([
      [0, 2],
    ]),
    'saved_order': 0,
  });
  await db.insert('settings', {'key': 'haptics', 'value': 'false'});
  await db.insert('meta', {'key': 'last_played', 'value': '3'});
  await db.close();
  return path;
}

void main() {
  group('fresh database', () {
    test('is created at the latest version with every table', () async {
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir));
      await repo.loadProgress();
      await repo.close();
      final db = await rawDb(dbPathIn(dir));
      expect(await userVersion(db), Migrations.latest);
      expect(await tablesOf(db), {
        'meta',
        'settings',
        'completed_levels',
        'saved_games',
        'hint_stats',
        'unlocked_styles',
      });
      await db.close();
    });

    test('has the snapshot columns on saved games', () async {
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir));
      await repo.loadProgress();
      await repo.close();
      final db = await rawDb(dbPathIn(dir));
      expect(
        await columnsOf(db, 'saved_games'),
        containsAll([
          'level',
          'variant',
          'generator_version',
          'moves',
          'seed',
          'original_state',
          'current_state',
          'move_count',
          'difficulty',
          'par',
          'fingerprint',
        ]),
      );
      await db.close();
    });

    test('rejects impossible values with constraints', () async {
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir));
      await repo.loadProgress();
      final db = await repo.database;
      for (final bad in [
        {'level': 0, 'stars': 3, 'best_moves': 3},
        {'level': 1, 'stars': 4, 'best_moves': 3},
        {'level': 1, 'stars': 0, 'best_moves': 3},
        {'level': 1, 'stars': 3, 'best_moves': 0},
      ]) {
        expect(
          () => db.insert('completed_levels', bad),
          throwsA(isA<DatabaseException>()),
          reason: '$bad',
        );
      }
      await repo.close();
    });
  });

  group('upgrading from version 1', () {
    test('keeps every row and adds the new columns and tables', () async {
      final dir = tempDir();
      final path = await buildV1Database(dir);

      final repo = repoAt(path);
      final progress = await repo.loadProgress();
      expect(progress.records.keys, [1, 2]);
      expect(progress.recordOf(2)!.stars, 2);
      expect(progress.recordOf(2)!.bestMoves, 7);
      expect(progress.recordOf(2)!.completions, 2);
      expect(progress.lastPlayedLevel, 3);
      expect(progress.saved[3]!.moves, [const MoveModel(0, 2)]);
      expect(
        progress.saved[3]!.hasSnapshot,
        isFalse,
        reason: 'a version-1 save has no snapshot',
      );
      expect((await repo.loadSettings()).haptics, isFalse);
      await repo.close();

      final db = await rawDb(path);
      expect(await userVersion(db), Migrations.latest);
      expect(
        await columnsOf(db, 'saved_games'),
        containsAll(['seed', 'original_state', 'par', 'booster']),
      );
      expect(
        await tablesOf(db),
        containsAll(['hint_stats', 'unlocked_styles']),
      );
      await db.close();
    });

    test('upgraded and fresh databases have the same schema', () async {
      final dirA = tempDir();
      final fresh = repoAt(dbPathIn(dirA));
      await fresh.loadProgress();
      await fresh.close();

      final dirB = tempDir();
      final upgradedPath = await buildV1Database(dirB);
      final up = repoAt(upgradedPath);
      await up.loadProgress();
      await up.close();

      final a = await rawDb(dbPathIn(dirA));
      final b = await rawDb(upgradedPath);
      expect(await tablesOf(a), await tablesOf(b));
      for (final t in await tablesOf(a)) {
        expect(
          await columnsOf(b, t),
          await columnsOf(a, t),
          reason: 'table $t',
        );
      }
      await a.close();
      await b.close();
    });

    test(
      'a pre-snapshot save can be upgraded to a full one and reloaded',
      () async {
        final dir = tempDir();
        final path = await buildV1Database(dir);
        final repo = repoAt(path);
        final progress = await repo.loadProgress();
        final lv = const LevelGenerator().generate(3);
        final upgraded = progress.withSavedGame(
          SavedGame(
            level: 3,
            variant: 0,
            generatorVersion: kGeneratorVersion,
            moves: progress.saved[3]!.moves,
            seed: lv.seed,
            originalPuzzle: lv.puzzle,
            difficultyIndex: 0,
            par: lv.solution.length,
            fingerprint: lv.fingerprint,
          ),
        );
        await repo.saveProgress(upgraded);
        await repo.close();

        final again = repoAt(path);
        final back = (await again.loadProgress()).saved[3]!;
        expect(back.hasSnapshot, isTrue);
        expect(back.originalPuzzle, lv.puzzle);
        expect(back.seed, lv.seed);
        await again.close();
      },
    );

    test('migrations are idempotent (re-running changes nothing)', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      final db = await testFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(version: 1),
      );
      await Migrations.run(db, 0, Migrations.latest);
      await db.insert('completed_levels', {
        'level': 5,
        'stars': 1,
        'best_moves': 9,
      });
      await Migrations.run(
        db,
        0,
        Migrations.latest,
      ); // as after a version-lowering downgrade
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM completed_levels'),
        ),
        1,
      );
      await db.close();
    });
  });

  group('version 3: the extra-bottle flag', () {
    test(
      'a version-2 database upgrades; old saves are standard games',
      () async {
        final dir = tempDir();
        final path = dbPathIn(dir);
        final level = const LevelGenerator().generate(3);
        final db = await testFactory.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: 2,
            onCreate: (db, v) => Migrations.run(db, 0, 2),
          ),
        );
        await db.insert('saved_games', {
          'level': 3,
          'variant': level.variant,
          'generator_version': level.generatorVersion,
          'moves': jsonEncode([
            [level.solution.first.source, level.solution.first.destination],
          ]),
          'saved_order': 1,
        });
        expect(await columnsOf(db, 'saved_games'), isNot(contains('booster')));
        await db.close();

        final repo = repoAt(path);
        final p = await repo.loadProgress();
        expect(p.saved[3], isNotNull);
        expect(p.saved[3]!.boosted, isFalse);
        expect(p.saved[3]!.moves, hasLength(1));
        await repo.close();

        final after = await rawDb(path);
        expect(await userVersion(after), Migrations.latest);
        expect(await columnsOf(after, 'saved_games'), contains('booster'));
        await after.close();
      },
    );

    test('running the migration twice is harmless', () async {
      final dir = tempDir();
      final db = await testFactory.openDatabase(
        dbPathIn(dir),
        options: OpenDatabaseOptions(version: 1),
      );
      await Migrations.run(db, 0, Migrations.latest);
      await Migrations.run(db, 2, Migrations.latest);
      expect(await columnsOf(db, 'saved_games'), contains('booster'));
      await db.close();
    });
  });

  group('migration runner', () {
    final extra = Migration(4, 'adds a table', (db) async {
      await db.execute(
        'CREATE TABLE IF NOT EXISTS extra_notes (id INTEGER PRIMARY KEY, note TEXT)',
      );
    });

    test(
      'applies migrations in order, only those newer than the database',
      () async {
        final order = <int>[];
        final steps = [
          Migration(1, 'a', (db) async => order.add(1)),
          Migration(2, 'b', (db) async => order.add(2)),
          Migration(3, 'c', (db) async => order.add(3)),
        ];
        final dir = tempDir();
        final db = await testFactory.openDatabase(dbPathIn(dir));
        await Migrations.run(db, 1, 3, migrations: steps);
        expect(order, [2, 3]);
        order.clear();
        await Migrations.run(db, 0, 2, migrations: steps);
        expect(order, [1, 2]);
        await db.close();
      },
    );

    test(
      'a failing upgrade changes NOTHING and the data stays readable',
      () async {
        final dir = tempDir();
        final path = dbPathIn(dir);
        // A database at version 4 with data in it.
        final first = repoAt(path, migrations: [...Migrations.all, extra]);
        await first.loadProgress();
        await first.saveProgress(
          PlayerProgress.empty.withCompletion(level: 1, stars: 3, moves: 3),
        );
        await first.close();

        final boom = Migration(5, 'explodes half way', (db) async {
          await db.execute('CREATE TABLE half_done (x INTEGER)');
          throw StateError('migration bug');
        });
        final broken = repoAt(
          path,
          migrations: [...Migrations.all, extra, boom],
        );
        await expectLater(broken.loadProgress(), throwsA(anything));

        // Not treated as corruption: the file is still there, untouched.
        expect(File(path).existsSync(), isTrue);
        expect(
          Directory(dir.path)
              .listSync()
              .where((f) => f.path.contains('.corrupt')),
          isEmpty,
        );
        final db = await rawDb(path);
        expect(await userVersion(db), 4, reason: 'the version did not advance');
        expect(
          await tablesOf(db),
          isNot(contains('half_done')),
          reason: 'the partial step was rolled back',
        );
        await db.close();

        // The previous version of the app still opens it with all data.
        final ok = repoAt(path, migrations: [...Migrations.all, extra]);
        expect((await ok.loadProgress()).recordOf(1)!.stars, 3);
        await ok.close();
      },
    );

    test('a database from a NEWER app opens and keeps its data', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      final newer = repoAt(path, migrations: [...Migrations.all, extra]);
      await newer.loadProgress();
      await newer.saveProgress(
        PlayerProgress.empty.withCompletion(level: 4, stars: 2, moves: 8),
      );
      await newer.close();

      final older = repoAt(path); // knows only versions 1-3
      final p = await older.loadProgress();
      expect(p.recordOf(4)!.bestMoves, 8);
      await older.saveProgress(p.withCompletion(level: 5, stars: 1, moves: 20));
      await older.close();

      final db = await rawDb(path);
      expect(
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM completed_levels'),
        ),
        2,
      );
      expect(
        await tablesOf(db),
        contains('extra_notes'),
        reason: 'the newer app\'s data is never dropped',
      );
      await db.close();
    });
  });

  group('damaged database file', () {
    test(
      'is backed up (never deleted) and replaced; the player is told',
      () async {
        final dir = tempDir();
        final path = dbPathIn(dir);
        File(path).writeAsBytesSync(List.generate(4096, (i) => (i * 31) % 256));

        final repo = repoAt(path);
        final p = await repo.loadProgress();
        expect(p.records, isEmpty);
        expect(
          File('$path.corrupt-1').existsSync(),
          isTrue,
          reason: 'the damaged file is kept',
        );
        expect(File('$path.corrupt-1').lengthSync(), 4096);
        expect(repo.takeNotices().single, contains('damaged'));
        expect(
          repo.takeNotices(),
          isEmpty,
          reason: 'notices are delivered once',
        );

        await repo.saveProgress(p.withCompletion(level: 1, stars: 3, moves: 3));
        await repo.close();
        final again = repoAt(path);
        expect(
          (await again.loadProgress()).recordOf(1)!.stars,
          3,
          reason: 'the new database works normally',
        );
        expect(again.takeNotices(), isEmpty);
        await again.close();
      },
    );

    test('a second damage keeps BOTH backups', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      File(path).writeAsStringSync('garbage one');
      var r = repoAt(path);
      await r.loadProgress();
      await r.close();
      File(path).writeAsStringSync('garbage two, longer');
      r = repoAt(path);
      await r.loadProgress();
      await r.close();
      expect(File('$path.corrupt-1').readAsStringSync(), 'garbage one');
      expect(File('$path.corrupt-2').readAsStringSync(), 'garbage two, longer');
    });

    test('an empty file is just a new database, not an error', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      File(path).createSync();
      final r = repoAt(path);
      expect((await r.loadProgress()).currentLevel, 1);
      expect(r.takeNotices(), isEmpty);
      await r.close();
    });
  });

  group('importing the previous (shared_preferences) storage', () {
    final legacyProgress = jsonEncode({
      'v': 1,
      'last': 3,
      'records': {
        '1': {'stars': 3, 'bestMoves': 3},
        '2': {'stars': 2, 'bestMoves': 9},
      },
      'saved': [
        {
          'level': 3,
          'variant': 0,
          'generatorVersion': kGeneratorVersion,
          'moves': [
            [0, 2],
          ],
        },
        {
          'level': 9,
          'variant': 0,
          'generatorVersion': 0,
          'moves': [
            [0, 1],
          ],
        },
      ],
    });
    final legacySettings = jsonEncode({
      'v': 1,
      'sfx': false,
      'haptics': true,
      'speed': 'fast',
      'motion': 'on',
      'assist': 'symbols',
      'style': 'alchemy_classic',
    });

    setUp(
      () => SharedPreferences.setMockInitialValues({
        LegacyPrefs.progressKey: legacyProgress,
        LegacyPrefs.settingsKey: legacySettings,
      }),
    );

    test(
      'moves progress, saved games and settings into the database',
      () async {
        final dir = tempDir();
        final repo = repoAt(dbPathIn(dir), legacy: LegacyPrefs());
        final p = await repo.loadProgress();
        expect(p.records.keys, [1, 2]);
        expect(p.recordOf(1)!.stars, 3);
        expect(p.lastPlayedLevel, 3);
        final s = await repo.loadSettings();
        expect(s.soundEffects, isFalse);
        expect(s.speed.name, 'fast');
        expect(s.colorAssist.name, 'symbols');
        await repo.close();
      },
    );

    test(
      'a current-generation save gets its puzzle snapshot captured NOW',
      () async {
        final dir = tempDir();
        final repo = repoAt(dbPathIn(dir), legacy: LegacyPrefs());
        final g = (await repo.loadProgress()).saved[3]!;
        final lv = const LevelGenerator().generate(3);
        expect(g.hasSnapshot, isTrue);
        expect(g.originalPuzzle, lv.puzzle);
        expect(g.seed, lv.seed);
        expect(g.par, lv.solution.length);
        expect(g.moves, [const MoveModel(0, 2)]);
        await repo.close();
      },
    );

    test('a save from an older generator is kept as is (it cannot be rebuilt exactly)', () async {
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir), legacy: LegacyPrefs());
      final g = (await repo.loadProgress()).saved[9]!;
      expect(g.hasSnapshot, isFalse);
      expect(g.generatorVersion, 0);
      await repo.close();
    });

    test('the old keys are removed once the data is safe, and it never imports twice', () async {
      final dir = tempDir();
      final path = dbPathIn(dir);
      final first = repoAt(path, legacy: LegacyPrefs());
      await first.loadProgress();
      await first.close();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LegacyPrefs.progressKey), isNull);
      expect(prefs.getString(LegacyPrefs.settingsKey), isNull);

      // Stale data appears again: it must NOT overwrite the database.
      SharedPreferences.setMockInitialValues({
        LegacyPrefs.progressKey: jsonEncode({
          'records': {
            '77': {'stars': 1, 'bestMoves': 1},
          },
        }),
      });
      final second = repoAt(path, legacy: LegacyPrefs());
      final p = await second.loadProgress();
      expect(p.records.keys, [1, 2]);
      await second.close();
    });

    test(
      'damaged legacy data imports nothing and does not stop the game',
      () async {
        SharedPreferences.setMockInitialValues({
          LegacyPrefs.progressKey: '{not json',
          LegacyPrefs.settingsKey: '<<<',
        });
        final dir = tempDir();
        final repo = repoAt(dbPathIn(dir), legacy: LegacyPrefs());
        final p = await repo.loadProgress();
        expect(p.currentLevel, 1);
        expect(await repo.loadSettings(), isA<AppSettings>());
        await repo.close();
      },
    );

    test('with nothing to import it just starts fresh', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir), legacy: LegacyPrefs());
      expect((await repo.loadProgress()).currentLevel, 1);
      expect(repo.takeNotices(), isEmpty);
      await repo.close();
    });

    test('a failing legacy source never blocks start-up', () async {
      final dir = tempDir();
      final repo = repoAt(dbPathIn(dir), legacy: _ThrowingLegacy());
      final p = await repo.loadProgress();
      expect(p.currentLevel, 1);
      expect(repo.takeNotices().single, contains('could not be imported'));
      await repo.close();
    });
  });
}

class _ThrowingLegacy extends LegacyPrefs {
  @override
  Future<LegacyData> read() async => throw StateError('prefs unavailable');
}
