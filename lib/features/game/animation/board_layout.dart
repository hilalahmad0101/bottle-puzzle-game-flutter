import 'dart:math' as math;
import 'dart:ui';

/// Positions of every bottle on the board, in board coordinates. The pour
/// animation needs real rectangles (to fly a bottle from A to B), so the
/// board lays itself out explicitly instead of using Wrap/Grid.
final class BoardLayout {
  const BoardLayout({
    required this.size,
    required this.bottleSize,
    required this.rects,
  });

  final Size size;
  final Size bottleSize;
  final List<Rect> rects;

  /// Vertical space a layout needs, as a multiple of one bottle's height, for
  /// [rows] rows: headroom above the first row, the rows, the gaps between
  /// them and a little at the bottom.
  static double _heightFactor(int rows) =>
      0.72 + rows + 0.30 * (rows - 1) + 0.08;

  /// Without [maxHeight]: up to 6 bottles in one row, otherwise two balanced
  /// rows (12 bottles = 6 + 6, which fits a 320 px wide phone).
  ///
  /// With [maxHeight] (the playing screen): the number of rows (1-3) that
  /// gives the LARGEST bottles that fit both the width and the height, so a
  /// small phone, a tall phone, a tablet and a landscape screen each get the
  /// best arrangement and nothing is clipped.
  ///
  /// Room is reserved above the top row so a lifted or pouring bottle never
  /// leaves the board.
  static BoardLayout compute({
    required int count,
    required double width,
    required double aspect,
    double maxBottleHeight = 210,
    double gap = 8,
    double? maxHeight,
  }) {
    assert(count >= 0 && width > 0 && aspect > 0);
    if (count == 0) {
      return const BoardLayout(
        size: Size.zero,
        bottleSize: Size.zero,
        rects: [],
      );
    }

    int perRow;
    double bh;
    if (maxHeight == null) {
      perRow = count <= 6 ? count : (count / 2).ceil();
      final bw = math.min(
        (width - (perRow - 1) * gap) / perRow,
        maxBottleHeight * aspect,
      );
      bh = bw / aspect;
    } else {
      perRow = count;
      bh = -1;
      for (var rows = 1; rows <= math.min(3, count); rows++) {
        final pr = (count / rows).ceil();
        final actualRows = (count / pr).ceil();
        final byWidth = ((width - (pr - 1) * gap) / pr) / aspect;
        final byHeight = maxHeight / _heightFactor(actualRows);
        final candidate = math.min(
          math.min(byWidth, byHeight),
          maxBottleHeight,
        );
        if (candidate > bh + 1e-9) {
          bh = candidate;
          perRow = pr;
        }
      }
    }
    return _build(
      count: count,
      width: width,
      perRow: perRow,
      bh: bh,
      aspect: aspect,
      gap: gap,
    );
  }

  static BoardLayout _build({
    required int count,
    required double width,
    required int perRow,
    required double bh,
    required double aspect,
    required double gap,
  }) {
    final bw = bh * aspect;
    final rows = (count / perRow).ceil();
    final topPad = bh * 0.72;
    final rowGap = bh * 0.30;
    final rects = <Rect>[];
    for (var i = 0; i < count; i++) {
      final row = i ~/ perRow;
      final inRow = math.min(perRow, count - row * perRow);
      final rowWidth = inRow * bw + (inRow - 1) * gap;
      final left = (width - rowWidth) / 2 + (i % perRow) * (bw + gap);
      rects.add(Rect.fromLTWH(left, topPad + row * (bh + rowGap), bw, bh));
    }
    return BoardLayout(
      size: Size(width, topPad + rows * bh + (rows - 1) * rowGap + bh * 0.08),
      bottleSize: Size(bw, bh),
      rects: rects,
    );
  }
}
