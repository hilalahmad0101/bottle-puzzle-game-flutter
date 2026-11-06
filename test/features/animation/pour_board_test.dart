import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/engine/models/puzzle_state.dart';
import 'package:prism_pour/features/game/animation/animation_settings.dart';
import 'package:prism_pour/features/game/animation/board_layout.dart';
import 'package:prism_pour/features/game/animation/pour_board.dart';
import 'package:prism_pour/features/game/animation/pour_overlay_painter.dart';
import 'package:prism_pour/features/game/application/board_controller.dart';
import 'package:prism_pour/features/game/rendering/bottle_static_layers.dart';
import 'package:prism_pour/features/game/rendering/bottle_style.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/game/rendering/completed_bottle_effect.dart';
import 'package:prism_pour/features/game/rendering/liquid_palette.dart';
import 'package:prism_pour/features/game/rendering/liquid_volume_model.dart';

const boardWidth = 420.0;

PuzzleState st(List<List<int>> b) => PuzzleState.fromIds(b);

/// 0:[2,1,1] 1:[1] 2:[] 3:[3,3,3,3]   -> 0 -> 1 pours 2 units
BoardController make() => BoardController(
  st([
    [2, 1, 1],
    [1],
    [],
    [3, 3, 3, 3],
  ]),
);

final palette = LiquidPalette.forColorIds([1, 2, 3]);

Widget host(
  BoardController c, {
  AnimationSettings settings = const AnimationSettings(),
  ValueNotifier<double?>? scrub,
  BottleLayerCache? cache,
  double width = boardWidth,
  bool reduceOs = false,
  GlobalKey<PourBoardState>? key,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceOs),
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: PourBoard(
              key: key,
              controller: c,
              palette: palette,
              settings: settings,
              scrub: scrub,
              cache: cache,
            ),
          ),
        ),
      ),
    ),
  );
}

Finder overlay() => find.byWidgetPredicate(
  (w) => w is CustomPaint && w.painter is PourOverlayPainter,
);

/// Screen position of bottle [i] on a 420-wide board.
Offset bottleCenter(
  WidgetTester tester,
  int i,
  int count, {
  double width = boardWidth,
}) {
  final layout = BoardLayout.compute(
    count: count,
    width: width,
    aspect: BottleStyles.alchemyClassic.spec.aspect,
  );
  final origin = tester.getTopLeft(find.byType(PourBoard));
  return origin + layout.rects[i].center;
}

Future<void> tapBottle(WidgetTester tester, int i, int count) async {
  await tester.tapAt(bottleCenter(tester, i, count));
  await tester.pump();
}

