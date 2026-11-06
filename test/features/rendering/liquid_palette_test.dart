import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/engine/models/color_unit.dart';

double minDelta(Iterable<LiquidColor> cs) {
  final l = cs.toList();
  var m = double.infinity;
  for (var i = 0; i < l.length; i++) {
    for (var j = i + 1; j < l.length; j++) {
      final d = ColorMath.deltaE(l[i].base, l[j].base);
      if (d < m) m = d;
    }
  }
  return m;
}

void main() {
  group('catalogue', () {
    test('has all twelve requested colours', () {
      expect(
        LiquidPalette.all.map((c) => c.name),
        containsAll([
          'Cyan',
          'Magenta',
          'Emerald',
          'Amber',
          'Violet',
          'Coral',
          'Royal Blue',
          'Lime',
          'Rose',
          'Turquoise',
          'Gold',
          'Deep Orange',
        ]),
      );
      expect(LiquidPalette.all.length, 12);
    });

    test('colours, symbols and patterns are all unique', () {
      final all = LiquidPalette.all;
      expect(all.map((c) => c.base.toARGB32()).toSet().length, 12);
      expect(all.map((c) => c.symbol).toSet().length, 12);
      expect(all.map((c) => c.pattern).toSet().length, 12);
      expect(all.map((c) => c.name).toSet().length, 12);
    });

    test('every pair is clearly distinguishable even in the worst case', () {
      expect(minDelta(LiquidPalette.all), greaterThan(17));
    });

    test('light/dark variants stay on either side of the base', () {
      for (final c in LiquidPalette.all) {
        final (lb, _, _) = ColorMath.lab(c.base);
        expect(ColorMath.lab(c.light).$1, greaterThan(lb));
        expect(ColorMath.lab(c.dark).$1, lessThan(lb));
      }
    });
  });

  group('colour math', () {
    test('deltaE basics', () {
      const red = Color(0xFFFF0000);
      expect(ColorMath.deltaE(red, red), 0);
      expect(
        ColorMath.deltaE(red, const Color(0xFF00FF00)),
        closeTo(ColorMath.deltaE(const Color(0xFF00FF00), red), 1e-9),
      );
      expect(
        ColorMath.deltaE(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(100, 0.5),
      );
    });
  });

  group('per-level palettes avoid similar colours', () {
    test('any N colours chosen for a level stay well apart', () {
      final expectedFloor = {
        2: 100.0,
        3: 100.0,
        4: 90.0,
        5: 60.0,
        6: 55.0,
        7: 50.0,
        8: 45.0,
        9: 25.0,
        10: 24.0,
      };
      for (final entry in expectedFloor.entries) {
        final p = LiquidPalette.forColorIds(List.generate(entry.key, (i) => i));
        final colors = p.entries.map((e) => e.value).toList();
        expect(
          colors.map((c) => c.name).toSet().length,
          entry.key,
          reason: 'distinct colours for ${entry.key} ids',
        );
        expect(
          minDelta(colors),
          greaterThan(entry.value),
          reason: '${entry.key} colours',
        );
      }
    });

    test('the known look-alikes are never active together up to 8 colours', () {
      // Cyan/Turquoise, Amber/Gold and Coral/Deep Orange are the genuinely
      // similar pairs; they may only meet in the largest levels.
      const pairs = [
        ('Cyan', 'Turquoise'),
        ('Amber', 'Gold'),
        ('Coral', 'Deep Orange'),
      ];
      for (var n = 2; n <= 8; n++) {
        final names = LiquidPalette.forColorIds(List.generate(n, (i) => i))
            .entries
            .map((e) => e.value.name)
            .toSet();
        for (final (a, b) in pairs) {
          expect(
            names.contains(a) && names.contains(b),
            isFalse,
            reason: '$a and $b both active with $n colours',
          );
        }
      }
    });

    test('is deterministic and handles non-contiguous ids', () {
      final a = LiquidPalette.forColorIds([9, 3, 7]);
      final b = LiquidPalette.forColorIds([3, 7, 9]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.colorFor(3).name, isNot(a.colorFor(7).name));
      expect(a.colorFor(7).name, isNot(a.colorFor(9).name));
    });

    test('a seed changes which id gets which colour but not the set', () {
      final ids = List.generate(8, (i) => i);
      final base = LiquidPalette.forColorIds(ids);
      final seeded = LiquidPalette.forColorIds(ids, seed: 12345);
      expect(
        {for (final e in base.entries) e.value.name},
        {for (final e in seeded.entries) e.value.name},
      );
      expect(base == seeded, isFalse);
      expect(seeded, LiquidPalette.forColorIds(ids, seed: 12345));
    });

    test('unknown or huge ids never throw', () {
      final p = LiquidPalette.forColorIds([0, 1]);
      expect(p.colorFor(99).name, isNotEmpty);
      expect(p.colorFor(-4).name, isNotEmpty);
      final many = LiquidPalette.forColorIds(List.generate(20, (i) => i));
      expect(many.colorFor(19).name, isNotEmpty);
    });

    test('the order puts the most different colours first', () {
      final order = LiquidPalette.distinctOrder;
      expect(order.toSet().length, 12);
      final first = [for (final i in order.take(2)) LiquidPalette.all[i]];
      expect(ColorMath.deltaE(first[0].base, first[1].base), greaterThan(100));
    });
  });

  group('liquid layer spans', () {
    ColorUnit u(int id) => ColorUnit(id);

    test('empty bottle has no spans', () {
      expect(LiquidLayerSpan.fromUnits(const []), isEmpty);
    });

    test('merges contiguous equal colours and keeps positions', () {
      final spans = LiquidLayerSpan.fromUnits([
        u(1),
        u(1),
        u(2),
        u(1),
        u(1),
        u(1),
      ]);
      expect(spans, [
        const LiquidLayerSpan(1, 0, 2),
        const LiquidLayerSpan(2, 2, 3),
        const LiquidLayerSpan(1, 3, 6),
      ]);
      expect(spans.fold<double>(0, (a, s) => a + s.units), 6);
    });

    test('spans cover exactly the units, with no gaps or overlap', () {
      final units = [u(0), u(1), u(1), u(2)];
      final spans = LiquidLayerSpan.fromUnits(units);
      var at = 0.0;
      for (final s in spans) {
        expect(s.from, at);
        at = s.to;
      }
      expect(at, units.length);
    });

    test('value equality', () {
      expect(const LiquidLayerSpan(1, 0, 2), const LiquidLayerSpan(1, 0, 2));
      expect(
        const LiquidLayerSpan(1, 0, 2),
        isNot(const LiquidLayerSpan(1, 0, 3)),
      );
    });
  });
}
