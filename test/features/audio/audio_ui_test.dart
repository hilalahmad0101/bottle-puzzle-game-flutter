import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/audio/audio_backend.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/fake_audio.dart';
import '../../support/pump_app.dart';
import '../../support/test_app.dart';

Future<void> tapBottle(WidgetTester tester, int i) async {
  await tester.tap(find.byType(BottleView).at(i));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late FakeAudioBackend audio;

  Future<ProviderContainer> openLevel1(
    WidgetTester tester, {
    AppSettings? settings,
  }) async {
    audio = FakeAudioBackend();
    final c = await readyContainer(
      audio: audio,
      settings: settings,
      feedback: RecordingFeedback(),
    );
    addTearDown(c.dispose);
    await pumpApp(tester, c);
    await tester.tap(find.byKey(const Key('home.play')));
    await tester.pumpAndSettle();
    return c;
  }

  group('settings screen', () {
    testWidgets('the music switch starts and stops the music', (tester) async {
      audio = FakeAudioBackend();
      final c = await readyContainer(audio: audio);
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 1800),
      );
      expect(audio.calls.where((x) => x.startsWith('music')), isEmpty);
      await tester.tap(find.byKey(const Key('settings.music')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls, contains('music:start'));
      await tester.tap(find.byKey(const Key('settings.music')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls.last, 'music:pause');
      await leaveApp(tester);
    });

    testWidgets('sound, music and haptics are separate switches', (
      tester,
    ) async {
      final c = await readyContainer(audio: FakeAudioBackend());
      addTearDown(c.dispose);
      await pumpApp(
        tester,
        c,
        location: '/settings',
        size: const Size(393, 1800),
      );
      final n = c.read(appSettingsProvider.notifier);
      await tester.tap(find.byKey(const Key('settings.sfx')));
      await tester.pump();
      expect(c.read(appSettingsProvider).soundEffects, isFalse);
      expect(c.read(appSettingsProvider).haptics, isTrue);
      expect(c.read(appSettingsProvider).musicEnabled, isFalse);
      await tester.tap(find.byKey(const Key('settings.haptics')));
      await tester.pump();
      expect(c.read(appSettingsProvider).haptics, isFalse);
      expect(c.read(appSettingsProvider).soundEffects, isFalse);
      n.setMusic(true);
      await tester.pump();
      expect(c.read(appSettingsProvider).musicEnabled, isTrue);
      await leaveApp(tester);
    });
  });

  group('lifecycle', () {
    testWidgets('music pauses in the background and returns when resumed', (
      tester,
    ) async {
      await openLevel1(tester, settings: const AppSettings(musicEnabled: true));
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls, contains('music:start'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls.last, 'music:pause');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls.last, 'music:resume');
      await leaveApp(tester);
    });

    testWidgets('music that is off stays off across a background trip', (
      tester,
    ) async {
      await openLevel1(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 50));
      expect(audio.calls.where((x) => x.startsWith('music')), isEmpty);
      await leaveApp(tester);
    });

    testWidgets('leaving the app releases the audio engine', (tester) async {
      final c = await openLevel1(tester);
      c.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(audio.disposed, isTrue);
    });
  });

  group('during play', () {
    testWidgets('picking up a bottle ticks; a pour plays glass then liquid '
        'and stops with the animation', (tester) async {
      await openLevel1(tester);
      audio.calls.clear();
      await tapBottle(tester, 0);
      expect(audio.played, [SoundEffect.select]);
      audio.calls.clear();
      await tapBottle(tester, 2);
      expect(audio.played, [SoundEffect.glassMove, SoundEffect.pour]);
      expect(audio.calls, isNot(contains('stop:pour')));
      await tester.pump(const Duration(seconds: 4)); // the pour ends
      expect(audio.calls, contains('stop:pour'));
      await leaveApp(tester);
    });

    testWidgets('an impossible pour gives the soft "no" sound; an empty '
        'bottle tapped first is simply ignored', (tester) async {
      await openLevel1(tester);
      audio.calls.clear();
      await tapBottle(tester, 2); // empty: ignored, nothing to say
      expect(audio.played, isEmpty);
      await tapBottle(tester, 0); // picked up
      await tapBottle(tester, 1); // colours differ: not possible
      expect(audio.played, [SoundEffect.select, SoundEffect.invalid]);
      await leaveApp(tester);
    });

    testWidgets('winning plays the completion sound once', (tester) async {
      await openLevel1(tester);
      audio.calls.clear();
      for (final m in const [(0, 2), (1, 0), (1, 2)]) {
        await tapBottle(tester, m.$1);
        await tapBottle(tester, m.$2);
        await tester.pump(const Duration(seconds: 4));
      }
      expect(
        audio.played.where((e) => e == SoundEffect.complete),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 3));
      await leaveApp(tester);
    });

    testWidgets('with sound effects off the board is silent', (tester) async {
      await openLevel1(
        tester,
        settings: const AppSettings(soundEffects: false),
      );
      audio.calls.clear();
      await tapBottle(tester, 0);
      await tapBottle(tester, 2);
      await tester.pump(const Duration(seconds: 4));
      expect(audio.played, isEmpty);
      await leaveApp(tester);
    });

    testWidgets('pausing mid-pour stops the liquid sound', (tester) async {
      await openLevel1(tester);
      await tapBottle(tester, 0);
      await tapBottle(tester, 2);
      audio.calls.clear();
      await tester.tap(find.byKey(const Key('game.pause')));
      await tester.pumpAndSettle();
      expect(audio.calls, contains('stop:pour'));
      await tester.tap(find.byKey(const Key('pause.resume')));
      await tester.pumpAndSettle();
      await leaveApp(tester);
    });
  });
}
