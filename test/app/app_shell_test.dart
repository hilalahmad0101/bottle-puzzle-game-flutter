import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/app.dart';
import 'package:prism_pour/features/home/presentation/home_screen.dart';
import 'package:prism_pour/features/splash/presentation/splash_screen.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('starts on the splash screen, then moves to home', (
    tester,
  ) async {
    final c = await readyContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PrismPourApp()),
    );
    expect(find.byType(SplashScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('home offers play, levels, collection and settings', (
    tester,
  ) async {
    final c = await readyContainer();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const PrismPourApp()),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    for (final k in [
      'home.play',
      'home.levels',
      'home.collection',
      'home.settings',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
  });
}
