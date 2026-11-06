import 'dart:collection';
import 'dart:ui';

import 'bottle_geometry.dart';
import 'bottle_style.dart';
import 'glass_reflection_painter.dart';

/// The glass of one bottle recorded once as two Pictures: `back` (aura,
/// back wall) and `front` (walls, reflections, rim, ring). They depend only
/// on (style, size, capacity), never on the liquid, so replaying them is
/// far cheaper than re-issuing hundreds of gradient/blur draw calls.
final class BottleStaticLayers {
  BottleStaticLayers._(this.back, this.front);

  final Picture back;
  final Picture front;

  static BottleStaticLayers record(BottleGeometry g, BottleStyle s) {
    // Generous cull rect: glow and blur extend past the bottle box.
    final cull = Rect.fromLTWH(
      -g.size.width,
      -g.size.height * 0.1,
      g.size.width * 3,
      g.size.height * 1.2,
    );
    Picture capture(void Function(Canvas) draw) {
      final rec = PictureRecorder();
      draw(Canvas(rec, cull));
      return rec.endRecording();
    }

    return BottleStaticLayers._(
      capture((c) => GlassPainting.paintBack(c, g, s)),
      capture((c) => GlassPainting.paintFront(c, g, s)),
    );
  }
}

/// Shares recorded glass between every bottle with the same style, size and
/// capacity (a 12-bottle board records ONE set, not twelve). Small LRU.
///
/// Evicted pictures are not disposed explicitly: a painter on screen may
/// still hold one, and an un-disposed Picture is simply garbage collected.
final class BottleLayerCache {
  BottleLayerCache({this.maxEntries = 16});

  static final BottleLayerCache shared = BottleLayerCache();

  final int maxEntries;
  final LinkedHashMap<String, BottleStaticLayers> _entries = LinkedHashMap();

  /// How many times a set of layers actually had to be recorded.
  int recordCount = 0;

  int get length => _entries.length;

  BottleStaticLayers obtain(BottleStyle style, Size size, int capacity) {
    final key =
        '${style.id}|${(size.width * 2).round()}|${(size.height * 2).round()}|$capacity';
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // mark most recently used
      return hit;
    }
    final layers = BottleStaticLayers.record(
      style.geometryFor(size, capacity),
      style,
    );
    recordCount++;
    _entries[key] = layers;
    if (_entries.length > maxEntries) _entries.remove(_entries.keys.first);
    return layers;
  }

  void clear() => _entries.clear();
}
