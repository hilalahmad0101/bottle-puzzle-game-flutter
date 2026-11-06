import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/progress/data/database/migrations.dart';
import 'package:prism_pour/features/progress/data/legacy_prefs.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/features/progress/data/sqlite_progress_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite for tests: the real engine through FFI, without a background
/// isolate (so it also works inside fake-async widget tests).
DatabaseFactory get testFactory {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate;
}

/// A throwaway directory removed when the test ends.
Directory tempDir() {
  final d = Directory.systemTemp.createTempSync('prism_pour_test_');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

String dbPathIn(Directory d, [String name = 'game.db']) => '${d.path}/$name';

/// A repository on [path]. Open one per "app launch".
SqliteProgressRepository repoAt(
  String path, {
  List<Migration>? migrations,
  LegacyPrefs? legacy,
}) => SqliteProgressRepository(
  factory: testFactory,
  path: path,
  migrations: migrations,
  legacy: legacy,
);

/// Raw access to the database file, for arranging or inspecting data
/// independently of the repository.
Future<Database> rawDb(String path, {int? version}) => testFactory.openDatabase(
  path,
  options: OpenDatabaseOptions(version: version),
);

/// Lets widget tests (which run on a FAKE clock) use the real SQLite
/// repository: every database call runs in the real zone, and the test
/// waits for them with `await tester.runAsync(repo.settle)`.
///
/// Writes return immediately to the app (as a real write would not block the
/// game either); [settle] waits until they have all reached the file.
class RealZoneRepo implements ProgressRepository {
  RealZoneRepo(this.inner);

  final SqliteProgressRepository inner;
  final List<Future<void>> _inflight = [];

  Future<void> settle() async {
    while (_inflight.isNotEmpty) {
      final batch = List<Future<void>>.of(_inflight);
      _inflight.clear();
      await Future.wait(batch.map((f) => f.catchError((_) {})));
    }
    await inner.flush();
  }

  Future<void> _real(Future<void> Function() job) {
    final f = Zone.root.run(job);
    _inflight.add(f);
    return Future<void>.value();
  }

  @override
  Future<PlayerProgress> loadProgress() => inner.loadProgress();

  @override
  Future<AppSettings> loadSettings() => inner.loadSettings();

  @override
  Future<void> saveProgress(PlayerProgress progress) =>
      _real(() => inner.saveProgress(progress));

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _real(() => inner.saveSettings(settings));

  @override
  Future<void> flush() => _real(inner.flush);

  @override
  Future<void> close() => inner.close();

  @override
  List<String> takeNotices() => inner.takeNotices();
}
