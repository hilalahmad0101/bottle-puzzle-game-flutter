import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';

import '../../support/test_app.dart';

void main() {
  group('AppSettings', () {
    test('defaults', () {
      const s = AppSettings();
      expect(s.soundEffects, isTrue);
      expect(s.haptics, isTrue);
      expect(s.speed, AnimationSpeed.normal);
      expect(s.motion, MotionPreference.system);
      expect(s.colorAssist, ColorAssist.off);
      expect(s.bottleStyleId, 'alchemy_classic');
    });

    test('JSON round trip', () {
      const s = AppSettings(
        soundEffects: false,
        haptics: false,
        speed: AnimationSpeed.fast,
        motion: MotionPreference.on,
        colorAssist: ColorAssist.both,
        bottleStyleId: 'royal_glass',
      );
      expect(AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson()))), s);
    });

    test('unknown or damaged fields fall back individually', () {
      final s = AppSettings.fromJson({
        'sfx': 'yes',
        'haptics': false,
        'speed': 'warp',
        'motion': 'on',
        'assist': 42,
        'style': null,
      });
      expect(s.soundEffects, isTrue);
      expect(s.haptics, isFalse);
      expect(s.speed, AnimationSpeed.normal);
      expect(s.motion, MotionPreference.on);
      expect(s.colorAssist, ColorAssist.off);
      expect(s.bottleStyleId, 'alchemy_classic');
      expect(AppSettings.fromJson('junk'), const AppSettings());
    });

    test('derives animation settings', () {
      const s = AppSettings(
        speed: AnimationSpeed.fast,
        motion: MotionPreference.off,
      );
      expect(
        s.animation,
        const AnimationSettings(
          speed: AnimationSpeed.fast,
          motion: MotionPreference.off,
        ),
      );
    });
  });

  group('bottle unlocks', () {
    test('the free style needs nothing, others need stars', () {
      expect(BottleUnlocks.required('alchemy_classic'), 0);
      expect(BottleUnlocks.required('crystal_prism'), greaterThan(0));
      expect(
        BottleUnlocks.required('royal_glass'),
        greaterThan(BottleUnlocks.required('crystal_prism')),
      );
      expect(BottleUnlocks.isUnlocked('crystal_prism', 14), isFalse);
      expect(BottleUnlocks.isUnlocked('crystal_prism', 15), isTrue);
      expect(BottleUnlocks.required('unknown'), 0);
    });

    test('every built-in style has a unlock rule', () {
      for (final s in BottleStyles.all) {
        expect(
          BottleUnlocks.starsRequired.containsKey(s.id),
          isTrue,
          reason: s.id,
        );
      }
    });
  });

  group('providers persist every change', () {
    test('progress writes go to the repository', () async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      await c
          .read(progressProvider.notifier)
          .recordCompletion(level: 1, stars: 3, moves: 3);
      expect(c.read(progressProvider).currentLevel, 2);
      expect(repo.progress.currentLevel, 2);
      await c
          .read(progressProvider.notifier)
          .saveGame(
            SavedGame(
              level: 2,
              variant: 0,
              generatorVersion: 1,
              moves: const [],
            ),
          );
      expect(repo.progress.saved.containsKey(2), isTrue);
      await c.read(progressProvider.notifier).clearSavedGame(2);
      expect(repo.progress.saved, isEmpty);
    });

    test('unchanged values cause no write', () async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      await c.read(progressProvider.notifier).clearSavedGame(9);
      expect(repo.progressWrites, 0);
      c.read(appSettingsProvider.notifier).setHaptics(true); // already true
      expect(repo.settingsWrites, 0);
    });

    test('settings changes are saved and derived providers follow', () async {
      final repo = MemoryProgressRepository();
      final c = await readyContainer(repo: repo);
      addTearDown(c.dispose);
      final n = c.read(appSettingsProvider.notifier);
      n.setSpeed(AnimationSpeed.fast);
      n.setMotion(MotionPreference.on);
      n.setColorAssist(ColorAssist.symbols);
      n.setSoundEffects(false);
      n.setHaptics(false);
      expect(repo.settings.speed, AnimationSpeed.fast);
      expect(repo.settings.colorAssist, ColorAssist.symbols);
      expect(repo.settings.soundEffects, isFalse);
      expect(c.read(animationSettingsProvider).speed, AnimationSpeed.fast);
      expect(c.read(animationSettingsProvider).motion, MotionPreference.on);
    });

    test('start-up loads what was stored', () async {
      final c = await readyContainer(
        progress: PlayerProgress.empty.withCompletion(
          level: 1,
          stars: 3,
          moves: 3,
        ),
        settings: const AppSettings(colorAssist: ColorAssist.both),
      );
      addTearDown(c.dispose);
      expect(c.read(progressProvider).currentLevel, 2);
      expect(c.read(appSettingsProvider).colorAssist, ColorAssist.both);
    });
  });

  group('bottle style provider', () {
    test('a locked style is never shown, even if saved in settings', () async {
      final c = await readyContainer(
        settings: const AppSettings(bottleStyleId: 'royal_glass'),
      );
      addTearDown(c.dispose);
      expect(c.read(bottleStyleProvider), BottleStyles.alchemyClassic);
    });

    test('an unlocked style is used', () async {
      final progress = PlayerProgress(
        records: {
          for (var l = 1; l <= 5; l++)
            l: const LevelRecord(stars: 3, bestMoves: 5),
        },
      ); // 15 stars
      final c = await readyContainer(
        progress: progress,
        settings: const AppSettings(bottleStyleId: 'crystal_prism'),
      );
      addTearDown(c.dispose);
      expect(c.read(bottleStyleProvider), BottleStyles.crystalPrism);
    });

    test('an unknown id falls back to the default', () async {
      final c = await readyContainer(
        settings: const AppSettings(bottleStyleId: 'nope'),
      );
      addTearDown(c.dispose);
      expect(c.read(bottleStyleProvider), BottleStyles.alchemyClassic);
    });
  });
}
