enum AnimationSpeed {
  normal(1.0),
  fast(0.6);

  const AnimationSpeed(this.timeScale);

  /// Multiplier on every duration (smaller = faster).
  final double timeScale;
}

/// Reduced-motion preference.
enum MotionPreference {
  /// Follow the operating system's "reduce motion" / "remove animations".
  system,
  on,
  off,
}

/// Player-facing animation settings. In-memory for now; persisted by the
/// storage module.
final class AnimationSettings {
  const AnimationSettings({
    this.speed = AnimationSpeed.normal,
    this.motion = MotionPreference.system,
  });

  final AnimationSpeed speed;
  final MotionPreference motion;

  /// Whether reduced motion applies, given the OS preference.
  bool isReduced({required bool systemPrefersReduced}) => switch (motion) {
    MotionPreference.on => true,
    MotionPreference.off => false,
    MotionPreference.system => systemPrefersReduced,
  };

  AnimationSettings copyWith({
    AnimationSpeed? speed,
    MotionPreference? motion,
  }) => AnimationSettings(
    speed: speed ?? this.speed,
    motion: motion ?? this.motion,
  );

  @override
  bool operator ==(Object other) =>
      other is AnimationSettings &&
      other.speed == speed &&
      other.motion == motion;

  @override
  int get hashCode => Object.hash(speed, motion);
}
