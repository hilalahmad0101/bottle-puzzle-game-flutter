import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'migrations.dart';

/// Opens the game database, upgrading its schema and recovering from a
/// damaged file.
abstract final class AppDatabase {
  /// Opens [path] with [factory].
  ///
  /// A file that is not a valid database (damaged) is moved aside as
  /// `<path>.corrupt-N` (never deleted) and a fresh database is created;
  /// [onNotice] is told. Any OTHER failure (a migration error, a locked file)
  /// is rethrown untouched: it is not proof the data is bad, and wiping it
  /// would be the worst possible response.
  static Future<Database> open({
    required DatabaseFactory factory,
    required String path,
    List<Migration>? migrations,
    void Function(String)? onNotice,
  }) async {
    final steps = migrations ?? Migrations.all;
    try {
      final db = await _open(factory, path, steps);
      if (await _isHealthy(db)) return db;
      await db.close();
      throw const _Damaged('integrity check failed');
    } on _Damaged {
      return _recover(factory, path, steps, onNotice);
    } on DatabaseException catch (e) {
      if (_looksDamaged(e)) return _recover(factory, path, steps, onNotice);
      rethrow;
    }
  }

  static Future<Database> _open(
    DatabaseFactory factory,
    String path,
    List<Migration> steps,
  ) {
    final latest = steps.last.version;
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: latest,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) =>
            Migrations.run(db, 0, version, migrations: steps),
        onUpgrade: (db, from, to) =>
            Migrations.run(db, from, to, migrations: steps),
        // A database from a NEWER app: keep it and carry on. The schema is
        // additive, so every table this version needs is still there.
        onDowngrade: (db, from, to) async {},
      ),
    );
  }

  static Future<bool> _isHealthy(Database db) async {
    final rows = await db.rawQuery('PRAGMA quick_check');
    return rows.isNotEmpty && rows.first.values.first == 'ok';
  }

  static bool _looksDamaged(DatabaseException e) {
    final m = e.toString().toLowerCase();
    return m.contains('not a database') ||
        m.contains('malformed') ||
        m.contains('corrupt') ||
        m.contains('file is encrypted');
  }

  static Future<Database> _recover(
    DatabaseFactory factory,
    String path,
    List<Migration> steps,
    void Function(String)? onNotice,
  ) async {
    String? backup;
    if (path != inMemoryDatabasePath) {
      final file = File(path);
      if (await file.exists()) {
        var n = 1;
        while (await File('$path.corrupt-$n').exists()) {
          n++;
        }
        backup = '$path.corrupt-$n';
        await file.rename(backup);
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          final side = File('$path$suffix');
          if (await side.exists()) await side.delete();
        }
      }
    }
    onNotice?.call(
      backup == null
          ? 'Your saved data was damaged, so the game started fresh.'
          : 'Your saved data was damaged, so the game started fresh. The damaged file was kept as a backup.',
    );
    return _open(factory, path, steps);
  }
}

class _Damaged implements Exception {
  const _Damaged(this.reason);
  final String reason;
}
