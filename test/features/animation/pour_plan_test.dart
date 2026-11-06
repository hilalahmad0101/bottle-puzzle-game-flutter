import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/game_engine.dart';
import 'package:prism_pour/engine/models/move_model.dart';
import 'package:prism_pour/engine/models/move_result.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/animation/board_layout.dart';
import 'package:prism_pour/features/game/animation/liquid_levels.dart';
import 'package:prism_pour/features/game/animation/pour_plan.dart';
import 'package:prism_pour/features/game/rendering/bottle_geometry.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/liquid_layer.dart';
import 'package:prism_pour/features/game/rendering/liquid_volume_model.dart';

const boardWidth = 420.0;

({PourPlan plan, MoveResult result, BoardLayout layout, BottleGeometry g})
build(
  List<List<int>> bottles,
  MoveModel move, {
  double scale = 1,
  bool reduced = false,
  BottleStyle style = BottleStyles.alchemyClassic,
  double width = boardWidth,
}) {
  final state = PuzzleState.fromIds(bottles);
  final layout = BoardLayout.compute(
    count: state.bottleCount,
    width: width,
    aspect: style.spec.aspect,
  );
  final g = style.geometryFor(layout.bottleSize, 4);
  final result = GameEngine(state).applyMove(move);
  expect(result.isSuccess, isTrue, reason: '$move must be legal');
  final plan = PourPlan.build(
    result: result,
    geometry: g,
    sourceRect: layout.rects[move.source],
    destRect: layout.rects[move.destination],
    boardWidth: layout.size.width,
    timeScale: scale,
    reducedMotion: reduced,
  );
  return (plan: plan, result: result, layout: layout, g: g);
}

/// Scenarios covering 1..4 units, partial transfer, left/right/rows.
final scenarios = <String, (List<List<int>>, MoveModel)>{
  '1 unit': (
    [
      [2, 2, 0, 1],
      [1, 3, 3],
      [0, 0, 1, 2],
      [3, 1],
      [],
      [],
    ],
    const MoveModel(0, 3),
  ),
  '2 units': (
    [
      [0, 2, 1, 1],
      [3, 1],
      [2, 0, 3, 0],
      [2, 3, 0, 2],
      [],
      [],
    ],
    const MoveModel(0, 1),
  ),
  '3 units': (
    [
      [2, 1, 1, 1],
      [0, 3, 0, 3],
      [2, 0, 3, 2],
      [],
      [],
    ],
    const MoveModel(0, 3),
  ),
  '4 units': (
    [
      [1, 1, 1, 1],
      [0, 2, 0, 2],
      [],
      [],
    ],
    const MoveModel(0, 2),
  ),
  'partial 1 of 3': (
    [
      [3, 1, 1, 1],
      [2, 1, 1],
      [0, 2, 3, 0],
      [],
      [],
    ],
    const MoveModel(0, 1),
  ),
  'pour left': (
    [
      [0, 2, 1],
      [1, 3, 3, 2],
      [3, 2, 1, 1],
      [3, 1, 2, 1],
      [],
      [],
    ],
    const MoveModel(3, 0),
  ),
  'far apart': (
    [
      [2, 2, 0, 1],
      [3, 3, 0],
      [0, 2, 3],
      [1, 3],
      [],
      [1, 1],
    ],
    const MoveModel(0, 5),
  ),
};

List<double> times(PourPlan p, [int n = 240]) => [
  for (var i = 0; i <= n; i++) p.duration * i / n,
];

void expectSpansClose(List<LiquidLayerSpan> a, List<LiquidLayerSpan> b) {
  expect(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    expect(a[i].colorId, b[i].colorId);
    expect(a[i].from, closeTo(b[i].from, 1e-9));
    expect(a[i].to, closeTo(b[i].to, 1e-9));
  }
}

double fillOf(List<LiquidLayerSpan> s) => LiquidLevels.total(s);

