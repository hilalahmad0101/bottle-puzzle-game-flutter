import 'package:prism_pour/features/audio/audio_backend.dart';

/// Records what the game asked the audio engine to do; plays nothing.
class FakeAudioBackend implements AudioBackend {
  final List<String> calls = [];
  bool failPreload = false;
  bool failPlay = false;
  bool disposed = false;
  int preloads = 0;

  List<SoundEffect> get played => [
    for (final c in calls)
      if (c.startsWith('play:'))
        SoundEffect.values.byName(c.substring('play:'.length)),
  ];

  @override
  Future<void> preload() async {
    preloads++;
    calls.add('preload');
    if (failPreload) throw StateError('no audio device');
  }

  @override
  Future<void> playEffect(SoundEffect effect) async {
    if (failPlay) throw StateError('cannot play');
    calls.add('play:${effect.name}');
  }

  @override
  Future<void> stopEffect(SoundEffect effect) async =>
      calls.add('stop:${effect.name}');

  @override
  Future<void> startMusic() async => calls.add('music:start');
  @override
  Future<void> pauseMusic() async => calls.add('music:pause');
  @override
  Future<void> resumeMusic() async => calls.add('music:resume');

  @override
  Future<void> dispose() async {
    disposed = true;
    calls.add('dispose');
  }
}
