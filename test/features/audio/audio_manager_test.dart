import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/audio/audio_backend.dart';
import 'package:prism_pour/features/audio/audio_manager.dart';
import 'package:prism_pour/features/feedback/feedback_service.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/fake_audio.dart';
import '../../support/test_app.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioBackend backend;
  late bool sfx;
  late bool music;
  late DateTime now;

  AudioManager make({Duration minGap = const Duration(milliseconds: 45)}) =>
      AudioManager(
        backend,
        sfxEnabled: () => sfx,
        musicEnabled: () => music,
        clock: () => now,
        minGap: minGap,
      );

  setUp(() {
    backend = FakeAudioBackend();
    sfx = true;
    music = false;
    now = DateTime(2026, 1, 1);
  });

  group('sound effects', () {
    test('every effect reaches the engine', () async {
      final m = make(minGap: Duration.zero);
      for (final e in SoundEffect.values) {
        m.play(e);
      }
      await settle();
      expect(backend.played, SoundEffect.values);
    });

    test(
      'are silent when "Sound effects" is off, read at the moment of use',
      () async {
        final m = make();
        sfx = false;
        m.play(SoundEffect.select);
        await settle();
        expect(backend.played, isEmpty);
        sfx = true;
        m.play(SoundEffect.select);
        await settle();
        expect(backend.played, [SoundEffect.select]);
      },
    );

    test(
      'a burst of the same effect is one sound; others are unaffected',
      () async {
        final m = make();
        m.play(SoundEffect.select);
        m.play(SoundEffect.select);
        m.play(SoundEffect.invalid);
        await settle();
        expect(backend.played, [SoundEffect.select, SoundEffect.invalid]);
        now = now.add(const Duration(milliseconds: 60));
        m.play(SoundEffect.select);
        await settle();
        expect(backend.played.last, SoundEffect.select);
        expect(backend.played, hasLength(3));
      },
    );

    test('everything is loaded ONCE, however many sounds play', () async {
      final m = make(minGap: Duration.zero);
      for (var i = 0; i < 25; i++) {
        m.play(SoundEffect.values[i % SoundEffect.values.length]);
      }
      await m.init();
      await m.init();
      await settle();
      expect(backend.preloads, 1, reason: 'players are reused, not recreated');
    });

    test('nothing plays while the app is in the background', () async {
      final m = make();
      m.onLifecycle(AppLifecycleState.paused);
      m.play(SoundEffect.complete);
      await settle();
      expect(backend.played, isEmpty);
      m.onLifecycle(AppLifecycleState.resumed);
      m.play(SoundEffect.complete);
      await settle();
      expect(backend.played, [SoundEffect.complete]);
    });
  });

  group('pouring', () {
    test('plays the glass movement, then liquid until stopped', () async {
      final m = make();
      m.startPour();
      await settle();
      expect(backend.played, [SoundEffect.glassMove, SoundEffect.pour]);
      expect(m.isPourPlaying, isTrue);
      m.stopPour();
      await settle();
      expect(backend.calls, contains('stop:pour'));
      expect(m.isPourPlaying, isFalse);
    });

    test('stopping with nothing pouring does nothing', () async {
      final m = make();
      m.stopPour();
      await settle();
      expect(backend.calls.where((c) => c.startsWith('stop')), isEmpty);
    });

    test('a pour is silent with sound effects off', () async {
      sfx = false;
      final m = make();
      m.startPour();
      await settle();
      expect(backend.played, isEmpty);
      expect(m.isPourPlaying, isFalse);
    });

    test('backgrounding cuts the liquid sound', () async {
      final m = make();
      m.startPour();
      await settle();
      m.onLifecycle(AppLifecycleState.inactive);
      await settle();
      expect(backend.calls, contains('stop:pour'));
    });

    test('turning sound off mid-pour stops it', () async {
      final m = make();
      m.startPour();
      await settle();
      sfx = false;
      m.syncMusic();
      await settle();
      expect(backend.calls, contains('stop:pour'));
    });
  });

  group('music', () {
    test('is off by default: nothing starts', () async {
      final m = make();
      m.syncMusic();
      await settle();
      expect(backend.calls.where((c) => c.startsWith('music')), isEmpty);
      expect(m.isMusicPlaying, isFalse);
    });

    test(
      'starts when switched on, pauses when switched off, then resumes',
      () async {
        final m = make();
        music = true;
        m.syncMusic();
        await settle();
        expect(backend.calls.where((c) => c.startsWith('music')), [
          'music:start',
        ]);
        music = false;
        m.syncMusic();
        await settle();
        music = true;
        m.syncMusic();
        await settle();
        expect(backend.calls.where((c) => c.startsWith('music')), [
          'music:start',
          'music:pause',
          'music:resume',
        ]);
      },
    );

    test('syncing twice does not restart it', () async {
      final m = make();
      music = true;
      m.syncMusic();
      m.syncMusic();
      m.syncMusic();
      await settle();
      expect(backend.calls.where((c) => c == 'music:start'), hasLength(1));
    });

    test('pauses in the background and resumes only if still wanted', () async {
      final m = make();
      music = true;
      m.syncMusic();
      await settle();
      m.onLifecycle(AppLifecycleState.paused);
      await settle();
      expect(m.isMusicPlaying, isFalse);
      expect(backend.calls.last, 'music:pause');
      m.onLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(backend.calls.last, 'music:resume');

      m.onLifecycle(AppLifecycleState.paused);
      music = false; // switched off while away
      m.onLifecycle(AppLifecycleState.resumed);
      await settle();
      expect(m.isMusicPlaying, isFalse, reason: 'it must stay off');
    });

    test('repeated identical lifecycle events change nothing', () async {
      final m = make();
      music = true;
      m.syncMusic();
      await settle();
      m.onLifecycle(AppLifecycleState.paused);
      m.onLifecycle(AppLifecycleState.hidden);
      m.onLifecycle(AppLifecycleState.paused);
      await settle();
      expect(backend.calls.where((c) => c == 'music:pause'), hasLength(1));
    });
  });

  group('safety', () {
    test('a failing audio device never throws and turns audio off', () async {
      backend.failPreload = true;
      final m = make();
      m.play(SoundEffect.select);
      await settle();
      expect(m.isBroken, isTrue);
      expect(() => m.play(SoundEffect.select), returnsNormally);
      music = true;
      expect(m.syncMusic, returnsNormally);
      m.startPour();
      await settle();
      expect(backend.played, isEmpty);
    });

    test(
      'one failing play is contained and does not silence the rest',
      () async {
        backend.failPlay = true;
        final m = make(minGap: Duration.zero);
        m.play(SoundEffect.select);
        await settle();
        expect(m.isBroken, isFalse);
        backend.failPlay = false;
        m.play(SoundEffect.select);
        await settle();
        expect(backend.played, [SoundEffect.select]);
      },
    );

    test(
      'dispose releases the backend once, and nothing plays afterwards',
      () async {
        final m = make();
        music = true;
        m.syncMusic();
        await settle();
        await m.dispose();
        await m.dispose();
        expect(backend.calls.where((c) => c == 'dispose'), hasLength(1));
        expect(m.isDisposed, isTrue);
        final before = backend.calls.length;
        m.play(SoundEffect.select);
        m.syncMusic();
        m.startPour();
        m.onLifecycle(AppLifecycleState.resumed);
        await settle();
        expect(backend.calls.length, before);
      },
    );
  });

  group('wired to the settings', () {
    test('the music switch starts and pauses the real manager', () async {
      final c = await readyContainer(audio: backend);
      addTearDown(c.dispose);
      c.read(audioManagerProvider);
      await settle();
      expect(backend.calls.where((x) => x.startsWith('music')), isEmpty);
      c.read(appSettingsProvider.notifier).setMusic(true);
      // Listeners run when the provider is next evaluated (in the app a frame
      // does this; see the widget test in audio_ui_test.dart).
      c.read(audioSwitchesProvider);
      await settle();
      expect(backend.calls, contains('music:start'));
      c.read(appSettingsProvider.notifier).setMusic(false);
      c.read(audioSwitchesProvider);
      await settle();
      expect(backend.calls.last, 'music:pause');
    });

    test(
      'music saved as ON starts as soon as the settings have loaded',
      () async {
        final c = await readyContainer(
          audio: backend,
          settings: const AppSettings(musicEnabled: true),
        );
        addTearDown(c.dispose);
        c.read(audioManagerProvider);
        await settle();
        expect(backend.calls, contains('music:start'));
      },
    );

    test('disposing the app disposes the audio engine', () async {
      final c = await readyContainer(audio: backend);
      c.read(audioManagerProvider);
      c.dispose();
      await settle();
      expect(backend.disposed, isTrue);
    });

    test('the sound switch silences effects at once', () async {
      final c = await readyContainer(audio: backend);
      addTearDown(c.dispose);
      final audio = c.read(audioManagerProvider);
      c.read(appSettingsProvider.notifier).setSoundEffects(false);
      audio.play(SoundEffect.complete);
      await settle();
      expect(backend.played, isEmpty);
      c.read(appSettingsProvider.notifier).setSoundEffects(true);
      audio.play(SoundEffect.complete);
      await settle();
      expect(backend.played, [SoundEffect.complete]);
    });
  });

  group('feedback service (haptics + sound together)', () {
    late RecordingFeedback haptics;
    late ProviderContainer c;

    Future<FeedbackService> setUpFeedback({AppSettings? settings}) async {
      haptics = RecordingFeedback();
      c = await readyContainer(
        audio: backend,
        feedback: haptics,
        settings: settings,
      );
      addTearDown(c.dispose);
      return c.read(feedbackProvider);
    }

    test('each cue maps to its own haptic and sound', () async {
      final f = await setUpFeedback();
      final cases = <(void Function(), String?, SoundEffect?)>[
        (f.select, 'selectionClick', SoundEffect.select),
        (f.reject, 'heavy', SoundEffect.invalid),
        (f.complete, 'heavy', SoundEffect.complete),
        (f.reward, 'medium', SoundEffect.unlock),
        (f.hint, 'medium', SoundEffect.select),
        (f.button, 'selectionClick', SoundEffect.select),
      ];
      for (final (cue, haptic, sound) in cases) {
        haptics.calls.clear();
        backend.calls.clear();
        now = now.add(const Duration(seconds: 1));
        cue();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(haptics.calls, [haptic]);
        expect(backend.played, [?sound]);
      }
    });

    test('haptics and sound switch off independently', () async {
      final f = await setUpFeedback(
        settings: const AppSettings(haptics: false),
      );
      f.reject();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(haptics.calls, isEmpty);
      expect(backend.played, [SoundEffect.invalid]);

      c.read(appSettingsProvider.notifier)
        ..setHaptics(true)
        ..setSoundEffects(false);
      haptics.calls.clear();
      backend.calls.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      f.reject();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(haptics.calls, ['heavy']);
      expect(backend.played, isEmpty);
    });

    test('a pour starts and ends the liquid sound', () async {
      final f = await setUpFeedback();
      f.pour();
      await settle();
      expect(backend.played, [SoundEffect.glassMove, SoundEffect.pour]);
      f.pourEnded();
      await settle();
      expect(backend.calls, contains('stop:pour'));
    });
  });
}
