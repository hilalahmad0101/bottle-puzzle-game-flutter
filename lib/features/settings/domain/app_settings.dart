import '../../game/animation/animation_settings.dart';
import '../../game/rendering/liquid_palette.dart';

/// Player preferences.
final class AppSettings {
  const AppSettings({
    this.soundEffects = true,
    this.haptics = true,
    this.speed = AnimationSpeed.normal,
    this.motion = MotionPreference.system,
    this.colorAssist = ColorAssist.off,
    this.bottleStyleId = 'alchemy_classic',
    this.extraBottleBooster = false,
    this.musicEnabled = false,
    this.highContrast = false,
  });

  final bool soundEffects;
  final bool haptics;
  final AnimationSpeed speed;
  final MotionPreference motion;
  final ColorAssist colorAssist;
  final String bottleStyleId;

  /// Offer the optional extra-bottle booster while playing. OFF by default;
  /// standard play is unchanged unless the player turns this on.
  final bool extraBottleBooster;

  /// Optional ambient background music. OFF until the player turns it on.
  final bool musicEnabled;

  /// Stronger outlines and calmer decoration for easier reading.
  final bool highContrast;

  AnimationSettings get animation =>
      AnimationSettings(speed: speed, motion: motion);

  AppSettings copyWith({
    bool? soundEffects,
    bool? haptics,
    AnimationSpeed? speed,
    MotionPreference? motion,
    ColorAssist? colorAssist,
    String? bottleStyleId,
    bool? extraBottleBooster,
    bool? musicEnabled,
    bool? highContrast,
  }) => AppSettings(
    soundEffects: soundEffects ?? this.soundEffects,
    haptics: haptics ?? this.haptics,
    speed: speed ?? this.speed,
    motion: motion ?? this.motion,
    colorAssist: colorAssist ?? this.colorAssist,
    bottleStyleId: bottleStyleId ?? this.bottleStyleId,
    extraBottleBooster: extraBottleBooster ?? this.extraBottleBooster,
    musicEnabled: musicEnabled ?? this.musicEnabled,
    highContrast: highContrast ?? this.highContrast,
  );

  Map<String, Object> toJson() => {
    'v': 1,
    'sfx': soundEffects,
    'haptics': haptics,
    'speed': speed.name,
    'motion': motion.name,
    'assist': colorAssist.name,
    'style': bottleStyleId,
    'booster': extraBottleBooster,
    'music': musicEnabled,
    'contrast': highContrast,
  };

  /// Unknown or damaged values fall back to defaults field by field.
  static AppSettings fromJson(Object? j) {
    if (j is! Map) return const AppSettings();
    T pick<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    const d = AppSettings();
    return AppSettings(
      soundEffects: j['sfx'] is bool ? j['sfx'] as bool : d.soundEffects,
      haptics: j['haptics'] is bool ? j['haptics'] as bool : d.haptics,
      speed: pick(AnimationSpeed.values, j['speed'], d.speed),
      motion: pick(MotionPreference.values, j['motion'], d.motion),
      colorAssist: pick(ColorAssist.values, j['assist'], d.colorAssist),
      bottleStyleId: j['style'] is String
          ? j['style'] as String
          : d.bottleStyleId,
      extraBottleBooster: j['booster'] is bool
          ? j['booster'] as bool
          : d.extraBottleBooster,
      musicEnabled: j['music'] is bool ? j['music'] as bool : d.musicEnabled,
      highContrast: j['contrast'] is bool
          ? j['contrast'] as bool
          : d.highContrast,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.soundEffects == soundEffects &&
      other.haptics == haptics &&
      other.speed == speed &&
      other.motion == motion &&
      other.colorAssist == colorAssist &&
      other.bottleStyleId == bottleStyleId &&
      other.extraBottleBooster == extraBottleBooster &&
      other.musicEnabled == musicEnabled &&
      other.highContrast == highContrast;

  @override
  int get hashCode => Object.hash(
    soundEffects,
    haptics,
    speed,
    motion,
    colorAssist,
    bottleStyleId,
    extraBottleBooster,
    musicEnabled,
    highContrast,
  );
}

/// Stars needed to unlock each bottle style (earned by playing).
abstract final class BottleUnlocks {
  static const Map<String, int> starsRequired = {
    'alchemy_classic': 0,
    'crystal_prism': 15,
    'royal_glass': 45,
    'verdant_vial': 80,
    'starlit_flask': 130,
  };

  static int required(String styleId) => starsRequired[styleId] ?? 0;
  static bool isUnlocked(String styleId, int totalStars) =>
      totalStars >= required(styleId);
}
