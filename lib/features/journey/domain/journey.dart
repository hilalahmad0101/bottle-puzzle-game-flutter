import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// The look of the laboratory at one chapter of the Alchemy Journey.
///
/// Pure data: the screens only read these colours, so adding a chapter or
/// retuning one is an edit to [Journey.chapters] and nothing else.
@immutable
final class JourneyStage {
  const JourneyStage({
    required this.id,
    required this.name,
    required this.tagline,
    required this.levels,
    required this.top,
    required this.mid,
    required this.bottom,
    required this.glowA,
    required this.glowB,
    required this.motes,
    required this.colorfulness,
  }) : assert(levels > 0);

  final String id;
  final String name;
  final String tagline;

  /// How many levels this chapter lasts.
  final int levels;

  /// The backdrop gradient, top to bottom.
  final Color top, mid, bottom;

  /// Two soft coloured glows in opposite corners.
  final Color glowA, glowB;

  /// Tints of the drifting motes of light.
  final List<Color> motes;

  /// 0 (the dark world) .. 1 (full colour). Only informational and for
  /// ordering; the palette itself carries the colour.
  final double colorfulness;

  /// The palette between [a] and [b] (for a smooth change of chapter).
  /// Identity, tagline and length are [b]'s.
  static JourneyStage lerp(JourneyStage a, JourneyStage b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return JourneyStage(
      id: b.id,
      name: b.name,
      tagline: b.tagline,
      levels: b.levels,
      top: c(a.top, b.top),
      mid: c(a.mid, b.mid),
      bottom: c(a.bottom, b.bottom),
      glowA: c(a.glowA, b.glowA),
      glowB: c(a.glowB, b.glowB),
      motes: [
        for (var i = 0; i < b.motes.length; i++)
          c(a.motes[i % a.motes.length], b.motes[i]),
      ],
      colorfulness: a.colorfulness + (b.colorfulness - a.colorfulness) * t,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JourneyStage &&
      other.id == id &&
      other.top == top &&
      other.glowA == glowA;

  @override
  int get hashCode => Object.hash(id, top, glowA);

  /// This chapter's palette turned [degrees] around the colour wheel. Used for
  /// the repeats of the journey so each lap looks new but stays in character
  /// (lightness and saturation are untouched, so the scene stays readable).
  JourneyStage shifted(double degrees) {
    if (degrees % 360 == 0) return this;
    Color rot(Color c) {
      final h = HSLColor.fromColor(c);
      return h.withHue((h.hue + degrees) % 360).toColor();
    }

    return JourneyStage(
      id: id,
      name: name,
      tagline: tagline,
      levels: levels,
      top: rot(top),
      mid: rot(mid),
      bottom: rot(bottom),
      glowA: rot(glowA),
      glowB: rot(glowB),
      motes: [for (final m in motes) rot(m)],
      colorfulness: colorfulness,
    );
  }
}

/// Where a player is on the journey.
@immutable
final class JourneyPosition {
  const JourneyPosition({
    required this.lap,
    required this.stageIndex,
    required this.stage,
    required this.doneInStage,
    required this.chapter,
  });

  /// 0 for the first time through the chapters, 1 for the second, ...
  final int lap;
  final int stageIndex;

  /// The palette to show (already hue-shifted for later laps).
  final JourneyStage stage;

  /// Levels completed within this chapter so far.
  final int doneInStage;

  /// 1-based number of the chapter overall (keeps counting across laps).
  final int chapter;

  int get levelsInStage => stage.levels;
  int get levelsToNext => stage.levels - doneInStage;
  double get stageProgress => doneInStage / stage.levels;

  /// "Midnight Lab", then "Midnight Lab II", "Midnight Lab III", ...
  String get title =>
      lap == 0 ? stage.name : '${stage.name} ${_roman(lap + 1)}';

  /// The chapter that follows this one.
  JourneyStage get nextStage =>
      Journey.chapters[(stageIndex + 1) % Journey.chapters.length];

  @override
  bool operator ==(Object other) =>
      other is JourneyPosition &&
      other.lap == lap &&
      other.stageIndex == stageIndex &&
      other.doneInStage == doneInStage;

  @override
  int get hashCode => Object.hash(lap, stageIndex, doneInStage);

  /// Roman numerals up to 3999; beyond that (a lap count no one will ever
  /// reach, but the number must still work) a plain number.
  static String _roman(int n) {
    if (n >= 4000) return '$n';
    const table = [
      (1000, 'M'),
      (900, 'CM'),
      (500, 'D'),
      (400, 'CD'),
      (100, 'C'),
      (90, 'XC'),
      (50, 'L'),
      (40, 'XL'),
      (10, 'X'),
      (9, 'IX'),
      (5, 'V'),
      (4, 'IV'),
      (1, 'I'),
    ];
    var rest = n, out = '';
    for (final (v, s) in table) {
      while (rest >= v) {
        out += s;
        rest -= v;
      }
    }
    return out;
  }
}

/// The Alchemy Journey: as levels are completed the laboratory gains colour,
/// chapter by chapter. The chapters are DATA ([chapters]); after the last one
/// the journey starts a new lap (same chapters, hue-shifted, titled with a
/// numeral), so no level number is ever "past the end".
abstract final class Journey {
  /// Degrees the palette turns per lap.
  static const double lapHueShift = 38;

  static const List<JourneyStage> chapters = [
    JourneyStage(
      id: 'midnight_lab',
      name: 'Midnight Lab',
      tagline: 'A dark world waiting for its first colour.',
      levels: 10,
      top: Color(0xFF070B1C),
      mid: Color(0xFF111738),
      bottom: Color(0xFF1D1244),
      glowA: Color(0xFF7C5CFF),
      glowB: Color(0xFF58F0FF),
      motes: [
        Color(0xFF58F0FF),
        Color(0xFFFFC25A),
        Color(0xFFFF6BE0),
        Color(0xFFFFFFFF),
      ],
      colorfulness: 0.0,
    ),
    JourneyStage(
      id: 'crystal_cavern',
      name: 'Crystal Cavern',
      tagline: 'Frozen light begins to glitter in the stone.',
      levels: 15,
      top: Color(0xFF05141F),
      mid: Color(0xFF0B3048),
      bottom: Color(0xFF124066),
      glowA: Color(0xFF58F0FF),
      glowB: Color(0xFF8AA7FF),
      motes: [
        Color(0xFF9BF6FF),
        Color(0xFFFFFFFF),
        Color(0xFF8AA7FF),
        Color(0xFFB8FFF6),
      ],
      colorfulness: 0.3,
    ),
    JourneyStage(
      id: 'enchanted_garden',
      name: 'Enchanted Garden',
      tagline: 'Green things wake and the air smells of rain.',
      levels: 25,
      top: Color(0xFF06170E),
      mid: Color(0xFF0E3A25),
      bottom: Color(0xFF1B4D2E),
      glowA: Color(0xFF5CFF9A),
      glowB: Color(0xFFF0E26A),
      motes: [
        Color(0xFF9CFFB8),
        Color(0xFFF0E26A),
        Color(0xFFFF9CD5),
        Color(0xFFFFFFFF),
      ],
      colorfulness: 0.55,
    ),
    JourneyStage(
      id: 'celestial_observatory',
      name: 'Celestial Observatory',
      tagline: 'The roof opens on a sky full of patient stars.',
      levels: 40,
      top: Color(0xFF0A0720),
      mid: Color(0xFF241257),
      bottom: Color(0xFF3B1C7A),
      glowA: Color(0xFFB04DFF),
      glowB: Color(0xFFFFD36E),
      motes: [
        Color(0xFFFFFFFF),
        Color(0xFFFFD36E),
        Color(0xFFD9B8FF),
        Color(0xFF9BC7FF),
      ],
      colorfulness: 0.8,
    ),
    JourneyStage(
      id: 'golden_laboratory',
      name: 'Golden Laboratory',
      tagline: 'Every flask glows. The world has all its colour back.',
      levels: 60,
      top: Color(0xFF1E1204),
      mid: Color(0xFF4A2E0A),
      bottom: Color(0xFF7A4A12),
      glowA: Color(0xFFFFC25A),
      glowB: Color(0xFFFFEFB8),
      motes: [
        Color(0xFFFFC25A),
        Color(0xFFFFEFB8),
        Color(0xFFFFFFFF),
        Color(0xFFFFA64D),
      ],
      colorfulness: 1.0,
    ),
  ];

  /// Levels in one full lap through [chapters].
  static final int lapLength = chapters.fold(0, (a, c) => a + c.levels);

  /// The position of a player who has completed [completedLevels] levels.
  /// O(chapters), whatever the number (64-bit safe).
  static JourneyPosition at(int completedLevels) {
    final done = completedLevels < 0 ? 0 : completedLevels;
    final lap = done ~/ lapLength;
    var rest = done % lapLength;
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      if (rest < c.levels) {
        return JourneyPosition(
          lap: lap,
          stageIndex: i,
          stage: c.shifted(lapHueShift * lap),
          doneInStage: rest,
          chapter: lap * chapters.length + i + 1,
        );
      }
      rest -= c.levels;
    }
    throw StateError('unreachable'); // rest < lapLength
  }

  /// The first chapter, for places that have no progress yet.
  static JourneyPosition get start => at(0);
}