void main() {
  group('the animation represents EXACTLY the engine move', () {
    for (final e in scenarios.entries) {
      test(
        '${e.key}: starts at the previous state and ends at the resulting state',
        () {
          final b = build(e.value.$1, e.value.$2);
          final r = b.result;
          final first = b.plan.frameAt(0);
          final last = b.plan.frameAt(b.plan.duration);
          expect(
            first.sourceSpans,
            LiquidLayerSpan.fromUnits(r.sourceBefore!.units),
          );
          expect(
            first.destSpans,
            LiquidLayerSpan.fromUnits(r.destinationBefore!.units),
          );
          // Exact equality: the last frame IS the committed state.
          expect(
            last.sourceSpans,
            LiquidLayerSpan.fromUnits(r.sourceAfter!.units),
          );
          expect(
            last.destSpans,
            LiquidLayerSpan.fromUnits(r.destinationAfter!.units),
          );
          expect(last.phase, PourPhase.done);
        },
      );

      test('${e.key}: moves exactly quantity units, never more or less', () {
        final b = build(e.value.$1, e.value.$2);
        final q = b.result.quantity;
        final s0 = b.result.sourceBefore!.length.toDouble();
        final d0 = b.result.destinationBefore!.length.toDouble();
        expect(fillOf(b.plan.frameAt(b.plan.duration).sourceSpans), s0 - q);
        expect(fillOf(b.plan.frameAt(b.plan.duration).destSpans), d0 + q);
        for (final t in times(b.plan)) {
          final f = b.plan.frameAt(t);
          final drained = s0 - fillOf(f.sourceSpans);
          final filled = fillOf(f.destSpans) - d0;
          expect(drained, inInclusiveRange(-1e-9, q + 1e-9));
          expect(filled, inInclusiveRange(-1e-9, q + 1e-9));
          // Liquid is never created: what has arrived <= what has left.
          expect(filled, lessThanOrEqualTo(drained + 1e-9), reason: 't=$t');
        }
      });

      test('${e.key}: levels move smoothly and monotonically', () {
        final b = build(e.value.$1, e.value.$2);
        var prevS = double.infinity, prevD = -1.0;
        for (final t in times(b.plan, 400)) {
          final f = b.plan.frameAt(t);
          expect(fillOf(f.sourceSpans), lessThanOrEqualTo(prevS + 1e-9));
          expect(fillOf(f.destSpans), greaterThanOrEqualTo(prevD - 1e-9));
          prevS = fillOf(f.sourceSpans);
          prevD = fillOf(f.destSpans);
        }
        // No big jumps between neighbouring frames (60 fps worth).
        final dt = b.plan.duration / 400;
        var last = b.plan.frameAt(0);
        for (var i = 1; i <= 400; i++) {
          final f = b.plan.frameAt(dt * i);
          expect(
            (fillOf(f.sourceSpans) - fillOf(last.sourceSpans)).abs(),
            lessThan(0.08),
          );
          expect(
            (fillOf(f.destSpans) - fillOf(last.destSpans)).abs(),
            lessThan(0.08),
          );
          last = f;
        }
      });

      test('${e.key}: the poured colour is the engine\'s colour', () {
        final b = build(e.value.$1, e.value.$2);
        for (final t in times(b.plan)) {
          final f = b.plan.frameAt(t);
          if (f.stream != null) expect(f.stream!.color, b.result.color);
          // The top destination layer is always that colour once it has arrived.
        }
        final end = b.plan.frameAt(b.plan.duration);
        expect(end.destSpans.last.colorId, b.result.color!.id);
      });
    }

    test('different quantities really animate different amounts', () {
      final one = build(scenarios['1 unit']!.$1, scenarios['1 unit']!.$2);
      final two = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2);
      final three = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2);
      final four = build(scenarios['4 units']!.$1, scenarios['4 units']!.$2);
      expect([one, two, three, four].map((b) => b.plan.quantity), [1, 2, 3, 4]);
      final d = [one, two, three, four].map((b) => b.plan.duration).toList();
      for (var i = 1; i < d.length; i++) {
        expect(d[i], greaterThan(d[i - 1]), reason: 'bigger pours take longer');
      }
    });

    test(
      'a partial transfer animates the engine quantity, not the group size',
      () {
        final b = build(
          scenarios['partial 1 of 3']!.$1,
          scenarios['partial 1 of 3']!.$2,
        );
        expect(b.result.quantity, 1);
        expect(b.result.sourceBefore!.topGroupSize, 3);
        expect(fillOf(b.plan.frameAt(b.plan.duration).sourceSpans), 3);
      },
    );
  });

  group('stream is aligned with the bottle neck and the destination', () {
    for (final style in BottleStyles.all) {
      for (final e in scenarios.entries) {
        test(
          '${style.name} / ${e.key}: the lip stays on the held point while pouring',
          () {
            final b = build(e.value.$1, e.value.$2, style: style);
            final p = b.plan;
            final lip = b.g.pourLip(p.side.toDouble());
            var checked = 0;
            for (
              var t = p.tApproachEnd;
              t <= p.tPourEnd;
              t += (p.tPourEnd - p.tApproachEnd) / 30
            ) {
              final f = p.frameAt(t);
              final world = p.worldPoint(f.sourceAnchor, f.sourceAngle, lip);
              expect(
                (world - p.lipTarget).distance,
                lessThan(0.01),
                reason: 't=$t',
              );
              checked++;
            }
            expect(checked, greaterThan(20));
          },
        );

        test(
          '${style.name} / ${e.key}: the stream starts at the lip and lands in the destination',
          () {
            final b = build(e.value.$1, e.value.$2, style: style);
            final p = b.plan;
            var seen = 0;
            for (final t in times(p, 300)) {
              final f = p.frameAt(t);
              final s = f.stream;
              if (s == null) continue;
              seen++;
              expect((s.p0 - p.lipTarget).distance, lessThan(1e-9));
              expect(s.p3.dx, closeTo(p.destRect.center.dx, 1e-9));
              // Lands exactly on the destination liquid surface (board coords).
              expect(s.p3, f.impact);
              // Falls DOWN from lip to surface, inside the destination column.
              expect(s.p3.dy, greaterThan(s.p0.dy));
              expect(
                s.p3.dy,
                lessThanOrEqualTo(
                  p.destRect.top + b.g.liquidBounds.bottom + 1e-6,
                ),
              );
              expect(
                s.p3.dy,
                greaterThanOrEqualTo(
                  p.destRect.top + b.g.liquidBounds.top - 1e-6,
                ),
              );
              expect(s.width, greaterThan(0));
              expect(s.head, greaterThan(s.tail));
            }
            expect(seen, greaterThan(40));
          },
        );
      }
    }

    test('the stream only exists while liquid is leaving', () {
      final b = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2);
      final p = b.plan;
      expect(p.frameAt(0).stream, isNull);
      expect(p.frameAt(p.tApproachEnd * 0.5).stream, isNull);
      expect(p.frameAt((p.tApproachEnd + p.tPourEnd) / 2).stream, isNotNull);
      expect(p.frameAt(p.tStreamEnd + 0.01).stream, isNull);
      expect(p.frameAt(p.duration).stream, isNull);
    });

    test(
      'the stream grows from the lip and retracts back to the destination',
      () {
        final b = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2);
        final p = b.plan;
        final early = p.frameAt(p.tApproachEnd + 0.03).stream!;
        final mid = p.frameAt((p.tApproachEnd + p.tPourEnd) / 2).stream!;
        final late = p.frameAt(p.tPourEnd + 0.04).stream!;
        expect(early.head, lessThan(1));
        expect(early.tail, 0);
        expect(mid.head, 1);
        expect(mid.tail, 0);
        expect(late.tail, greaterThan(0));
        expect(late.width, lessThan(mid.width));
      },
    );

    test(
      'the source is tilted enough that the liquid actually reaches the lip',
      () {
        for (final e in scenarios.entries) {
          final b = build(e.value.$1, e.value.$2);
          final model = LiquidVolumeModel.of(b.g);
          final before = b.result.sourceBefore!.length.toDouble();
          expect(
            b.plan.startTilt.abs(),
            greaterThanOrEqualTo(model.requiredTilt(before) - 1e-9),
          );
          // And tilt keeps increasing as the bottle empties.
          var prev = 0.0;
          for (var t = b.plan.tApproachEnd; t <= b.plan.tPourEnd; t += 0.02) {
            final a = b.plan.frameAt(t).sourceAngle.abs();
            expect(
              a,
              greaterThanOrEqualTo(prev - 1e-9),
              reason: '${e.key} t=$t',
            );
            prev = a;
          }
          expect(prev, lessThanOrEqualTo(PourPlan.maxTilt + 1e-9));
        }
      },
    );

    test('tilt direction follows the side', () {
      final right = build(
        scenarios['1 unit']!.$1,
        scenarios['1 unit']!.$2,
      ).plan;
      expect(right.side, 1);
      expect(
        right.frameAt((right.tApproachEnd + right.tPourEnd) / 2).sourceAngle,
        greaterThan(0),
      );
      final left = build(
        scenarios['pour left']!.$1,
        scenarios['pour left']!.$2,
      ).plan;
      expect(left.side, -1);
      expect(
        left.frameAt((left.tApproachEnd + left.tPourEnd) / 2).sourceAngle,
        lessThan(0),
      );
    });
  });

  group('motion is continuous and ends exactly at rest', () {
    for (final e in scenarios.entries) {
      test('${e.key}: no jumps in position or angle', () {
        final b = build(e.value.$1, e.value.$2);
        final p = b.plan;
        final n = 1200;
        var prev = p.frameAt(0);
        for (var i = 1; i <= n; i++) {
          final f = p.frameAt(p.duration * i / n);
          // At 1/1200 of the pour a bottle may move only a little.
          expect(
            (f.sourceAnchor - prev.sourceAnchor).distance,
            lessThan(b.layout.bottleSize.height * 0.06),
            reason: 'step $i',
          );
          expect(
            (f.sourceAngle - prev.sourceAngle).abs(),
            lessThan(0.09),
            reason: 'step $i',
          );
          prev = f;
        }
      });

      test(
        '${e.key}: begins where the selected bottle already is (lifted) and ends home',
        () {
          final b = build(e.value.$1, e.value.$2);
          final p = b.plan;
          final first = p.frameAt(0);
          // Start pose == the lifted resting pose `BottleView` shows.
          expect(
            (first.sourceAnchor - p.liftedAnchor).distance,
            lessThan(1e-9),
          );
          expect(first.sourceAngle, 0);
          final last = p.frameAt(p.duration);
          expect((last.sourceAnchor - p.homeAnchor).distance, lessThan(1e-9));
          expect(last.sourceAngle, 0);
          // Everything settled: pixel-identical to a resting bottle.
          expect(last.sourceSurface.isRest, isTrue);
          expect(last.destSurface.isRest, isTrue);
          expect(last.glow, 0);
          expect(last.stream, isNull);
          expect(p.splash(last), isEmpty);
          expect(p.bubbles(last), isEmpty);
        },
      );
    }

    test('the home anchor is the real mouth of the source rectangle', () {
      final b = build(scenarios['1 unit']!.$1, scenarios['1 unit']!.$2);
      final p = b.plan;
      expect(p.homeAnchor, b.layout.rects[0].topLeft + b.g.mouth);
      expect(p.worldPoint(p.homeAnchor, 0, b.g.mouth), p.homeAnchor);
    });

    test('rotation maths: a rotated point matches a hand calculation', () {
      final p = build(scenarios['1 unit']!.$1, scenarios['1 unit']!.$2).plan;
      final local = p.geometry.mouth + const Offset(10, 0);
      final w = p.worldPoint(const Offset(100, 100), math.pi / 2, local);
      expect(w.dx, closeTo(100, 1e-9));
      expect(w.dy, closeTo(110, 1e-9)); // 90 deg clockwise: +x -> +y
    });
  });

  group('the bottle stays on the board', () {
    for (final style in BottleStyles.all) {
      for (final width in [320.0, 360.0, 420.0]) {
        test(
          '${style.name} @ $width: every pair of bottles, source never leaves the board',
          () {
            const n = 6;
            final bottles = [
              for (var i = 0; i < n; i++)
                <int>[0], // each bottle has one colour-0 unit
            ];
            final layout = BoardLayout.compute(
              count: n,
              width: width,
              aspect: style.spec.aspect,
            );
            final g = style.geometryFor(layout.bottleSize, 4);
            final state = PuzzleState.fromIds(bottles);
            for (var s = 0; s < n; s++) {
              for (var d = 0; d < n; d++) {
                if (s == d) continue;
                final result = GameEngine(state).applyMove(MoveModel(s, d));
                final plan = PourPlan.build(
                  result: result,
                  geometry: g,
                  sourceRect: layout.rects[s],
                  destRect: layout.rects[d],
                  boardWidth: layout.size.width,
                );
                for (final t in times(plan, 60)) {
                  final f = plan.frameAt(t);
                  for (final p in g.cavityPolygon) {
                    final w = plan.worldPoint(f.sourceAnchor, f.sourceAngle, p);
                    expect(
                      w.dx,
                      greaterThan(-layout.bottleSize.width * 0.35),
                      reason: '$s->$d t=$t x=${w.dx}',
                    );
                    expect(
                      w.dx,
                      lessThan(width + layout.bottleSize.width * 0.35),
                      reason: '$s->$d t=$t x=${w.dx}',
                    );
                    expect(
                      w.dy,
                      greaterThan(0),
                      reason: '$s->$d t=$t y=${w.dy}',
                    );
                  }
                }
              }
            }
          },
        );
      }
    }

    test('near a board edge the bottle swings to the side with room', () {
      // Leftmost source pouring into its right neighbour on a narrow board.
      final b = build(
        [
          [1],
          [1],
          [],
          [],
          [],
          [],
        ],
        const MoveModel(0, 1),
        width: 320,
      );
      final p = b.plan;
      // Tilting right would push the body off the left edge, so it flips.
      expect(p.side, -1);
    });
  });

  group('timing is device independent', () {
    test('frames depend only on seconds: repeatable and order independent', () {
      final b = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2);
      final a = b.plan.frameAt(0.77);
      b.plan.frameAt(0.1);
      b.plan.frameAt(1.9);
      final c = b.plan.frameAt(0.77);
      expect(c.sourceAnchor, a.sourceAnchor);
      expect(c.sourceAngle, a.sourceAngle);
      expect(c.sourceSpans, a.sourceSpans);
      expect(c.destSpans, a.destSpans);
      expect(c.stream?.p3, a.stream?.p3);
    });

    test('times outside 0..duration are clamped, never extrapolated', () {
      final b = build(scenarios['1 unit']!.$1, scenarios['1 unit']!.$2);
      expect(b.plan.frameAt(-5).sourceAngle, 0);
      expect(b.plan.frameAt(1e6).sourceAngle, 0);
      expect(b.plan.frameAt(1e6).phase, PourPhase.done);
    });

    test('fast speed is the same animation on a compressed clock', () {
      final normal = build(
        scenarios['3 units']!.$1,
        scenarios['3 units']!.$2,
      ).plan;
      final fast = build(
        scenarios['3 units']!.$1,
        scenarios['3 units']!.$2,
        scale: 0.6,
      ).plan;
      expect(fast.duration, closeTo(normal.duration * 0.6, 1e-9));
      for (final f in [0.1, 0.3, 0.55, 0.8, 0.97]) {
        final n = normal.frameAt(normal.duration * f);
        final q = fast.frameAt(fast.duration * f);
        expectSpansClose(q.sourceSpans, n.sourceSpans);
        expectSpansClose(q.destSpans, n.destSpans);
        expect((q.sourceAnchor - n.sourceAnchor).distance, lessThan(1e-6));
        expect(q.sourceAngle, closeTo(n.sourceAngle, 1e-9));
      }
    });

    test('slow motion scales the same way', () {
      final normal = build(
        scenarios['1 unit']!.$1,
        scenarios['1 unit']!.$2,
      ).plan;
      final slow = build(
        scenarios['1 unit']!.$1,
        scenarios['1 unit']!.$2,
        scale: 4,
      ).plan;
      expect(slow.duration, closeTo(normal.duration * 4, 1e-9));
    });

    test('durations are in a sensible range for a mobile puzzle', () {
      for (final e in scenarios.entries) {
        final p = build(e.value.$1, e.value.$2).plan;
        expect(p.duration, inInclusiveRange(1.5, 3.4), reason: e.key);
        final f = build(e.value.$1, e.value.$2, scale: 0.6).plan;
        expect(f.duration, inInclusiveRange(0.9, 2.1), reason: e.key);
      }
    });

    test('phases follow the required order', () {
      final p = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2).plan;
      final seq = <PourPhase>[];
      for (final t in times(p, 500)) {
        final ph = p.phaseAt(t);
        if (seq.isEmpty || seq.last != ph) seq.add(ph);
      }
      expect(seq, [
        PourPhase.approach,
        PourPhase.pouring,
        PourPhase.returning,
        PourPhase.settling,
        PourPhase.done,
      ]);
    });
  });

  group('reduced motion', () {
    for (final e in scenarios.entries) {
      test(
        '${e.key}: no flying, tilting, stream, splash or glow - but the same result',
        () {
          final b = build(e.value.$1, e.value.$2, reduced: true);
          final p = b.plan;
          expect(p.reduced, isTrue);
          expect(p.duration, lessThan(0.5));
          for (final t in times(p, 80)) {
            final f = p.frameAt(t);
            expect(f.stream, isNull);
            expect(f.sourceAngle, 0);
            expect(f.sourceAnchor, p.homeAnchor);
            expect(f.sourceSurface.isRest, isTrue);
            expect(f.destSurface.isRest, isTrue);
            expect(f.glow, 0);
            expect(p.splash(f), isEmpty);
            expect(p.bubbles(f), isEmpty);
          }
          expect(
            p.frameAt(0).sourceSpans,
            LiquidLayerSpan.fromUnits(b.result.sourceBefore!.units),
          );
          expect(
            p.frameAt(p.duration).sourceSpans,
            LiquidLayerSpan.fromUnits(b.result.sourceAfter!.units),
          );
          expect(
            p.frameAt(p.duration).destSpans,
            LiquidLayerSpan.fromUnits(b.result.destinationAfter!.units),
          );
        },
      );
    }

    test('levels still change smoothly (a fade, not a jump)', () {
      final p = build(
        scenarios['2 units']!.$1,
        scenarios['2 units']!.$2,
        reduced: true,
      ).plan;
      final mid = p.frameAt(p.duration / 2);
      final s = fillOf(mid.sourceSpans);
      expect(s, lessThan(4));
      expect(s, greaterThan(2));
    });

    test('is much shorter than the full animation', () {
      final full = build(
        scenarios['3 units']!.$1,
        scenarios['3 units']!.$2,
      ).plan;
      final red = build(
        scenarios['3 units']!.$1,
        scenarios['3 units']!.$2,
        reduced: true,
      ).plan;
      expect(red.duration, lessThan(full.duration * 0.25));
    });
  });

  group('ripples, slosh and particles', () {
    test('the destination surface reacts while the stream lands and calms afterwards', () {
      final p = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2).plan;
      expect(p.frameAt(0).destSurface.isRest, isTrue);
      final during = p.frameAt((p.tApproachEnd + p.tStreamEnd) / 2 + 0.1);
      expect(during.destSurface.rippleAmp, greaterThan(0.9));
      expect(during.destSurface.angle, isNot(0));
      final later = p.frameAt(p.tStreamEnd + (p.duration - p.tStreamEnd) * 0.6);
      expect(
        later.destSurface.rippleAmp,
        lessThan(during.destSurface.rippleAmp),
      );
      expect(p.frameAt(p.duration).destSurface.isRest, isTrue);
    });

    test('slosh is small (looks like water, not an earthquake)', () {
      final p = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2).plan;
      for (final t in times(p, 400)) {
        final f = p.frameAt(t);
        expect((f.destSurface.angle).abs(), lessThan(0.06));
        expect((f.sourceSurface.angle - f.sourceAngle).abs(), lessThan(0.06));
      }
    });

    test(
      'splash droplets are deterministic, bounded and above the surface',
      () {
        final p = build(
          scenarios['3 units']!.$1,
          scenarios['3 units']!.$2,
        ).plan;
        var total = 0;
        for (final t in times(p, 300)) {
          final f = p.frameAt(t);
          final a = p.splash(f);
          final b = p.splash(f);
          expect(a.length, b.length);
          expect(a.length, lessThanOrEqualTo(7));
          for (var i = 0; i < a.length; i++) {
            expect(a[i].position, b[i].position);
            expect(a[i].position.dy, lessThanOrEqualTo(f.impact.dy + 1e-9));
            expect(a[i].alpha, inInclusiveRange(0, 1));
            expect(a[i].radius, greaterThan(0));
          }
          total += a.length;
        }
        expect(total, greaterThan(50));
      },
    );

    test('bubbles rise inside the liquid and stay within bounds', () {
      final p = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2).plan;
      var total = 0;
      for (final t in times(p, 300)) {
        final f = p.frameAt(t);
        final list = p.bubbles(f);
        expect(list.length, lessThanOrEqualTo(8));
        for (final b in list) {
          expect(b.depth, greaterThanOrEqualTo(0));
          expect(b.dx.abs(), lessThan(p.geometry.size.width * 0.3));
          expect(b.alpha, inInclusiveRange(0, 1));
        }
        total += list.length;
      }
      expect(total, greaterThan(50));
    });

    test('no particles before the stream arrives or long after it ends', () {
      final p = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2).plan;
      expect(p.splash(p.frameAt(0.1)), isEmpty);
      expect(p.bubbles(p.frameAt(0.1)), isEmpty);
      expect(p.splash(p.frameAt(p.duration)), isEmpty);
    });

    test('particle motion differs between different moves', () {
      final a = build(scenarios['2 units']!.$1, scenarios['2 units']!.$2).plan;
      final b = build(scenarios['3 units']!.$1, scenarios['3 units']!.$2).plan;
      expect(a.seed, isNot(b.seed));
    });
  });

  group('selection glow', () {
    test('glows at the start (continuing the selection) and fades out', () {
      final p = build(scenarios['1 unit']!.$1, scenarios['1 unit']!.$2).plan;
      expect(p.frameAt(0).glow, closeTo(1, 1e-9));
      expect(p.frameAt(p.tApproachEnd).glow, closeTo(0, 1e-9));
      expect(p.frameAt(p.tPourEnd).glow, 0);
    });
  });

  group('input safety', () {
    test('only successful moves can be animated', () {
      final state = PuzzleState.fromIds([
        [1],
        [2],
      ]);
      final failed = GameEngine(state).applyMove(const MoveModel(0, 1));
      final layout = BoardLayout.compute(count: 2, width: 300, aspect: 0.42);
      final g = BottleStyles.alchemyClassic.geometryFor(layout.bottleSize, 4);
      expect(
        () => PourPlan.build(
          result: failed,
          geometry: g,
          sourceRect: layout.rects[0],
          destRect: layout.rects[1],
          boardWidth: 300,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
