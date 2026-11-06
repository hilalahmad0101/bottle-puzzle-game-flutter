import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_pour/app/app.dart';
import 'package:prism_pour/app/router/app_router.dart';

/// Phone and tablet screens used by the responsive tests (logical pixels).
const Map<String, Size> screens = {
  'small 320x568': Size(320, 568),
  'compact 360x640': Size(360, 640),
  'tall 393x873': Size(393, 873),
  'large 412x915': Size(412, 915),
  'tablet 800x1280': Size(800, 1280),
  'landscape 844x390': Size(844, 390),
  'wide landscape 915x412': Size(915, 412),
};

void setScreen(
  WidgetTester tester,
  Size size, {
  double textScale = 1.0,
  EdgeInsets safe = EdgeInsets.zero,
}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  tester.view.padding = FakeViewPadding(
    left: safe.left,
    top: safe.top,
    right: safe.right,
    bottom: safe.bottom,
  );
  tester.view.viewPadding = tester.view.padding;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Starts the real app on [location] (skipping the splash delay).
Future<GoRouterLike> pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  String location = '/home',
  Size size = const Size(393, 873),
  double textScale = 1.0,
  EdgeInsets safe = EdgeInsets.zero,

  /// Wait for every animation to finish. Off for tests that run with endless
  /// decorative motion on, which can never settle.
  bool settle = true,
}) async {
  setScreen(tester, size, textScale: textScale, safe: safe);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PrismPourApp(),
    ),
  );
  final router = container.read(appRouterProvider);
  router.go(location);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  return GoRouterLike(router);
}

/// A tiny wrapper so tests do not import go_router everywhere.
class GoRouterLike {
  GoRouterLike(this._r);
  final dynamic _r;
  void go(String l) => _r.go(l);
  void push(String l) => _r.push(l);
  void pop() => _r.pop();
}

/// Removes the app so timers and tickers are disposed.
Future<void> leaveApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}
