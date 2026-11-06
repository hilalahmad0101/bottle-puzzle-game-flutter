import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/settings/application/settings_providers.dart';

import '../../support/test_app.dart';

void main() {
  group('AnimationSettings', () {
    test('defaults: normal speed, follow the system', () {
      const s = AnimationSettings();
      expect(s.speed, AnimationSpeed.normal);
      expect(s.motion, MotionPreference.system);
      expect(AnimationSpeed.normal.timeScale, 1.0);
      expect(AnimationSpeed.fast.timeScale, lessThan(1.0));
      expect(AnimationSpeed.fast.timeScale, greaterThan(0));
    });

    test('reduced motion: on / off / system matrix', () {
      for (final os in [true, false]) {
        expect(
          const AnimationSettings(motion: MotionPreference.on)
              .isReduced(systemPrefersReduced: os),
          isTrue,
        );
        expect(
          const AnimationSettings(motion: MotionPreference.off)
              .isReduced(systemPrefersReduced: os),
          isFalse,
        );
        expect(
          const AnimationSettings().isReduced(systemPrefersReduced: os),
          os,
        );
      }
    });

    test('value equality and copyWith', () {
      expect(const AnimationSettings(), const AnimationSettings());
      expect(
        const AnimationSettings().copyWith(speed: AnimationSpeed.fast),
        const AnimationSettings(speed: AnimationSpeed.fast),
      );
      expect(
        const AnimationSettings(speed: AnimationSpeed.fast).hashCode,
        const AnimationSettings(speed: AnimationSpeed.fast).hashCode,
      );
      final s = const AnimationSettings().copyWith(motion: MotionPreference.on);
      expect(s.speed, AnimationSpeed.normal);
      expect(s.motion, MotionPreference.on);
    });
  });

  group('provider', () {
    test('changing one setting keeps the other', () async {
      final c = await readyContainer();
      addTearDown(c.dispose);
      c.read(appSettingsProvider.notifier).setSpeed(AnimationSpeed.fast);
      c.read(appSettingsProvider.notifier).setMotion(MotionPreference.on);
      final s = c.read(animationSettingsProvider);
      expect(s.speed, AnimationSpeed.fast);
      expect(s.motion, MotionPreference.on);
    });
  });
}
