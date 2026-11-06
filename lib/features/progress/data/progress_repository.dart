import '../../settings/domain/app_settings.dart';
import '../domain/player_progress.dart';

/// Where progress and settings live. The game talks only to this interface.
///
/// Contract:
///  * [saveProgress] receives the LATEST complete progress; implementations
///    may coalesce several quick calls into one write (latest wins) but must
///    apply them in order and atomically.
///  * Progress that was recorded is never deleted by a later save.
///  * [flush] completes when every accepted save has been written.
abstract interface class ProgressRepository {
  Future<PlayerProgress> loadProgress();
  Future<void> saveProgress(PlayerProgress progress);
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);

  /// Waits until all accepted writes are durable (call when the app goes to
  /// the background).
  Future<void> flush();

  Future<void> close();

  /// Human-readable problems found while loading (damaged records skipped,
  /// a corrupt file backed up, ...). Returned once, then cleared.
  List<String> takeNotices();
}

/// In-memory repository for tests and previews.
class MemoryProgressRepository implements ProgressRepository {
  MemoryProgressRepository({PlayerProgress? progress, AppSettings? settings})
    : _progress = progress ?? PlayerProgress.empty,
      _settings = settings ?? const AppSettings();

  PlayerProgress _progress;
  AppSettings _settings;
  int progressWrites = 0;
  int settingsWrites = 0;
  int flushes = 0;

  PlayerProgress get progress => _progress;
  AppSettings get settings => _settings;

  @override
  Future<PlayerProgress> loadProgress() async => _progress;

  @override
  Future<void> saveProgress(PlayerProgress progress) async {
    _progress = progress;
    progressWrites++;
  }

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
    settingsWrites++;
  }

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> close() async {}

  @override
  List<String> takeNotices() => const [];
}
