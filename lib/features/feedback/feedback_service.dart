import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_backend.dart';
import '../audio/audio_manager.dart';
import '../settings/application/settings_providers.dart';

/// The raw haptic calls. Replaceable in tests. (Sound goes through the
/// [AudioManager], not through here.)
abstract interface class FeedbackPlatform {
  Future<void> selectionClick();
  Future<void> lightImpact();
  Future<void> mediumImpact();
  Future<void> heavyImpact();
}

/// Uses only Flutter's built-in services: no extra permissions. Haptics are
/// the platform vibration/taptic engine.
class SystemFeedbackPlatform implements FeedbackPlatform {
  const SystemFeedbackPlatform();

  @override
  Future<void> selectionClick() => HapticFeedback.selectionClick();
  @override
  Future<void> lightImpact() => HapticFeedback.lightImpact();
  @override
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();
  @override
  Future<void> heavyImpact() => HapticFeedback.heavyImpact();
}

/// Haptics and sound cues for gameplay events. Haptics honour the "Haptics"
/// setting here; sounds honour "Sound effects" inside the [AudioManager].
class FeedbackService {
  FeedbackService(this._platform, this._audio, this._haptics);

  final FeedbackPlatform _platform;
  final AudioManager _audio;
  final bool Function() _haptics;

  void _h(Future<void> Function() f) {
    if (_haptics()) f();
  }

  /// A bottle was picked up or put down.
  void select() {
    _h(_platform.selectionClick);
    _audio.play(SoundEffect.select);
  }

  /// A pour started (glass lifts, liquid runs until [pourEnded]).
  void pour() {
    _h(_platform.lightImpact);
    _audio.startPour();
  }

  /// The pour animation finished or was interrupted.
  void pourEnded() => _audio.stopPour();

  /// A tap that cannot be a move.
  void reject() {
    _h(_platform.heavyImpact);
    _audio.play(SoundEffect.invalid);
  }

  /// A button or switch was pressed: a light haptic and a soft glass tick.
  void button() {
    _h(_platform.selectionClick);
    _audio.play(SoundEffect.select);
  }

  /// A hint appeared.
  void hint() {
    _h(_platform.mediumImpact);
    _audio.play(SoundEffect.select);
  }

  /// The level was solved.
  void complete() {
    _h(_platform.heavyImpact);
    _audio.play(SoundEffect.complete);
  }

  /// A reward: a new bottle design or a new chapter of the journey.
  void reward() {
    _h(_platform.mediumImpact);
    _audio.play(SoundEffect.unlock);
  }
}

/// The tick for any button, switch or segment. Safe anywhere: with no
/// provider scope above (a bare widget test) it simply does nothing.
void playUiTap(BuildContext context) {
  try {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(feedbackProvider).button();
  } catch (_) {}
}

final feedbackPlatformProvider = Provider<FeedbackPlatform>(
  (ref) => const SystemFeedbackPlatform(),
);

final feedbackProvider = Provider<FeedbackService>((ref) {
  return FeedbackService(
    ref.watch(feedbackPlatformProvider),
    ref.watch(audioManagerProvider),
    () => ref.read(appSettingsProvider).haptics,
  );
});
