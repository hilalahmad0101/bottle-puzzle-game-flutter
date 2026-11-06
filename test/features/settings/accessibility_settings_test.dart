import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/sqlite_support.dart';
import '../../support/test_app.dart';

void main() {
  group('defaults', () {
    test('sound and haptics on; music, high contrast and boosters off', () {
      const s = AppSettings();
      expect(s.soundEffects, isTrue);
      expect(s.haptics, isTrue);
      expect(s.musicEnabled, isFalse, reason: 'music is optional');
      expect(s.highContrast, isFalse);
      expect(s.extraBottleBooster, isFalse);
      expect(s.colorAssist, ColorAssist.off);
      expect(s.motion, MotionPreference.system);
    });
  });

  group('serialisation', () {
    test('every accessibility switch round-trips', () {
      const s = AppSettings(
        soundEffects: false,
        haptics: false,
        musicEnabled: true,
        highContrast: true,
        colorAssist: ColorAssist.both,
        motion: MotionPreference.on,
        speed: AnimationSpeed.fast,
      );
      expect(AppSettings.fromJson(s.toJson()), s);
    });

    test('a damaged value falls back field by field, others survive', () {
      final s = AppSettings.fromJson({
        'music': 'loud',
        'contrast': 3,
        'sfx': false,
        'haptics': false,
      });
      expect(s.musicEnabled, isFalse);
      expect(s.highContrast, isFalse);
      expect(s.soundEffects, isFalse);
      expect(s.haptics, isFalse);
    });

    test('settings saved before these switches existed load with defaults', () {
      final s = AppSettings.fromJson({'sfx': true, 'haptics': true});
      expect(s.musicEnabled, isFalse);
      expect(s.highContrast, isFalse);
    });

    test('the new fields take part in equality', () {
      expect(const AppSettings(musicEnabled: true), isNot(const AppSettings()));
      expect(const AppSettings(highContrast: true), isNot(const AppSettings()));
      expect(
        const AppSettings(musicEnabled: true).hashCode,
        isNot(const AppSettings().hashCode),
      );
    });
  });

  group('the switches are independent', () {
    test('each setter changes only its own field and is saved', () async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      final n = c.read(appSettingsProvider.notifier);
      n.setMusic(true);
      expect(c.read(appSettingsProvider).musicEnabled, isTrue);
      expect(c.read(appSettingsProvider).soundEffects, isTrue);
      n.setHighContrast(true);
      expect(c.read(appSettingsProvider).highContrast, isTrue);
      expect(c.read(appSettingsProvider).musicEnabled, isTrue);
      n.setSoundEffects(false);
      expect(c.read(appSettingsProvider).musicEnabled, isTrue);
      n.setHaptics(false);
      n.setMotion(MotionPreference.on);
      n.setColorAssist(ColorAssist.symbols);
      final s = c.read(appSettingsProvider);
      expect(s.soundEffects, isFalse);
      expect(s.haptics, isFalse);
      expect(s.motion, MotionPreference.on);
      expect(s.colorAssist, ColorAssist.symbols);
      expect(s.musicEnabled, isTrue);
      expect(s.highContrast, isTrue);
    });

    test('reduced animation mode reduces motion, music is unaffected', () {
      const reduced = AnimationSettings(motion: MotionPreference.on);
      expect(reduced.isReduced(systemPrefersReduced: false), isTrue);
      const s = AppSettings(motion: MotionPreference.on, musicEnabled: true);
      expect(s.animation.isReduced(systemPrefersReduced: false), isTrue);
      expect(s.musicEnabled, isTrue);
    });

    test('highContrastProvider is false until the settings have loaded and '
        'then follows the setting', () async {
      final c = await readyContainer(
        settings: const AppSettings(highContrast: true),
      );
      addTearDown(c.dispose);
      expect(c.read(highContrastProvider), isTrue);
      c.read(appSettingsProvider.notifier).setHighContrast(false);
      expect(c.read(highContrastProvider), isFalse);
    });
  });

  group('stored on the device', () {
    test('all of them survive closing and reopening the database', () async {
      final path = dbPathIn(tempDir());
      final a = repoAt(path);
      await a.loadProgress();
      const saved = AppSettings(
        soundEffects: false,
        haptics: false,
        musicEnabled: true,
        highContrast: true,
        colorAssist: ColorAssist.patterns,
        motion: MotionPreference.on,
      );
      await a.saveSettings(saved);
      await a.close();
      final b = repoAt(path);
      await b.loadProgress();
      expect(await b.loadSettings(), saved);
      await b.close();
    });
  });
}
