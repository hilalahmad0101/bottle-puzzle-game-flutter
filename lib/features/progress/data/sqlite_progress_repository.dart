import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../engine/generator/generator_version.dart';
import '../../../engine/generator/level_generator.dart';
import '../../../engine/models/move_model.dart';
import '../../../engine/models/puzzle_codec.dart';
import '../../../engine/models/puzzle_state.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/player_progress.dart';
import 'database/app_database.dart';
import 'database/migrations.dart';
import 'legacy_prefs.dart';
import 'progress_repository.dart';

/// Durable storage in SQLite.
///
///  * Every write is ONE transaction: a completion (the level record, the
///    saved game's removal, unlocked styles) lands all together or not at all.
///  * Only what changed is written (the repository diffs against what it last
///    loaded or wrote), so saving after every move is a few small rows.
///  * Quick successive saves are coalesced (the latest wins) and applied in
///    order on a single queue.
///  * Recorded progress is never deleted by a save; only a finished or
///    abandoned saved game is removed.
///  * Loading tolerates damaged rows: each bad row is skipped (and reported
///    through [takeNotices]) without affecting the rest.
class SqliteProgressRepository implements ProgressRepository {
  SqliteProgressRepository({
    DatabaseFactory? factory,
    this.path,
    this.migrations,
    this.legacy,
  }) : _factory = factory ?? databaseFactory;

  /// Database file. Defaults to `prism_pour.db` in the platform databases
  /// directory. Use [inMemoryDatabasePath] for throwaway databases.
  final String? path;
  final List<Migration>? migrations;
  final DatabaseFactory _factory;

  /// Where to import pre-database data from (null = nothing to import).
  final LegacyPrefs? legacy;

  Future<Database>? _dbFuture;
  PlayerProgress _last = PlayerProgress.empty;
  final List<String> _notices = [];

  Future<void> _tail = Future.value();
  PlayerProgress? _pending;

  Future<Database> get database =>
      _dbFuture ??= _openAndInit().catchError((Object e, StackTrace s) {
        _dbFuture = null; // allow a retry
        throw e;
      });

  Future<Database> _openAndInit() async {
    final location = path ?? p.join(await getDatabasesPath(), 'prism_pour.db');
    final db = await AppDatabase.open(
      factory: _factory,
      path: location,
      migrations: migrations,
      onNotice: _notices.add,
    );
    try {
      await _importLegacy(db);
    } catch (e, s) {
      // Importing old data must never stop the game from starting.
      debugPrint('Legacy import failed: $e\n$s');
      _notices.add('Some earlier progress could not be imported.');
    }
    return db;
  }

  @override
  List<String> takeNotices() {
    final out = List<String>.of(_notices);
    _notices.clear();
    return out;
  }

  // ---------------------------------------------------------------- reading

  @override
  Future<PlayerProgress> loadProgress() async {
    final db = await database;
    var skipped = 0;

    final records = <int, LevelRecord>{};
    for (final r in await db.query('completed_levels')) {
      final level = r['level'], stars = r['stars'], moves = r['best_moves'];
      final done = r['completions'];
      final rec = (level is int && level >= 1)
          ? LevelRecord.fromJson({
              'stars': stars,
              'bestMoves': moves,
              'completions': done,
            })
          : null;
      if (rec == null) {
        skipped++;
      } else {
        records[level as int] = rec;
      }
    }

    final saved = <int, SavedGame>{};
    final badSaves = <int>[];
    for (final r in await db.query(
      'saved_games',
      orderBy: 'saved_order ASC, level ASC',
    )) {
      final game = _decodeGame(r, (note) => _notices.add(note));
      final level = r['level'];
      if (game == null) {
        skipped++;
        if (level is int) badSaves.add(level);
      } else if (!records.containsKey(game.level)) {
        saved[game.level] = game;
      }
    }
    // An unreadable saved game can never be restored; remove it so it does
    // not linger (completed levels and everything else stay untouched).
    for (final level in badSaves) {
      await db.delete('saved_games', where: 'level = ?', whereArgs: [level]);
    }

    final hints = <int, HintStat>{};
    for (final r in await db.query('hint_stats')) {
      final level = r['level'], req = r['requested'], shown = r['shown'];
      if (level is int &&
          level >= 1 &&
          req is int &&
          shown is int &&
          req >= 0 &&
          shown >= 0) {
        hints[level] = HintStat(requested: req, shown: shown);
      } else {
        skipped++;
      }
    }

    final unlocked = <String>{
      for (final r in await db.query('unlocked_styles'))
        if (r['style_id'] is String) r['style_id'] as String,
    };

    int? lastPlayed;
    final meta = await _meta(db, 'last_played');
    if (meta != null) {
      final v = int.tryParse(meta);
      if (v != null && v >= 1) lastPlayed = v;
    }

    if (skipped > 0) {
      _notices.add(
        skipped == 1
            ? 'One damaged saved record was skipped.'
            : '$skipped damaged saved records were skipped.',
      );
    }

    final loaded = PlayerProgress(
      records: records,
      saved: saved,
      hints: hints,
      unlockedStyles: unlocked,
      lastPlayedLevel: lastPlayed,
    );
    _last = loaded; // what the database holds: later saves are diffs of this
    return loaded.normalized();
  }

