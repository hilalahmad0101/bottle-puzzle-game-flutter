import 'package:sqflite/sqflite.dart';

/// One step of the schema's history.
///
/// Rules (so old data is never lost):
///  * a migration only ADDS (tables, columns); it never drops or rewrites
///    user data;
///  * each is idempotent (`IF NOT EXISTS`, column checks), so re-running one,
///    for instance after an app downgrade lowered the version number, is
///    harmless;
///  * the whole upgrade runs in one transaction: if any step fails, nothing
///    is applied and the old data is untouched.
final class Migration {
  const Migration(this.version, this.name, this.apply);

  final int version;
  final String name;
  final Future<void> Function(DatabaseExecutor db) apply;
}

abstract final class Migrations {
  /// Every migration, in order. The database version is the last one.
  static final List<Migration> all = [
    const Migration(1, 'core tables', _v1),
    const Migration(
      2,
      'saved-game snapshot, hint statistics, unlocked styles',
      _v2,
    ),
    const Migration(3, 'extra-bottle booster flag on saved games', _v3),
  ];

  static int get latest => all.last.version;

  /// Runs the migrations after [from] up to and including [to].
  static Future<void> run(
    DatabaseExecutor db,
    int from,
    int to, {
    List<Migration>? migrations,
  }) async {
    for (final m in migrations ?? all) {
      if (m.version > from && m.version <= to) await m.apply(db);
    }
  }

  static Future<bool> columnExists(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    return cols.any((c) => c['name'] == column);
  }

  static Future<void> addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    if (!await columnExists(db, table, column)) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }
}

/// Version 1: progress, settings and moves-only saved games.
Future<void> _v1(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS completed_levels (
      level INTEGER PRIMARY KEY NOT NULL CHECK (level >= 1),
      stars INTEGER NOT NULL CHECK (stars BETWEEN 1 AND 3),
      best_moves INTEGER NOT NULL CHECK (best_moves >= 1),
      completions INTEGER NOT NULL DEFAULT 1 CHECK (completions >= 1)
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS saved_games (
      level INTEGER PRIMARY KEY NOT NULL CHECK (level >= 1),
      variant INTEGER NOT NULL,
      generator_version INTEGER NOT NULL,
      moves TEXT NOT NULL,
      saved_order INTEGER NOT NULL DEFAULT 0
    )''');
}

/// Version 2: a saved game now carries the ORIGINAL puzzle (so a generator
/// change can never alter it), plus hint statistics and unlocked styles.
Future<void> _v2(DatabaseExecutor db) async {
  for (final (column, type) in const [
    ('seed', 'INTEGER'),
    ('original_state', 'TEXT'),
    ('current_state', 'TEXT'),
    ('move_count', 'INTEGER'),
    ('difficulty', 'INTEGER'),
    ('par', 'INTEGER'),
    ('fingerprint', 'TEXT'),
  ]) {
    await Migrations.addColumnIfMissing(db, 'saved_games', column, type);
  }
  await db.execute('''
    CREATE TABLE IF NOT EXISTS hint_stats (
      level INTEGER PRIMARY KEY NOT NULL CHECK (level >= 1),
      requested INTEGER NOT NULL DEFAULT 0 CHECK (requested >= 0),
      shown INTEGER NOT NULL DEFAULT 0 CHECK (shown >= 0)
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS unlocked_styles (
      style_id TEXT PRIMARY KEY NOT NULL
    )''');
}

/// Version 3: a saved game remembers whether the optional extra-bottle
/// booster was used (0 = standard, the default for every existing row).
Future<void> _v3(DatabaseExecutor db) async {
  await Migrations.addColumnIfMissing(
    db,
    'saved_games',
    'booster',
    'INTEGER NOT NULL DEFAULT 0',
  );
}
