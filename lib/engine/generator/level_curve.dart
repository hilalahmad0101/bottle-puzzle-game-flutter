/// Hard limits that keep boards usable on small phones
/// (<= 12 bottles fits two rows of six).
const int kMaxColors = 10;
const int kMinColors = 3;
const int kEmptyBottles = 2;
const int kBottleCapacity = 4;
const int kMaxBottles = kMaxColors + kEmptyBottles;

/// Up to this many colours boards are built by reverse construction; larger
/// boards are random classic boards accepted only after solver verification
/// (reverse walks almost never end in a classic layout at that size).
const int kReverseMaxColors = 6;

/// Number of handcrafted tutorial levels (levels 1..kTutorialLevels).
const int kTutorialLevels = 5;

/// Parameters for one procedural level, derived purely from its number.
final class LevelParams {
  const LevelParams({
    required this.level,
    required this.progress,
    required this.colors,
    required this.empties,
    required this.capacity,
    required this.targetScore,
  });

  final int level;

  /// 0..1 position on the difficulty ramp.
  final double progress;
  final int colors;
  final int empties;
  final int capacity;

  /// Difficulty score candidates should be close to.
  final double targetScore;
}

/// Maps a level number to difficulty parameters: a smooth, monotone ramp
/// from level 6 to level [rampLevels]+6, then a plateau at maximum size.
/// Beyond the plateau, variety comes from different seeds, not a bigger
/// board (the board must stay phone-sized).
abstract final class LevelCurve {
  static const int rampLevels = 120;

  static LevelParams forLevel(int level) {
    final stage = level - (kTutorialLevels + 1);
    final p = stage <= 0
        ? 0.0
        : (stage >= rampLevels ? 1.0 : stage / rampLevels);
    final colors = kMinColors + (p * (kMaxColors - kMinColors + 0.99)).floor();
    return LevelParams(
      level: level,
      progress: p,
      colors: colors,
      empties: kEmptyBottles,
      capacity: kBottleCapacity,
      targetScore: 0.30 + 0.55 * p,
    );
  }
}