  SavedGame? _decodeGame(Map<String, Object?> r, void Function(String) note) {
    final level = r['level'],
        variant = r['variant'],
        version = r['generator_version'];
    final rawMoves = r['moves'];
    if (level is! int ||
        level < 1 ||
        variant is! int ||
        version is! int ||
        rawMoves is! String) {
      return null;
    }
    final List<MoveModel> moves;
    try {
      moves = PuzzleCodec.decodeMoves(jsonDecode(rawMoves));
    } on FormatException {
      return null;
    }

    PuzzleState? decode(Object? raw) {
      if (raw is! String) return null;
      try {
        return PuzzleCodec.decode(jsonDecode(raw));
      } on FormatException {
        return null;
      }
    }

    final original = decode(r['original_state']);
    final current = decode(r['current_state']);
    if (r['original_state'] != null && original == null) {
      // The snapshot is damaged but the moves are fine: keep the game; the
      // session regenerates the level if (and only if) the generator version
      // still matches.
      note('A saved puzzle snapshot was damaged; its level will be rebuilt.');
    }
    final difficulty = r['difficulty'];
    final par = r['par'];
    final seed = r['seed'];
    return SavedGame(
      level: level,
      variant: variant,
      generatorVersion: version,
      moves: moves,
      seed: seed is int ? seed : null,
      originalPuzzle: original,
      currentPuzzle: original == null ? null : current,
      difficultyIndex: difficulty is int && difficulty >= 0 && difficulty <= 3
          ? difficulty
          : null,
      par: par is int && par >= 1 ? par : null,
      fingerprint: r['fingerprint'] is String
          ? r['fingerprint'] as String
          : null,
      boosted: r['booster'] == 1,
    );
  }

  @override
  Future<AppSettings> loadSettings() async {
    final db = await database;
    final map = <String, Object?>{};
    for (final r in await db.query('settings')) {
      final key = r['key'], value = r['value'];
      if (key is! String || value is! String) continue;
      try {
        map[key] = jsonDecode(value);
      } on FormatException {
        // this setting falls back to its default
      }
    }
    return AppSettings.fromJson(map);
  }

  // ---------------------------------------------------------------- writing

