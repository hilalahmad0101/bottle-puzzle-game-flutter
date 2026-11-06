import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/settings_providers.dart';

/// Master switch for decorative, endlessly looping animation (drifting
/// motes, pulsing rings). On in the app; tests turn it off so that
/// `pumpAndSettle` can finish.
final ambientMotionProvider = Provider<bool>((ref) => true);

/// Whether decorative looping motion may run now: the master switch is on
/// and the player/OS has not asked for reduced motion.
bool ambientMotionAllowed(BuildContext context, WidgetRef ref) {
  if (!ref.watch(ambientMotionProvider)) return false;
  final reduced = ref
      .watch(animationSettingsProvider)
      .isReduced(
        systemPrefersReduced:
            MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      );
  return !reduced;
}
