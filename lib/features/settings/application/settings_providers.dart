import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../game/animation/animation_settings.dart';
import '../../game/rendering/bottle_style.dart';
import '../../game/rendering/liquid_palette.dart';
import '../../progress/application/providers.dart';
import '../domain/app_settings.dart';

/// Player preferences; every change is persisted.
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(bootstrapProvider).requireValue.settings;

  void _set(AppSettings next) {
    if (next == state) return;
    state = next;
    ref.read(progressRepositoryProvider).saveSettings(next).catchError((
      Object e,
    ) {
      debugPrint('Could not save settings: $e');
    });
  }

  void setSoundEffects(bool v) => _set(state.copyWith(soundEffects: v));
  void setHaptics(bool v) => _set(state.copyWith(haptics: v));
  void setSpeed(AnimationSpeed v) => _set(state.copyWith(speed: v));
  void setMotion(MotionPreference v) => _set(state.copyWith(motion: v));
  void setColorAssist(ColorAssist v) => _set(state.copyWith(colorAssist: v));
  void setMusic(bool v) => _set(state.copyWith(musicEnabled: v));
  void setHighContrast(bool v) => _set(state.copyWith(highContrast: v));
  void setExtraBottleBooster(bool v) =>
      _set(state.copyWith(extraBottleBooster: v));
  void setBottleStyle(String id) => _set(state.copyWith(bottleStyleId: id));
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

/// Animation preferences derived from the single source of truth.
///
/// Safe on the splash screen: until the saved settings have loaded it returns
/// the defaults instead of throwing, so decorative widgets can ask for it
/// from the very first frame.
final animationSettingsProvider = Provider<AnimationSettings>((ref) {
  if (!ref.watch(bootstrapProvider).hasValue) return const AnimationSettings();
  return ref.watch(appSettingsProvider).animation;
});

/// High-contrast mode. Safe on the splash screen like
/// [animationSettingsProvider]: off until the saved settings have loaded.
final highContrastProvider = Provider<bool>((ref) {
  if (!ref.watch(bootstrapProvider).hasValue) return false;
  return ref.watch(appSettingsProvider.select((s) => s.highContrast));
});

/// The bottle style in use. An unknown or still-locked style falls back to
/// the free default, so a damaged or tampered setting can never show a
/// style the player has not unlocked.
final bottleStyleProvider = Provider<BottleStyle>((ref) {
  final id = ref.watch(appSettingsProvider).bottleStyleId;
  final progress = ref.watch(progressProvider);
  for (final s in BottleStyles.all) {
    if (s.id == id && progress.isStyleUnlocked(s.id)) return s;
  }
  return BottleStyles.alchemyClassic;
});