void main() {
  late BottleLayerCache cache;
  setUp(() => cache = BottleLayerCache());

  group('tap -> pour -> settle', () {
    testWidgets('selecting lifts the bottle and shows the halo, no pour yet', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      expect(c.selectedIndex, 0);
      expect(c.isPouring, isFalse);
      expect(overlay(), findsNothing);
      final views = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .toList();
      expect(views[0].selected, isTrue);
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets(
      'a second tap commits the move at once and starts the animation',
      (tester) async {
        final c = make();
        final before = c.committedState;
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        // Game state is final immediately; the animation is just a replay.
        expect(c.engine.moveCount, 1);
        expect(c.committedState, isNot(before));
        expect(c.isPouring, isTrue);
        expect(overlay(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('the two bottles are hidden while the overlay draws them', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      // 2 of 4 static bottles are offstage during the pour.
      expect(find.byType(BottleView), findsNWidgets(2));
      expect(find.byType(BottleView, skipOffstage: false), findsNWidgets(4));
      await tester.pumpAndSettle();
      expect(find.byType(BottleView), findsNWidgets(4));
    });

    testWidgets('runs to completion by itself and releases input', (
      tester,
    ) async {
      final c = make();
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(host(c, cache: cache, key: key));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      final duration = key.currentState!.currentPlan!.duration;
      await tester.pump(Duration(milliseconds: (duration * 500).round()));
      expect(c.isPouring, isTrue, reason: 'half-way through');
      await tester.pump(Duration(milliseconds: (duration * 520).round()));
      await tester.pump();
      expect(c.isPouring, isFalse);
      expect(overlay(), findsNothing);
      expect(
        c.engine.moveCount,
        1,
        reason: 'finishing never re-applies the move',
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('after settling you can start the next pour', (tester) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pumpAndSettle();
      await tapBottle(tester, 1, 4);
      await tapBottle(tester, 2, 4);
      expect(c.engine.moveCount, 2);
      await tester.pumpAndSettle();
      expect(c.isPouring, isFalse);
    });

    testWidgets('the board renders the committed state once settled', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pumpAndSettle();
      final views = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .toList();
      for (var i = 0; i < 4; i++) {
        expect(views[i].bottle, c.committedState.bottles[i]);
      }
    });
  });

  group('no conflicting input during a pour', () {
    testWidgets('taps on any bottle while pouring change nothing', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      final snapshot = c.committedState;
      await tester.pump(const Duration(milliseconds: 300));
      for (final i in [0, 1, 2, 3, 2, 1]) {
        await tapBottle(tester, i, 4);
      }
      expect(c.engine.moveCount, 1);
      expect(c.committedState, snapshot);
      expect(c.selectedIndex, isNull);
      expect(c.isPouring, isTrue);
      await tester.pumpAndSettle();
      expect(c.engine.moveCount, 1);
    });

    testWidgets('hammering the same destination never applies the move twice', (
      tester,
    ) async {
      final c = BoardController(
        st([
          [1, 1],
          [1],
          [],
        ]),
      );
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 3);
      for (var i = 0; i < 15; i++) {
        await tapBottle(tester, 1, 3);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(c.engine.moveCount, 1);
      await tester.pumpAndSettle();
      expect(c.engine.moveCount, 1);
    });
  });

  group('interruptions: the committed game is never affected', () {
    testWidgets('app backgrounded mid-pour: animation dropped, state final', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      final committed = c.committedState;
      await tester.pump(const Duration(milliseconds: 400));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(c.isPouring, isFalse);
      expect(c.lastInterruption, InterruptReason.background);
      expect(overlay(), findsNothing);
      expect(c.committedState, committed);
      expect(c.engine.moveCount, 1);
      // Back to the app: nothing weird, input works.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tapBottle(tester, 3, 4);
      expect(c.selectedIndex, 3);
    });

    testWidgets('inactive and hidden also drop the replay', (tester) async {
      for (final s in [AppLifecycleState.inactive, AppLifecycleState.hidden]) {
        final c = make();
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        await tester.pump(const Duration(milliseconds: 200));
        tester.binding.handleAppLifecycleStateChanged(s);
        await tester.pump();
        expect(c.isPouring, isFalse, reason: '$s');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('leaving the screen mid-pour does not strand the controller', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pump(const Duration(milliseconds: 300));
      final committed = c.committedState;
      await tester.pumpWidget(
        const MaterialApp(home: SizedBox()),
      ); // navigated away
      await tester.pump();
      await tester.pump();
      expect(c.isPouring, isFalse, reason: 'no view left to finish it');
      expect(c.lastInterruption, InterruptReason.navigation);
      expect(c.committedState, committed);
      expect(c.engine.moveCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('returning to a fresh board shows the committed result', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump();
      await tester.pumpWidget(host(c, cache: cache));
      await tester.pump();
      final views = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .toList();
      expect(views.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(views[i].bottle, c.committedState.bottles[i]);
      }
      expect(overlay(), findsNothing);
    });

    testWidgets('reset mid-pour stops the animation and restores the level', (
      tester,
    ) async {
      final c = make();
      final start = c.committedState;
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pump(const Duration(milliseconds: 300));
      c.reset();
      await tester.pump();
      expect(overlay(), findsNothing);
      expect(c.committedState, start);
      expect(c.engine.moveCount, 0);
      await tester.pumpAndSettle(); // must not hang on a zombie ticker
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets(
      'undo mid-pour: state is back at once and the liquid flows back',
      (tester) async {
        final c = make();
        final start = c.committedState;
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        await tester.pump(const Duration(milliseconds: 300));
        c.undo();
        expect(c.committedState, start, reason: 'the game is back at once');
        await tester.pump();
        expect(c.activePour!.isUndo, isTrue);
        expect(overlay(), findsOneWidget, reason: 'the liquid flows back');
        await tester.pumpAndSettle();
        expect(overlay(), findsNothing);
        expect(c.isPouring, isFalse);
        final views = tester
            .widgetList<BottleView>(find.byType(BottleView))
            .toList();
        for (var i = 0; i < 4; i++) {
          expect(views[i].bottle, start.bottles[i]);
        }
      },
    );

    testWidgets(
      'pause mid-pour locks input and removes the half-poured bottle',
      (tester) async {
        final c = make();
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        await tester.pump(const Duration(milliseconds: 250));
        c.pause();
        await tester.pump();
        expect(overlay(), findsNothing);
        await tapBottle(tester, 3, 4);
        expect(c.selectedIndex, isNull, reason: 'paused: taps ignored');
        c.resume();
        await tapBottle(tester, 3, 4);
        expect(c.selectedIndex, 3);
      },
    );

    testWidgets(
      'an unexpected size change under a running pour drops it safely',
      (tester) async {
        final c = make();
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pumpWidget(host(c, cache: cache, width: 320));
        await tester.pump();
        await tester.pump();
        expect(c.isPouring, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('loading a new level mid-pour', (tester) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pump(const Duration(milliseconds: 250));
      c.loadLevel(
        st([
          [1],
          [],
          [],
        ]),
      );
      await tester.pump();
      expect(find.byType(BottleView), findsNWidgets(3));
      expect(overlay(), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a pour started right after an interrupted one animates cleanly',
      (tester) async {
        final c = make();
        await tester.pumpWidget(host(c, cache: cache));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        await tester.pump(const Duration(milliseconds: 250));
        c.interruptPour();
        await tester.pump();
        await tapBottle(tester, 1, 4);
        await tapBottle(tester, 2, 4);
        expect(c.isPouring, isTrue);
        expect(overlay(), findsOneWidget);
        await tester.pumpAndSettle();
        expect(c.isPouring, isFalse);
        expect(c.engine.moveCount, 2);
      },
    );
  });

  group('settings', () {
    testWidgets('fast speed finishes sooner than normal', (tester) async {
      Future<double> run(AnimationSpeed speed) async {
        final c = make();
        final key = GlobalKey<PourBoardState>();
        await tester.pumpWidget(
          host(
            c,
            settings: AnimationSettings(speed: speed),
            cache: cache,
            key: key,
          ),
        );
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        final d = key.currentState!.currentPlan!.duration;
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        return d;
      }

      final normal = await run(AnimationSpeed.normal);
      final fast = await run(AnimationSpeed.fast);
      expect(fast, closeTo(normal * 0.6, 1e-9));
    });

    testWidgets('reduced motion setting uses the short, still animation', (
      tester,
    ) async {
      final c = make();
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(
        host(
          c,
          settings: const AnimationSettings(motion: MotionPreference.on),
          cache: cache,
          key: key,
        ),
      );
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      final plan = key.currentState!.currentPlan!;
      expect(plan.reduced, isTrue);
      expect(plan.duration, lessThan(0.5));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(c.isPouring, isFalse);
    });

    testWidgets('"system" follows the OS reduce-motion flag', (tester) async {
      for (final os in [true, false]) {
        final c = make();
        final key = GlobalKey<PourBoardState>();
        await tester.pumpWidget(host(c, cache: cache, key: key, reduceOs: os));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        expect(key.currentState!.currentPlan!.reduced, os);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('"off" ignores the OS flag', (tester) async {
      final c = make();
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(
        host(
          c,
          settings: const AnimationSettings(motion: MotionPreference.off),
          cache: cache,
          key: key,
          reduceOs: true,
        ),
      );
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      expect(key.currentState!.currentPlan!.reduced, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets(
      'the settings used are the ones at the moment the pour starts',
      (tester) async {
        final c = make();
        final key = GlobalKey<PourBoardState>();
        await tester.pumpWidget(host(c, cache: cache, key: key));
        await tapBottle(tester, 0, 4);
        await tapBottle(tester, 1, 4);
        final first = key.currentState!.currentPlan!;
        await tester.pumpWidget(
          host(
            c,
            settings: const AnimationSettings(speed: AnimationSpeed.fast),
            cache: cache,
            key: key,
          ),
        );
        expect(
          identical(key.currentState!.currentPlan, first),
          isTrue,
          reason: 'mid-pour plan is not rebuilt',
        );
        await tester.pumpAndSettle();
      },
    );
  });

  group('completion celebration waits for the pour', () {
    testWidgets('the solved bottle celebrates only after the pour ends', (
      tester,
    ) async {
      final c = BoardController(
        st([
          [1, 1, 1],
          [1],
          [],
        ]),
      );
      await tester.pumpWidget(host(c, cache: cache));
      await tapBottle(tester, 1, 3);
      await tapBottle(tester, 0, 3);
      expect(c.engine.isLevelCompleted(), isTrue);
      expect(c.levelCompleteVisible, isFalse);
      // Hidden static bottles are told NOT to celebrate yet.
      final during = tester
          .widgetList<BottleView>(find.byType(BottleView, skipOffstage: false))
          .toList();
      expect(during[0].completed, isFalse);
      expect(during[1].completed, isFalse);
      await tester.pumpAndSettle();
      expect(c.levelCompleteVisible, isTrue);
      final after = tester
          .widgetList<BottleView>(find.byType(BottleView))
          .toList();
      expect(after[0].completed, isNull);
      expect(find.byType(CompletedBottleEffect), findsWidgets);
    });
  });

  group('scrubbing (debug)', () {
    testWidgets('a frozen scrub value stops the animation from finishing', (
      tester,
    ) async {
      final c = make();
      final scrub = ValueNotifier<double?>(0.5);
      final key = GlobalKey<PourBoardState>();
      await tester.pumpWidget(host(c, scrub: scrub, cache: cache, key: key));
      await tapBottle(tester, 0, 4);
      await tapBottle(tester, 1, 4);
      await tester.pump(const Duration(seconds: 10));
      expect(c.isPouring, isTrue, reason: 'frozen');
      expect(key.currentState!.currentPlan, isNotNull);
      scrub.value = 0.8;
      await tester.pump();
      scrub.value = null; // resume from where it was scrubbed to
      await tester.pumpAndSettle();
      expect(c.isPouring, isFalse);
      expect(c.engine.moveCount, 1);
    });
  });

  group('performance warm-up', () {
    testWidgets(
      'tilt solves are done right after the board appears, before the first pour',
      (tester) async {
        final c = make();
        final key = GlobalKey<PourBoardState>();
        await tester.pumpWidget(host(c, cache: cache, key: key));
        await tester
            .pump(); // the post-frame warm-up runs after the first frame
        final g = key.currentState!.debugGeometry!;
        final model = LiquidVolumeModel.of(g);
        for (final fill in LiquidVolumeModel.warmUpFills(g.capacity)) {
          expect(model.isTiltWarm(fill), isTrue, reason: 'fill $fill');
        }
      },
    );

    test('the warm-up covers every fill a pour samples', () {
      final fills = LiquidVolumeModel.warmUpFills(4).toList();
      expect(fills.length, 17);
      expect(fills.first, 4);
      expect(fills.last, 0);
      // PourPlan samples at quarter-unit steps from an integer fill.
      for (var before = 1; before <= 4; before++) {
        for (var q = 1; q <= before; q++) {
          for (var i = 0; i <= q * 4; i++) {
            final f = before + (before - q - before) * i / (q * 4);
            expect(
              fills.contains(f),
              isTrue,
              reason: '$before - $q at $i -> $f',
            );
          }
        }
      }
    });
  });

  group('robustness', () {
    testWidgets('twelve bottles on a 320 px phone, many pours, no exceptions', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = BoardController(
        st([
          for (var i = 0; i < 10; i++) [i % 5, (i + 1) % 5, (i + 2) % 5],
          [],
          [],
        ]),
      );
      await tester.pumpWidget(host(c, cache: cache, width: 320));
      for (var n = 0; n < 6; n++) {
        final legal = c.engine.getLegalMoves();
        if (legal.isEmpty) break;
        final m = legal[n % legal.length];
        await tapBottle(tester, m.source, 12);
        await tester.tapAt(bottleCenter(tester, m.destination, 12, width: 320));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(c.isPouring, isFalse);
    });

    testWidgets('rapid random interruption never leaves a stuck animation', (
      tester,
    ) async {
      final c = make();
      await tester.pumpWidget(host(c, cache: cache));
      for (var i = 0; i < 12; i++) {
        final legal = c.engine.getLegalMoves();
        if (legal.isEmpty) break;
        final m = legal[i % legal.length];
        await tapBottle(tester, m.source, 4);
        await tapBottle(tester, m.destination, 4);
        await tester.pump(Duration(milliseconds: 50 + (i * 97) % 700));
        switch (i % 4) {
          case 0:
            c.interruptPour();
          case 1:
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          case 2:
            c.undo();
          case 3:
            await tester.pump(const Duration(seconds: 3));
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(c.engine.isStateValid(), isTrue);
      }
      await tester.pumpAndSettle();
      expect(c.isPouring, isFalse);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
