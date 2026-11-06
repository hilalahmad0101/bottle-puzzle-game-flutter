import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/app.dart';
import 'package:prism_pour/app/router/app_router.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/game/rendering/bottle_view.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';

import '../../support/pump_app.dart';
import '../../support/test_app.dart';

/// A notch / gesture bar sized for the screen shape.
EdgeInsets safeFor(Size s) {
  if (s.width > s.height) {
    return const EdgeInsets.fromLTRB(48, 0, 48, 21); // landscape notch
  }
  if (s.width >= 700) return const EdgeInsets.only(top: 24, bottom: 20);
  return const EdgeInsets.only(top: 44, bottom: 34);
}

Rect safeRect(Size s) {
  final e = safeFor(s);
  return Rect.fromLTRB(e.left, e.top, s.width - e.right, s.height - e.bottom);
}

bool inside(Rect r, Rect area) =>
    r.left >= area.left - 0.5 &&
    r.top >= area.top - 0.5 &&
    r.right <= area.right + 0.5 &&
    r.bottom <= area.bottom + 0.5;

PlayerProgress progress(int done) => PlayerProgress(
  records: {
    for (var l = 1; l <= done; l++)
      l: const LevelRecord(stars: 2, bestMoves: 20),
  },
);

Future<ProviderContainer> start(
  WidgetTester tester,
  Size size,
  String location, {
  double scale = 1,
  PlayerProgress? p,
}) async {
  final c = await readyContainer(progress: p);
  addTearDown(c.dispose);
  await pumpApp(
    tester,
    c,
    location: location,
    size: size,
    textScale: scale,
    safe: safeFor(size),
  );
  return c;
}

/// Opens the real play screen on [level] (levels are not gated by the test).
Future<ProviderContainer> openGame(
  WidgetTester tester,
  Size size,
  int level, {
  double scale = 1,
}) async {
  final c = await readyContainer();
  addTearDown(c.dispose);
  await pumpApp(tester, c, size: size, textScale: scale, safe: safeFor(size));
  final load = c.read(gameSessionProvider).startLevel(level);
  c.read(appRouterProvider).push('/play');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await load;
  await tester.pumpAndSettle();
  return c;
}

