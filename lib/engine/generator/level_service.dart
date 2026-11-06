import 'dart:isolate';

import 'generated_level.dart';
import 'level_generator.dart';

/// Bounded memory of recently used layout fingerprints.
final class RecentLayouts {
  RecentLayouts({this.capacity = 30});

  final int capacity;
  final List<String> _items = [];

  bool contains(String fingerprint) => _items.contains(fingerprint);

  void add(String fingerprint) {
    _items.remove(fingerprint);
    _items.add(fingerprint);
    if (_items.length > capacity) _items.removeAt(0);
  }

  List<String> get items => List.unmodifiable(_items);
}

/// Generates levels off the UI thread.
///
/// Generation is already bounded, but a 12-bottle search can still take
/// hundreds of milliseconds in a debug build, so the UI should go through
/// this service. Results cross the isolate boundary as plain JSON.
class LevelService {
  const LevelService({this.generator = const LevelGenerator()});

  final LevelGenerator generator;

  Future<GeneratedLevel> generate(int level, {int variant = 0}) async {
    final gen = generator;
    final json = await Isolate.run(
      () => gen.generate(level, variant: variant).toJson(),
    );
    return GeneratedLevel.fromJson(json);
  }

  /// Canonical level (variant 0) unless its layout was seen recently; then
  /// up to [maxVariants] alternatives are tried. The returned level records
  /// its `variant`, so storing (level, variant) reproduces it exactly.
  /// The canonical level for a number never depends on history.
  ///
  /// This reduces repeats; it cannot guarantee uniqueness (low levels have
  /// few possible layouts, and fingerprints are 64-bit hashes).
  Future<GeneratedLevel> levelAvoidingRecent(
    int level, {
    required RecentLayouts recent,
    int maxVariants = 3,
  }) async {
    var chosen = await generate(level);
    for (
      var v = 1;
      v <= maxVariants && recent.contains(chosen.fingerprint);
      v++
    ) {
      if (chosen.isTutorial) break; // tutorials are fixed
      chosen = await generate(level, variant: v);
    }
    recent.add(chosen.fingerprint);
    return chosen;
  }
}
