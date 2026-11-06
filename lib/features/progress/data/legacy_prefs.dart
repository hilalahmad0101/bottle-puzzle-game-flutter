import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../settings/domain/app_settings.dart';
import '../domain/player_progress.dart';

/// Data written by the previous storage (JSON in `shared_preferences`).
final class LegacyData {
  const LegacyData(this.progress, this.settings);

  final PlayerProgress progress;
  final AppSettings? settings;

  bool get isEmpty =>
      progress.records.isEmpty && progress.saved.isEmpty && settings == null;
}

/// Reads (and afterwards removes) the pre-SQLite save data. It exists only
/// so players who already have progress keep it when the game moves to
/// SQLite; nothing writes to these keys any more.
class LegacyPrefs {
  LegacyPrefs([SharedPreferences? prefs]) : _prefs = prefs;

  static const progressKey = 'prismpour.progress.v1';
  static const settingsKey = 'prismpour.settings.v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  Object? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<LegacyData> read() async {
    final p = await _p;
    final progressRaw = p.getString(progressKey);
    final settingsRaw = p.getString(settingsKey);
    return LegacyData(
      PlayerProgress.fromJson(_decode(progressRaw)),
      settingsRaw == null ? null : AppSettings.fromJson(_decode(settingsRaw)),
    );
  }

  /// Called only after the data is safely in the database.
  Future<void> clear() async {
    final p = await _p;
    await p.remove(progressKey);
    await p.remove(settingsKey);
  }
}