  Future<void> _serial(Future<void> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  @override
  Future<void> saveProgress(PlayerProgress progress) {
    _pending = progress; // the latest wins
    return _serial(() async {
      final next = _pending;
      if (next == null) return; // already written by an earlier job
      _pending = null;
      try {
        final db = await database;
        await db.transaction((txn) => _applyDiff(txn, _last, next));
        _last = next;
      } catch (_) {
        _pending ??= next; // keep it for the next attempt (or flush)
        rethrow;
      }
    });
  }

  @override
  Future<void> saveSettings(AppSettings settings) => _serial(() async {
    final db = await database;
    await db.transaction((txn) => _writeSettings(txn, settings));
  });

  @override
  Future<void> flush() async {
    await _serial(() async {
      final next = _pending;
      if (next == null) return;
      _pending = null;
      try {
        final db = await database;
        await db.transaction((txn) => _applyDiff(txn, _last, next));
        _last = next;
      } catch (_) {
        _pending ??= next;
        rethrow;
      }
    });
  }

  @override
  Future<void> close() async {
    try {
      await flush();
    } finally {
      final f = _dbFuture;
      _dbFuture = null;
      if (f != null) await (await f).close();
    }
  }

  /// Writes the difference between [last] and [next]. Runs inside a
  /// transaction supplied by the caller.
  static Future<void> _applyDiff(
    DatabaseExecutor txn,
    PlayerProgress last,
    PlayerProgress next,
  ) async {
    final batch = txn.batch();

    // Completed levels only ever grow: a save can add or improve a record
    // but never delete one.
    for (final e in next.records.entries) {
      if (last.records[e.key] != e.value) {
        batch.insert('completed_levels', {
          'level': e.key,
          'stars': e.value.stars,
          'best_moves': e.value.bestMoves,
          'completions': e.value.completions,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    for (final level in last.saved.keys) {
      if (!next.saved.containsKey(level)) {
        batch.delete('saved_games', where: 'level = ?', whereArgs: [level]);
      }
    }
    var order = 0;
    for (final g in next.saved.values) {
      if (last.saved[g.level] != g) {
        batch.insert(
          'saved_games',
          _gameRow(g, order),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        batch.update(
          'saved_games',
          {'saved_order': order},
          where: 'level = ?',
          whereArgs: [g.level],
        );
      }
      order++;
    }

    for (final e in next.hints.entries) {
      if (last.hints[e.key] != e.value) {
        batch.insert('hint_stats', {
          'level': e.key,
          'requested': e.value.requested,
          'shown': e.value.shown,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    for (final id in next.unlockedStyles) {
      if (!last.unlockedStyles.contains(id)) {
        batch.insert('unlocked_styles', {
          'style_id': id,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }

    if (next.lastPlayedLevel != last.lastPlayedLevel &&
        next.lastPlayedLevel != null) {
      batch.insert('meta', {
        'key': 'last_played',
        'value': '${next.lastPlayedLevel}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  static Map<String, Object?> _gameRow(SavedGame g, int order) => {
    'level': g.level,
    'variant': g.variant,
    'generator_version': g.generatorVersion,
    'moves': jsonEncode(PuzzleCodec.encodeMoves(g.moves)),
    'saved_order': order,
    'seed': g.seed,
    'original_state': g.originalPuzzle == null
        ? null
        : jsonEncode(PuzzleCodec.encode(g.originalPuzzle!)),
    'current_state': g.currentPuzzle == null
        ? null
        : jsonEncode(PuzzleCodec.encode(g.currentPuzzle!)),
    'move_count': g.moves.length,
    'difficulty': g.difficultyIndex,
    'par': g.par,
    'fingerprint': g.fingerprint,
    'booster': g.boosted ? 1 : 0,
  };

  static Future<void> _writeSettings(
    DatabaseExecutor txn,
    AppSettings s,
  ) async {
    final batch = txn.batch();
    for (final e in s.toJson().entries) {
      if (e.key == 'v') continue;
      batch.insert('settings', {
        'key': e.key,
        'value': jsonEncode(e.value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> _meta(DatabaseExecutor db, String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  // ---------------------------------------------------------- legacy import

  /// One-time move of the old `shared_preferences` data into the database.
  /// Saved games from the old format only had level + moves; where the level
  /// can still be regenerated exactly (same generator version) its puzzle is
  /// captured NOW, so from here on it is protected against generator changes.
  Future<void> _importLegacy(Database db) async {
    final source = legacy;
    if (source == null) return;
    if (await _meta(db, 'legacy_import') != null) return;

    final data = await source.read();
    await db.transaction((txn) async {
      if (!data.isEmpty) {
        final progress = _withSnapshots(data.progress).normalized();
        await _applyDiff(txn, PlayerProgress.empty, progress);
        if (data.settings != null) await _writeSettings(txn, data.settings!);
      }
      await txn.insert('meta', {
        'key': 'legacy_import',
        'value': 'done',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await source.clear(); // only after the data is safely stored
  }

  static PlayerProgress _withSnapshots(PlayerProgress legacy) {
    var progress = legacy;
    for (final g in legacy.saved.values) {
      if (g.hasSnapshot || g.generatorVersion != kGeneratorVersion) continue;
      try {
        final lv = const LevelGenerator().generate(g.level, variant: g.variant);
        progress = progress.withSavedGame(
          SavedGame(
            level: g.level,
            variant: g.variant,
            generatorVersion: g.generatorVersion,
            moves: g.moves,
            seed: lv.seed,
            originalPuzzle: lv.puzzle,
            difficultyIndex: lv.difficulty.index,
            par: lv.solution.length,
            fingerprint: lv.fingerprint,
          ),
        );
      } catch (_) {
        // keep the legacy row as it is
      }
    }
    // Preserve the player's last-played pointer (withSavedGame moves it).
    return legacy.lastPlayedLevel == null
        ? progress
        : progress.withLastPlayed(legacy.lastPlayedLevel!);
  }
}
