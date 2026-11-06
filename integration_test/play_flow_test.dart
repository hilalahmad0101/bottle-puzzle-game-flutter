import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prism_pour/features/game/presentation/game_screen.dart';
import 'package:prism_pour/features/home/presentation/home_screen.dart';
import 'package:prism_pour/features/splash/presentation/splash_screen.dart';
import 'package:prism_pour/main.dart' as app;

String where() =>
    'splash=${find.byType(SplashScreen).evaluate().length} home=${find.byType(HomeScreen).evaluate().length} game=${find.byType(GameScreen).evaluate().length} loading=${find.byKey(const Key('game.loading')).evaluate().length} failed=${find.byKey(const Key('game.failed')).evaluate().length} board=${find.byKey(const Key('game.level')).evaluate().length}';

/// Runs the REAL app on a device/simulator: real storage, real isolate-based
/// level generation, real splash. Taps Play and checks the board appears.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('splash -> home -> Play shows the board', (tester) async {
    app.main();
    for (var i = 0; i < 150 && find.byKey(const Key('home.play')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('STATE after startup: ${where()}');
    expect(find.byKey(const Key('home.play')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home.play')));
    final sw = Stopwatch()..start();
    for (var i = 0; i < 150 && find.byKey(const Key('game.level')).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('STATE after Play (${sw.elapsedMilliseconds} ms): ${where()}');
    expect(find.byKey(const Key('game.level')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
