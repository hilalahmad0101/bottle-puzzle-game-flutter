import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/color_unit.dart';
import 'package:prism_pour/features/game/animation/liquid_levels.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';

List<ColorUnit> u(List<int> ids) => ids.map(ColorUnit.new).toList();

void main() {
  group('drained', () {
    test('zero amount changes nothing', () {
      expect(
        LiquidLevels.drained(u([1, 2, 2]), 0),
        LiquidLayerSpan.fromUnits(u([1, 2, 2])),
      );
    });

    test('removes from the TOP layer only', () {
      expect(LiquidLevels.drained(u([1, 2, 2]), 0.5), [
        const LiquidLayerSpan(1, 0, 1),
        const LiquidLayerSpan(2, 1, 2.5),
      ]);
    });

    test('a whole top layer disappears, no zero-height sliver', () {
      expect(LiquidLevels.drained(u([1, 2, 2]), 2), [
        const LiquidLayerSpan(1, 0, 1),
      ]);
    });

    test('can cut into the layer below when a pour spans layers', () {
      expect(LiquidLevels.drained(u([1, 1, 2]), 1.5), [
        const LiquidLayerSpan(1, 0, 1.5),
      ]);
    });

    test('draining everything leaves an empty bottle', () {
      expect(LiquidLevels.drained(u([1, 1]), 2), isEmpty);
      expect(LiquidLevels.drained(u([1, 1]), 9), isEmpty);
    });

    test('equals the engine result at the end', () {
      for (var q = 1; q <= 3; q++) {
        final before = u([0, 2, 1, 1, 1]).sublist(0, 4);
        final after = before.sublist(0, before.length - q.clamp(0, 3));
        expect(
          LiquidLevels.drained(
            before,
            (before.length - after.length).toDouble(),
          ),
          LiquidLayerSpan.fromUnits(after),
        );
      }
    });
  });

  group('filled', () {
    test('adds a new layer on top', () {
      expect(LiquidLevels.filled(u([1]), const ColorUnit(2), 1.5), [
        const LiquidLayerSpan(1, 0, 1),
        const LiquidLayerSpan(2, 1, 2.5),
      ]);
    });

    test('merges with an equal top colour (no seam)', () {
      expect(LiquidLevels.filled(u([1, 2]), const ColorUnit(2), 0.5), [
        const LiquidLayerSpan(1, 0, 1),
        const LiquidLayerSpan(2, 1, 2.5),
      ]);
    });

    test('into an empty bottle', () {
      expect(LiquidLevels.filled(const [], const ColorUnit(3), 2), [
        const LiquidLayerSpan(3, 0, 2),
      ]);
    });

    test('zero amount changes nothing', () {
      expect(
        LiquidLevels.filled(u([1]), const ColorUnit(2), 0),
        LiquidLayerSpan.fromUnits(u([1])),
      );
    });

    test('equals the engine result at the end', () {
      final before = u([1, 0, 2]);
      final after = u([1, 0, 2, 2, 2]);
      expect(
        LiquidLevels.filled(before, const ColorUnit(2), 2),
        LiquidLayerSpan.fromUnits(after),
      );
    });
  });

  test('total height', () {
    expect(LiquidLevels.total(const []), 0);
    expect(
      LiquidLevels.total(
        LiquidLevels.filled(u([1, 1]), const ColorUnit(1), 0.25),
      ),
      2.25,
    );
  });
}
