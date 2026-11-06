import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/game/application/game_session.dart';
import 'app_routes.dart';

/// Start (or resume) a level and open the play screen. Navigation happens
/// first, so the play screen can show its loading state while the level is
/// generated off the UI thread.
Future<void> openLevel(
  BuildContext context,
  WidgetRef ref,
  int level, {
  bool resume = true,
  bool replaceCurrent = false,
}) async {
  final load = ref.read(gameSessionProvider).startLevel(level, resume: resume);
  if (replaceCurrent) {
    context.pushReplacement(AppRoutes.play);
  } else {
    context.push(AppRoutes.play);
  }
  await load;
}
