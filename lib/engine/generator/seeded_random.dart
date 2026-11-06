const int _m32 = 0xFFFFFFFF;

/// 32-bit integer multiply that is exact on every Dart platform.
int _imul(int a, int b) {
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & _m32;
}

/// Deterministic PRNG (mulberry32). Implemented here on purpose:
/// `dart:math` Random does not promise the same sequence across SDK
/// versions, which would silently change every level.
final class SeededRandom {
  SeededRandom(int seed) : _state = seed & _m32;

  int _state;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _m32;
    var t = _imul(_state ^ (_state >> 15), _state | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & _m32;
    return (t ^ (t >> 14)) & _m32;
  }

  /// Uniform-ish integer in [0, n). (Modulo bias is negligible for the
  /// tiny ranges used here.)
  int nextInt(int n) {
    assert(n > 0);
    return nextUint32() % n;
  }

  /// True with probability [p] (0..1).
  bool chance(double p) => nextUint32() < p * 4294967296.0;

  T pick<T>(List<T> items) => items[nextInt(items.length)];

  void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = items[i];
      items[i] = items[j];
      items[j] = t;
    }
  }
}

/// Stable hashing helpers (32-bit FNV-1a over 32-bit words).
abstract final class StableHash {
  static int words(Iterable<int> words, {int basis = 0x811C9DC5}) {
    var h = basis;
    for (final w in words) {
      var x = w & _m32;
      for (var i = 0; i < 4; i++) {
        h ^= x & 0xFF;
        h = _imul(h, 0x01000193);
        x >>= 8;
      }
    }
    return h;
  }

  /// Seed for (version, level, variant, attempt). Level may exceed 32 bits.
  static int levelSeed(int version, int level, int variant, [int attempt = 0]) {
    final h = words([
      version,
      level & _m32,
      (level >> 16) >> 16,
      variant,
      attempt,
    ]);
    // Extra avalanche so adjacent levels get unrelated streams.
    return SeededRandom(h).nextUint32();
  }
}
