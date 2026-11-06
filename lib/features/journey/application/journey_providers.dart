import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../progress/application/providers.dart';
import '../domain/journey.dart';

/// Where the player is on the Alchemy Journey: one chapter per milestone of
/// completed levels (the first level not yet completed is `currentLevel`, so
/// `currentLevel - 1` levels are done).
///
/// Before the saved progress has loaded (the splash screen, or a failed load)
/// the player is at the very start of the journey.
final journeyProvider = Provider<JourneyPosition>((ref) {
  if (!ref.watch(bootstrapProvider.select((b) => b.hasValue))) {
    return Journey.start;
  }
  final done = ref.watch(progressProvider.select((p) => p.currentLevel - 1));
  return Journey.at(done);
});

/// Just the palette, so a screen that only paints the backdrop is not
/// rebuilt by progress inside a chapter.
final journeyStageProvider = Provider<JourneyStage>((ref) {
  return ref.watch(journeyProvider.select((p) => p.stage));
});
