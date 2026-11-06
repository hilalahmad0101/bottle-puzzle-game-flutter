import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/rendering/bottle_geometry.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';

const sizes = [Size(40, 95), Size(84, 200), Size(150, 357), Size(61, 139)];
const capacities = [3, 4, 5, 6];

void forEachGeometry(
  void Function(BottleStyle style, Size size, int cap, BottleGeometry g) body,
) {
  for (final style in BottleStyles.all) {
    for (final size in sizes) {
      for (final cap in capacities) {
        body(style, size, cap, style.geometryFor(size, cap));
      }
    }
  }
}

void main() {
  group('shared geometry interface', () {
    test(
      'every style yields a BottleGeometry with the requested size/capacity',
      () {
        forEachGeometry((style, size, cap, g) {
          expect(g, isA<BottleGeometry>());
          expect(g.size, size);
          expect(g.capacity, cap);
        });
      },
    );

    test(
      'there are at least three distinct styles with unique ids and names',
      () {
        expect(BottleStyles.all.length, greaterThanOrEqualTo(3));
        expect(
          BottleStyles.all.map((s) => s.id).toSet().length,
          BottleStyles.all.length,
        );
        expect(
          BottleStyles.all.map((s) => s.name).toSet().length,
          BottleStyles.all.length,
        );
        expect(
          BottleStyles.all.map((s) => s.name),
          containsAll(['Alchemy Classic', 'Crystal Prism', 'Royal Glass']),
        );
      },
    );

    test('silhouettes really differ between styles', () {
      final a = BottleStyles.alchemyClassic.geometryFor(
        const Size(100, 238),
        4,
      );
      final b = BottleStyles.crystalPrism.geometryFor(const Size(100, 238), 4);
      final c = BottleStyles.royalGlass.geometryFor(const Size(100, 238), 4);
      expect(a.outline.getBounds(), isNot(b.outline.getBounds()));
      expect(b.outline.getBounds(), isNot(c.outline.getBounds()));
      expect(a.ringRect, isNot(b.ringRect));
    });
  });

  group('unit layout', () {
    test('every unit has exactly the same height', () {
      forEachGeometry((style, size, cap, g) {
        final h = g.unitHeight;
        expect(h, greaterThan(0));
        for (var i = 0; i < cap; i++) {
          expect(
            g.unitRect(i).height,
            closeTo(h, 1e-9),
            reason: '${style.id} $size cap=$cap unit $i',
          );
        }
        expect(h * cap, closeTo(g.liquidBounds.height, 1e-9));
      });
    });

    test('units tile the column exactly: bottom unit at the floor, top unit at the top', () {
      forEachGeometry((style, size, cap, g) {
        expect(g.unitRect(0).bottom, closeTo(g.liquidBounds.bottom, 1e-9));
        expect(g.unitRect(cap - 1).top, closeTo(g.liquidBounds.top, 1e-9));
        for (var i = 1; i < cap; i++) {
          expect(g.unitRect(i).bottom, closeTo(g.unitRect(i - 1).top, 1e-9));
          expect(g.unitRect(i).left, g.liquidBounds.left);
          expect(g.unitRect(i).right, g.liquidBounds.right);
        }
      });
    });

    test('unit height scales linearly with the bottle size', () {
      for (final style in BottleStyles.all) {
        final small = style.geometryFor(const Size(50, 119), 4);
        final big = style.geometryFor(const Size(100, 238), 4);
        expect(big.unitHeight, closeTo(small.unitHeight * 2, 1e-6));
      }
    });

    test('unit index out of range is rejected', () {
      final g = BottleStyles.alchemyClassic.geometryFor(const Size(84, 200), 4);
      expect(() => g.unitRect(4), throwsA(isA<AssertionError>()));
      expect(() => g.unitRect(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('no overflow', () {
    test('the hollow lies inside the glass and the glass inside the box', () {
      forEachGeometry((style, size, cap, g) {
        final out = g.outline.getBounds();
        final cav = g.cavity.getBounds();
        final why = '${style.id} $size cap=$cap';
        expect(out.left, greaterThanOrEqualTo(-1e-3), reason: why);
        expect(out.top, greaterThanOrEqualTo(-1e-3), reason: why);
        expect(out.right, lessThanOrEqualTo(size.width + 1e-3), reason: why);
        expect(out.bottom, lessThanOrEqualTo(size.height + 1e-3), reason: why);
        expect(cav.left, greaterThan(out.left), reason: why);
        expect(cav.right, lessThan(out.right), reason: why);
        expect(cav.bottom, lessThan(out.bottom), reason: why);
        // Thick base: clearly more glass under the liquid than at the sides.
        expect(
          out.bottom - cav.bottom,
          greaterThan(size.height * 0.03),
          reason: why,
        );
      });
    });

    test(
      'the liquid column is inside the hollow (even a completely full bottle)',
      () {
        forEachGeometry((style, size, cap, g) {
          final cav = g.cavity.getBounds();
          final l = g.liquidBounds;
          final why = '${style.id} $size cap=$cap';
          expect(l.left, greaterThanOrEqualTo(cav.left - 1e-3), reason: why);
          expect(l.right, lessThanOrEqualTo(cav.right + 1e-3), reason: why);
          // Path stores float32, hence the tolerance for path-derived values.
          expect(l.bottom, closeTo(cav.bottom, 1e-3), reason: why);
          // All four corners of the TOP unit are inside the hollow.
          final top = g.unitRect(cap - 1).deflate(0.5);
          for (final p in [
            top.topLeft,
            top.topRight,
            top.bottomLeft,
            top.bottomRight,
          ]) {
            expect(g.cavity.contains(p), isTrue, reason: '$why corner $p');
          }
          // Centre of every unit is inside.
          for (var i = 0; i < cap; i++) {
            expect(
              g.cavity.contains(g.unitRect(i).center),
              isTrue,
              reason: '$why unit $i',
            );
          }
        });
      },
    );

    test('a full column stops below the neck ring and mouth', () {
      forEachGeometry((style, size, cap, g) {
        final why = '${style.id} $size cap=$cap';
        expect(g.liquidBounds.top, greaterThan(g.ringRect.bottom), reason: why);
        expect(g.mouth.dy, lessThan(g.ringRect.top), reason: why);
      });
    });

    test('anchor points the animation will use lie inside the glass', () {
      forEachGeometry((style, size, cap, g) {
        expect(g.pivot.dx, closeTo(size.width / 2, 1e-3));
        expect(g.cavity.contains(g.pivot), isTrue);
        expect(g.mouth.dx, closeTo(size.width / 2, 1e-3));
        expect(g.mouth.dy, lessThan(g.liquidBounds.top));
        expect(g.facetEdges.length, 4);
        final bounds = g.outline.getBounds().inflate(0.5);
        for (final (a, b) in g.facetEdges) {
          expect(bounds.contains(a), isTrue);
          expect(bounds.contains(b), isTrue);
        }
      });
    });
  });

  group('shape properties', () {
    test('the neck is narrower than the body (elegant narrow neck)', () {
      for (final style in BottleStyles.all) {
        final s = style.spec;
        expect(s.neckWidth, lessThan(s.bodyWidth * 0.5));
        expect(s.lipWidth, greaterThan(s.neckWidth)); // flared rim
      }
    });

    test('outline is symmetric about the vertical centre line', () {
      for (final style in BottleStyles.all) {
        final g = style.geometryFor(const Size(84, 200), 4);
        final b = g.outline.getBounds();
        expect((b.left + b.right) / 2, closeTo(42, 1e-3));
        for (final y in [30.0, 80.0, 140.0, 190.0]) {
          final left = g.outline.contains(Offset(42 - 20, y));
          final right = g.outline.contains(Offset(42 + 20, y));
          expect(left, right, reason: '${style.id} y=$y');
        }
      }
    });

    test('the hollow is open at the top (liquid can be poured out)', () {
      for (final style in BottleStyles.all) {
        final g = style.geometryFor(const Size(84, 200), 4);
        // Just below the mouth, on the centre line, is hollow; just above
        // the lip is not glass at all.
        expect(g.cavity.contains(Offset(42, g.mouth.dy + 14)), isTrue);
      }
    });
  });
}