void main() {
  group('menu screens never overflow, on any screen or text size', () {
    for (final entry in screens.entries) {
      for (final scale in [1.0, 1.6]) {
        for (final loc in ['/home', '/levels', '/collection', '/settings']) {
          testWidgets('$loc @ ${entry.key} text x$scale', (tester) async {
            await start(tester, entry.value, loc, scale: scale, p: progress(7));
            expect(tester.takeException(), isNull);
            await leaveApp(tester);
          });
        }
      }
    }
  });

  group('home screen keeps its actions reachable', () {
    for (final entry in screens.entries) {
      testWidgets(
        'all buttons can be reached and fit the width @ ${entry.key}',
        (tester) async {
          await start(tester, entry.value, '/home', scale: 1.3);
          final area = safeRect(entry.value);
          for (final k in ['home.play', 'home.levels', 'home.collection']) {
            final f = find.byKey(Key(k));
            await tester.ensureVisible(f);
            await tester.pump();
            final r = tester.getRect(f);
            expect(r.left, greaterThanOrEqualTo(area.left), reason: k);
            expect(r.right, lessThanOrEqualTo(area.right), reason: k);
            expect(
              r.height,
              greaterThanOrEqualTo(48),
              reason: '$k is a comfortable tap target',
            );
          }
          final settings = tester.getRect(
            find.byKey(const Key('home.settings')),
          );
          expect(
            inside(settings, safeRect(entry.value)),
            isTrue,
            reason: 'settings button is inside the safe area',
          );
          expect(settings.shortestSide, greaterThanOrEqualTo(44));
          await leaveApp(tester);
        },
      );
    }
  });

  group('the playing screen fits every screen', () {
    for (final entry in screens.entries) {
      for (final level in [7, 40, 150]) {
        testWidgets(
          'level $level @ ${entry.key}: nothing clipped, nothing overlapping',
          (tester) async {
            final size = entry.value;
            final c = await openGame(tester, size, level);
            expect(tester.takeException(), isNull);
            final area = safeRect(size);
            final count = c
                .read(gameSessionProvider)
                .board!
                .committedState
                .bottleCount;

            final bottles = [
              for (var i = 0; i < count; i++)
                tester.getRect(find.byType(BottleView).at(i)),
            ];
            expect(bottles.length, count);
            for (var i = 0; i < count; i++) {
              expect(
                inside(bottles[i], area),
                isTrue,
                reason: 'bottle $i ${bottles[i]} must be inside $area',
              );
              expect(
                bottles[i].width,
                greaterThanOrEqualTo(22),
                reason: 'bottle $i is big enough to play',
              );
              for (var j = i + 1; j < count; j++) {
                expect(
                  bottles[i].overlaps(bottles[j]),
                  isFalse,
                  reason: 'bottles $i and $j overlap',
                );
              }
            }

            final controls = {
              for (final k in [
                'game.pause',
                'game.undo',
                'game.hint',
                'game.restart',
              ])
                k: tester.getRect(find.byKey(Key(k))),
            };
            for (final e in controls.entries) {
              expect(
                inside(e.value, area),
                isTrue,
                reason: '${e.key} ${e.value} must be inside $area',
              );
              expect(
                e.value.shortestSide,
                greaterThanOrEqualTo(44),
                reason: '${e.key} tap target',
              );
              for (final b in bottles) {
                expect(
                  e.value.overlaps(b),
                  isFalse,
                  reason: '${e.key} must not cover a bottle',
                );
              }
            }
            for (final k in ['game.level', 'game.moves', 'game.par']) {
              expect(
                inside(tester.getRect(find.byKey(Key(k))), area),
                isTrue,
                reason: k,
              );
            }
            await leaveApp(tester);
          },
        );
      }
    }

    for (final entry in screens.entries) {
      testWidgets('large system text does not break the HUD @ ${entry.key}', (
        tester,
      ) async {
        await openGame(tester, entry.value, 7, scale: 2.0);
        expect(tester.takeException(), isNull);
        final area = safeRect(entry.value);
        for (final k in [
          'game.pause',
          'game.undo',
          'game.hint',
          'game.restart',
          'game.level',
          'game.moves',
        ]) {
          expect(
            inside(tester.getRect(find.byKey(Key(k))), area),
            isTrue,
            reason: k,
          );
        }
        await leaveApp(tester);
      });
    }

    testWidgets('portrait uses most of the screen for the bottles', (
      tester,
    ) async {
      final size = screens['tall 393x873']!;
      final c = await openGame(tester, size, 7);
      final count = c
          .read(gameSessionProvider)
          .board!
          .committedState
          .bottleCount;
      final bottles = [
        for (var i = 0; i < count; i++)
          tester.getRect(find.byType(BottleView).at(i)),
      ];
      expect(
        bottles.first.height,
        greaterThan(150),
        reason: 'bottles are large on a big phone',
      );
      await leaveApp(tester);
    });

    testWidgets('bigger screens get bigger bottles than small ones', (
      tester,
    ) async {
      Future<double> height(Size size) async {
        final c = await openGame(tester, size, 7);
        final h = tester.getRect(find.byType(BottleView).first).height;
        c.dispose();
        await leaveApp(tester);
        return h;
      }

      final small = await height(screens['small 320x568']!);
      final big = await height(screens['tall 393x873']!);
      expect(big, greaterThan(small));
    });
  });

  group(
    'overlays and the completion screen fit small screens with big text',
    () {
      for (final entry in screens.entries) {
        testWidgets('pause menu @ ${entry.key}', (tester) async {
          await openGame(tester, entry.value, 7, scale: 1.6);
          await tester.tap(find.byKey(const Key('game.pause')));
          await tester.pumpAndSettle();
          expect(find.text('PAUSED'), findsOneWidget);
          expect(tester.takeException(), isNull);
          for (final k in [
            'pause.resume',
            'pause.restart',
            'pause.settings',
            'pause.home',
          ]) {
            await tester.ensureVisible(find.byKey(Key(k)));
            expect(
              tester.getRect(find.byKey(Key(k))).height,
              greaterThanOrEqualTo(48),
              reason: k,
            );
          }
          await leaveApp(tester);
        });

        testWidgets('completion screen @ ${entry.key}', (tester) async {
          final c = await readyContainer();
          addTearDown(c.dispose);
          await pumpApp(
            tester,
            c,
            size: entry.value,
            textScale: 1.6,
            safe: safeFor(entry.value),
          );
          final s = c.read(gameSessionProvider);
          await s.startLevel(1);
          for (final m in const [(0, 2), (1, 0), (1, 2)]) {
            s.board!.tapBottle(m.$1);
            s.board!.tapBottle(m.$2);
            s.board!.finishPour(s.board!.activePour!.token);
          }
          final router = c.read(appRouterProvider);
          router.push('/play');
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('complete.title')), findsOneWidget);
          for (final k in ['complete.next', 'complete.replay']) {
            await tester.ensureVisible(find.byKey(Key(k)));
            final r = tester.getRect(find.byKey(Key(k)));
            expect(r.height, greaterThanOrEqualTo(48), reason: k);
            expect(
              r.left,
              greaterThanOrEqualTo(safeRect(entry.value).left),
              reason: k,
            );
            expect(
              r.right,
              lessThanOrEqualTo(safeRect(entry.value).right),
              reason: k,
            );
          }
          await leaveApp(tester);
        });
      }
    },
  );

  group('splash', () {
    for (final entry in screens.entries) {
      testWidgets('fits @ ${entry.key}', (tester) async {
        final c = await readyContainer();
        addTearDown(c.dispose);
        setScreen(
          tester,
          entry.value,
          textScale: 1.6,
          safe: safeFor(entry.value),
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const PrismPourApp()),
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        await leaveApp(tester);
      });
    }
  });
}
