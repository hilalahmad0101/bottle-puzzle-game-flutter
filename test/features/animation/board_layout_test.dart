import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/features/game/animation/board_layout.dart';

const aspect = 0.42;

void main() {
  layoutFitsHeightTests();
  test('no bottles gives an empty layout', () {
    final l = BoardLayout.compute(count: 0, width: 300, aspect: aspect);
    expect(l.rects, isEmpty);
  });

  for (final width in [320.0, 360.0, 412.0, 600.0]) {
    for (var n = 1; n <= 12; n++) {
      test('$n bottles fit a $width px wide board without overlap', () {
        final l = BoardLayout.compute(count: n, width: width, aspect: aspect);
        expect(l.rects.length, n);
        for (final r in l.rects) {
          expect(r.left, greaterThanOrEqualTo(-1e-9));
          expect(r.right, lessThanOrEqualTo(width + 1e-9));
          expect(r.top, greaterThan(0), reason: 'headroom above the first row');
          expect(r.bottom, lessThanOrEqualTo(l.size.height));
          expect(r.width / r.height, closeTo(aspect, 1e-9));
          expect(r.width, closeTo(l.bottleSize.width, 1e-9));
          expect(r.height, closeTo(l.bottleSize.height, 1e-9));
        }
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            expect(
              l.rects[i].overlaps(l.rects[j]),
              isFalse,
              reason: '$i vs $j',
            );
          }
        }
        expect(l.size.width, width);
      });
    }
  }

  test('up to six bottles share one row, more use two balanced rows', () {
    Set<double> rowsOf(int n) => BoardLayout.compute(
      count: n,
      width: 360,
      aspect: aspect,
    ).rects.map((r) => r.top).toSet();
    expect(rowsOf(6).length, 1);
    expect(rowsOf(7).length, 2);
    expect(rowsOf(12).length, 2);
    final l = BoardLayout.compute(count: 12, width: 360, aspect: aspect);
    final firstRow = l.rects.where((r) => r.top == l.rects.first.top).length;
    expect(firstRow, 6);
  });

  test('twelve bottles stay usable on a small phone', () {
    final l = BoardLayout.compute(count: 12, width: 320, aspect: aspect);
    expect(l.bottleSize.width, greaterThan(38));
    expect(l.bottleSize.height, greaterThan(90));
  });

  test('rows are centred', () {
    final l = BoardLayout.compute(count: 3, width: 400, aspect: aspect);
    final left = l.rects.first.left;
    final right = 400 - l.rects.last.right;
    expect(left, closeTo(right, 1e-9));
  });

  test('bottle size is capped on wide boards', () {
    final l = BoardLayout.compute(count: 2, width: 900, aspect: aspect);
    expect(l.bottleSize.height, lessThanOrEqualTo(210 + 1e-9));
  });

  test('there is room above for a lifted or pouring bottle', () {
    final l = BoardLayout.compute(count: 5, width: 400, aspect: aspect);
    expect(l.rects.first.top, greaterThanOrEqualTo(l.bottleSize.height * 0.6));
  });

  test('gap between rows leaves room to lift the second row', () {
    final l = BoardLayout.compute(count: 8, width: 400, aspect: aspect);
    final r0 = l.rects.first, r1 = l.rects.last;
    expect(r1.top - r0.bottom, greaterThan(l.bottleSize.height * 0.2));
    expect(
      Rect.fromLTWH(0, 0, l.size.width, l.size.height).contains(r1.bottomRight),
      isTrue,
    );
  });
}

void layoutFitsHeightTests() {
  group('fitting a screen of a given height', () {
    const sizes = [
      Size(320, 380),
      Size(360, 460),
      Size(393, 640),
      Size(412, 700),
      Size(800, 900),
      Size(700, 280),
      Size(760, 300),
    ];

    for (final size in sizes) {
      for (var n = 1; n <= 12; n++) {
        test(
          '$n bottles in ${size.width.toInt()}x${size.height.toInt()} fit both ways',
          () {
            final l = BoardLayout.compute(
              count: n,
              width: size.width,
              aspect: aspect,
              maxHeight: size.height,
            );
            expect(l.rects.length, n);
            expect(
              l.size.height,
              lessThanOrEqualTo(size.height + 1e-6),
              reason: 'height',
            );
            expect(l.size.width, size.width);
            for (final r in l.rects) {
              expect(r.left, greaterThanOrEqualTo(-1e-9));
              expect(r.right, lessThanOrEqualTo(size.width + 1e-9));
              expect(r.bottom, lessThanOrEqualTo(l.size.height + 1e-9));
              expect(r.top, greaterThan(0));
            }
            for (var i = 0; i < n; i++) {
              for (var j = i + 1; j < n; j++) {
                expect(l.rects[i].overlaps(l.rects[j]), isFalse);
              }
            }
          },
        );
      }
    }

    test('it picks the arrangement with the biggest bottles', () {
      for (final size in sizes) {
        for (var n = 2; n <= 12; n++) {
          final best = BoardLayout.compute(
            count: n,
            width: size.width,
            aspect: aspect,
            maxHeight: size.height,
          );
          // Compare against every forced row count.
          for (var rows = 1; rows <= 3; rows++) {
            final perRow = (n / rows).ceil();
            final actualRows = (n / perRow).ceil();
            final byW = ((size.width - (perRow - 1) * 8) / perRow) / aspect;
            final byH =
                size.height /
                (0.72 + actualRows + 0.30 * (actualRows - 1) + 0.08);
            final candidate = [byW, byH, 210.0].reduce((a, b) => a < b ? a : b);
            expect(
              best.bottleSize.height,
              greaterThanOrEqualTo(candidate - 1e-6),
              reason: '$n in $size vs $rows rows',
            );
          }
        }
      }
    });

    test('a tall screen gets taller bottles than a short one', () {
      final tall = BoardLayout.compute(
        count: 5,
        width: 393,
        aspect: aspect,
        maxHeight: 700,
      );
      final short = BoardLayout.compute(
        count: 5,
        width: 393,
        aspect: aspect,
        maxHeight: 400,
      );
      expect(tall.bottleSize.height, greaterThan(short.bottleSize.height));
    });

    test('a wide landscape screen prefers a single row', () {
      final l = BoardLayout.compute(
        count: 5,
        width: 760,
        aspect: aspect,
        maxHeight: 280,
      );
      expect(l.rects.map((r) => r.top).toSet().length, 1);
    });

    test('twelve bottles stay playable on a small phone', () {
      final l = BoardLayout.compute(
        count: 12,
        width: 320,
        aspect: aspect,
        maxHeight: 400,
      );
      expect(l.bottleSize.width, greaterThan(26));
    });

    test('without maxHeight nothing changes (existing behaviour)', () {
      final a = BoardLayout.compute(count: 12, width: 360, aspect: aspect);
      final b = BoardLayout.compute(
        count: 12,
        width: 360,
        aspect: aspect,
        maxHeight: null,
      );
      expect(a.rects, b.rects);
    });
  });
}
