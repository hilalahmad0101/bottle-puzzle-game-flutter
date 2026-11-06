/// Every sound effect the game plays. Each maps to one bundled file.
enum SoundEffect {
  /// A bottle was picked up or put down: a tiny glass tink.
  select('audio/select.wav', poolSize: 2, volume: 0.9),

  /// Glass lifting/sliding as a pour begins.
  glassMove('audio/glass_move.wav', poolSize: 2),

  /// Soft liquid pouring (stopped early if the animation ends sooner).
  pour('audio/pour.wav', volume: 0.7),

  /// A tap that cannot be a move: a gentle falling pair of tones.
  invalid('audio/invalid.wav', poolSize: 2, volume: 0.8),

  /// The level was solved.
  complete('audio/complete.wav'),

  /// A new bottle design, chapter or other reward.
  unlock('audio/unlock.wav');

  const SoundEffect(this.asset, {this.poolSize = 1, this.volume = 1.0});

  /// Path relative to `assets/` (what an asset source expects).
  final String asset;

  /// How many overlapping copies may play at once. Players are created once
  /// and reused, never per play.
  final int poolSize;
  final double volume;
}

/// The looping ambient track.
const String kMusicAsset = 'audio/music_ambient.wav';
const double kMusicVolume = 0.35;

/// The few operations the game needs from an audio engine. The real one is
/// [AudioplayersBackend]; tests use a fake, so no test touches a device.
///
/// Implementations must not throw for ordinary playback failures; the
/// manager also guards against it, because a missing audio device must never
/// stop the game.
abstract interface class AudioBackend {
  /// Load every effect and the music ahead of time (decoded/cached once).
  Future<void> preload();

  Future<void> playEffect(SoundEffect effect);
  Future<void> stopEffect(SoundEffect effect);

  /// Starts the music from the top and loops it.
  Future<void> startMusic();
  Future<void> pauseMusic();
  Future<void> resumeMusic();

  /// Releases every player. The backend is unusable afterwards.
  Future<void> dispose();
}
