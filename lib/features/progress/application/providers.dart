import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/domain/app_settings.dart';
import '../data/progress_repository.dart';
import '../domain/player_progress.dart';

/// The storage implementation. Overridden in `main` (and in tests).
final progressRepositoryProvider = Provider<ProgressRepository>(
  (ref) =>
      throw UnimplementedError('progressRepositoryProvider must be overridden'),
);

/// Everything loaded at start-up. The splash screen waits for it.
final class Bootstrap {
  const Bootstrap(this.progress, this.settings, [this.notices = const []]);
  final PlayerProgress progress;
  final AppSettings settings;

  /// Problems found while loading (damaged data skipped, ...), for the player.
  final List<String> notices;
}

final bootstrapProvider = FutureProvider<Bootstrap>((ref) async {
  final repo = ref.watch(progressRepositoryProvider);
  final results = await Future.wait([repo.loadProgress(), repo.loadSettings()]);
  return Bootstrap(
    results[0] as PlayerProgress,
    results[1] as AppSettings,
    repo.takeNotices(),
  );
});

/// The player's progress. Every change is written to the repository.
///
/// The in-memory state is always updated first, so the game never waits for
/// or breaks on the disk. If a write fails (disk full, ...) the error is
/// logged and the NEXT successful write includes everything, because the
/// repository diffs against what it has actually stored.
class ProgressNotifier extends Notifier<PlayerProgress> {
  @override
  PlayerProgress build() => ref.watch(bootstrapProvider).requireValue.progress;

  Future<void> _set(PlayerProgress next) async {
    if (identical(next, state)) return;
    state = next;
    try {
      await ref.read(progressRepositoryProvider).saveProgress(next);
    } catch (e, s) {
      debugPrint('Could not save progress: $e\n$s');
    }
  }

  Future<void> recordCompletion({
    required int level,
    required int stars,
    required int moves,
  }) => _set(state.withCompletion(level: level, stars: stars, moves: moves));

  Future<void> saveGame(SavedGame game) => _set(state.withSavedGame(game));

  Future<void> clearSavedGame(int level) => _set(state.withoutSavedGame(level));

  Future<void> setLastPlayed(int level) => _set(state.withLastPlayed(level));

  Future<void> recordHint(int level, {int requested = 0, int shown = 0}) =>
      _set(state.withHint(level, requested: requested, shown: shown));
}

final progressProvider = NotifierProvider<ProgressNotifier, PlayerProgress>(
  ProgressNotifier.new,
);

/// Messages found while loading saved data, shown once on the home screen.
class StartupNoticesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref
      .watch(bootstrapProvider)
      .maybeWhen(data: (b) => b.notices, orElse: () => const []);

  void dismiss() => state = const [];
}

final startupNoticesProvider =
    NotifierProvider<StartupNoticesNotifier, List<String>>(
      StartupNoticesNotifier.new,
    );
