import 'package:audioplayers/audioplayers.dart';

import 'audio_backend.dart';

/// The real audio engine, built on `audioplayers`.
///
/// Reuse, not recreation: one player per effect (a small round-robin pool
/// for the ones that can overlap) and one for the music, all created in
/// [preload] and kept until [dispose]. Effects use the low-latency mode;
/// the music uses the normal media mode and loops.
///
/// The audio session mixes with other apps instead of taking focus, so
/// opening the game does not cut off the player's own music or podcast.
class AudioplayersBackend implements AudioBackend {
  final Map<SoundEffect, List<AudioPlayer>> _pools = {};
  final Map<SoundEffect, int> _next = {};
  AudioPlayer? _music;
  Future<void>? _loading;
  bool _disposed = false;

  @override
  Future<void> preload() => _loading ??= _load();

  Future<void> _load() async {
    await AudioPlayer.global.setAudioContext(
      AudioContextConfig(
        focus: AudioContextConfigFocus.mixWithOthers,
        stayAwake: false,
      ).build(),
    );
    // Decode/copy every file once, before the first tap needs it.
    await AudioCache.instance.loadAll([
      for (final e in SoundEffect.values) e.asset,
      kMusicAsset,
    ]);
    for (final e in SoundEffect.values) {
      final pool = <AudioPlayer>[];
      for (var i = 0; i < e.poolSize; i++) {
        final p = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(AssetSource(e.asset));
        pool.add(p);
      }
      _pools[e] = pool;
      _next[e] = 0;
    }
    final m = AudioPlayer();
    await m.setPlayerMode(PlayerMode.mediaPlayer);
    await m.setReleaseMode(ReleaseMode.loop);
    await m.setVolume(kMusicVolume);
    await m.setSource(AssetSource(kMusicAsset));
    _music = m;
  }

  @override
  Future<void> playEffect(SoundEffect effect) async {
    final pool = _pools[effect];
    if (_disposed || pool == null) return;
    final i = _next[effect]!;
    _next[effect] = (i + 1) % pool.length;
    final p = pool[i];
    await p.stop();
    await p.play(AssetSource(effect.asset), volume: effect.volume);
  }

  @override
  Future<void> stopEffect(SoundEffect effect) async {
    if (_disposed) return;
    for (final p in _pools[effect] ?? const <AudioPlayer>[]) {
      await p.stop();
    }
  }

  @override
  Future<void> startMusic() async {
    final m = _music;
    if (_disposed || m == null) return;
    await m.play(AssetSource(kMusicAsset), volume: kMusicVolume);
  }

  @override
  Future<void> pauseMusic() async {
    if (_disposed) return;
    await _music?.pause();
  }

  @override
  Future<void> resumeMusic() async {
    if (_disposed) return;
    await _music?.resume();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final pool in _pools.values) {
      for (final p in pool) {
        await p.dispose();
      }
    }
    _pools.clear();
    await _music?.dispose();
    _music = null;
  }
}
