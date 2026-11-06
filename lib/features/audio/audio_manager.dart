import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../progress/application/providers.dart';
import '../settings/application/settings_providers.dart';
import '../settings/domain/app_settings.dart';
import 'audio_backend.dart';
import 'audioplayers_backend.dart';

/// The one place that decides whether a sound is allowed to play.
///
///  * **Settings.** Effects follow "Sound effects", the music follows
///    "Music"; both are read at the moment of use, so a switch takes
///    effect immediately.
///  * **Latency.** Everything is preloaded once ([init]); playing is a single
///    call on an already-created player. Nothing is allocated per sound.
///  * **Lifecycle.** The music pauses when the app leaves the foreground and
///    resumes only if it is still wanted. Effects are not played in the
///    background.
///  * **Safety.** A backend failure (no audio device, a platform without
///    support) is logged once and audio turns itself off for the session; the
///    game never sees an exception.
class AudioManager {
  AudioManager(
    this._backend, {
    required this._sfxEnabled,
    required this._musicEnabled,
    DateTime Function()? clock,
    this.minGap = const Duration(milliseconds: 45),
  }) : _clock = clock ?? DateTime.now;

  final AudioBackend _backend;
  final bool Function() _sfxEnabled;
  final bool Function() _musicEnabled;
  final DateTime Function() _clock;

  /// Two requests for the same effect closer than this are one (a double
  /// tap must not machine-gun the same sound).
  final Duration minGap;

  final Map<SoundEffect, DateTime> _lastPlayed = {};
  Future<void>? _initFuture;
  bool _foreground = true;
  bool _musicStarted = false;
  bool _musicPlaying = false;
  bool _pourPlaying = false;
  bool _disposed = false;
  bool _broken = false;

  bool get isDisposed => _disposed;
  bool get isBroken => _broken;
  bool get isForeground => _foreground;
  bool get isMusicPlaying => _musicPlaying;
  bool get isPourPlaying => _pourPlaying;

  /// Loads everything once. Safe to call repeatedly.
  Future<void> init() => _initFuture ??= _guard(_backend.preload);

  /// Runs [job]; a failure is printed loudly. A failed LOAD ([fatal], the
  /// default) means there is no audio engine at all (typically the app was
  /// hot-reloaded after the audio plugin was added: stop it and run it
  /// again), so audio stays off. A single failed play does not.
  Future<void> _guard(Future<void> Function() job, {bool fatal = true}) async {
    if (_disposed || _broken) return;
    try {
      await job();
    } catch (error, stack) {
      if (fatal) {
        _broken = true;
        _musicPlaying = false;
        _pourPlaying = false;
      }
      debugPrint(
        '*** AUDIO ${fatal ? 'DISABLED' : 'problem'}: $error\n'
        'If this says MissingPluginException, fully stop the app and run it '
        'again (hot restart is not enough after adding a plugin).\n$stack',
      );
    }
  }

  /// Plays [effect] if sound effects are on and the app is in the foreground.
  void play(SoundEffect effect) {
    if (_disposed || _broken || !_foreground || !_sfxEnabled()) return;
    final now = _clock();
    final last = _lastPlayed[effect];
    if (last != null && now.difference(last) < minGap) return;
    _lastPlayed[effect] = now;
    _guard(() async {
      await init();
      if (_broken || _disposed) return;
      await _backend.playEffect(effect);
    }, fatal: false);
  }

  /// A pour starts: glass lifts, liquid runs. Ended by [stopPour].
  void startPour() {
    if (_disposed || _broken || !_foreground || !_sfxEnabled()) return;
    play(SoundEffect.glassMove);
    _pourPlaying = true;
    _guard(() async {
      await init();
      if (_broken || _disposed) return;
      await _backend.playEffect(SoundEffect.pour);
    });
  }

  /// The pour animation ended (or was interrupted): stop the liquid sound.
  void stopPour() {
    if (!_pourPlaying) return;
    _pourPlaying = false;
    _guard(() => _backend.stopEffect(SoundEffect.pour));
  }

  /// Brings the music in line with settings and lifecycle. Call whenever
  /// either changes.
  void syncMusic() {
    if (_disposed || _broken) return;
    final want = _musicEnabled() && _foreground;
    if (want && !_musicPlaying) {
      _musicPlaying = true;
      final first = !_musicStarted;
      _musicStarted = true;
      _guard(() async {
        await init();
        if (_broken || _disposed) return;
        if (first) {
          await _backend.startMusic();
        } else {
          await _backend.resumeMusic();
        }
      });
    } else if (!want && _musicPlaying) {
      _musicPlaying = false;
      _guard(_backend.pauseMusic);
    }
    if (!_sfxEnabled()) stopPour();
  }

  /// Forward `WidgetsBindingObserver.didChangeAppLifecycleState` here.
  void onLifecycle(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    if (!foreground) stopPour();
    syncMusic();
  }

  /// Releases the players. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _musicPlaying = false;
    _pourPlaying = false;
    try {
      await _backend.dispose();
    } catch (error) {
      debugPrint('Audio could not be released cleanly: $error');
    }
  }
}

final audioBackendProvider = Provider<AudioBackend>((ref) {
  final backend = AudioplayersBackend();
  ref.onDispose(backend.dispose);
  return backend;
});

/// The audio switches, safe before the saved settings have loaded (the
/// splash screen starts the audio system): defaults until then.
final audioSwitchesProvider = Provider<({bool sfx, bool music})>((ref) {
  if (!ref.watch(bootstrapProvider).hasValue) {
    const d = AppSettings();
    return (sfx: d.soundEffects, music: d.musicEnabled);
  }
  return ref.watch(
    appSettingsProvider.select(
      (s) => (sfx: s.soundEffects, music: s.musicEnabled),
    ),
  );
});

final audioManagerProvider = Provider<AudioManager>((ref) {
  final manager = AudioManager(
    ref.watch(audioBackendProvider),
    sfxEnabled: () => ref.read(audioSwitchesProvider).sfx,
    musicEnabled: () => ref.read(audioSwitchesProvider).music,
  );
  // Music follows its switch (and the start-up load of saved settings).
  ref.listen(audioSwitchesProvider, (_, _) => manager.syncMusic());
  ref.onDispose(manager.dispose);
  manager.syncMusic();
  return manager;
});
