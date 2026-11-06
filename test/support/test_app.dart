import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:prism_pour/engine/generator/level_generator.dart';
import 'package:prism_pour/features/audio/audio_manager.dart';
import 'package:prism_pour/features/feedback/feedback_service.dart';
import 'package:prism_pour/features/game/application/game_session.dart';
import 'package:prism_pour/features/progress/application/providers.dart';
import 'package:prism_pour/features/progress/data/progress_repository.dart';
import 'package:prism_pour/features/progress/domain/player_progress.dart';
import 'package:prism_pour/features/settings/domain/app_settings.dart';
import 'package:prism_pour/shared/widgets/ambient_motion.dart';

import 'fake_audio.dart';

/// Records haptic/sound calls instead of touching the device.
class RecordingFeedback implements FeedbackPlatform {
  final List<String> calls = [];

  @override
  Future<void> selectionClick() async => calls.add('selectionClick');
  @override
  Future<void> lightImpact() async => calls.add('light');
  @override
  Future<void> mediumImpact() async => calls.add('medium');
  @override
  Future<void> heavyImpact() async => calls.add('heavy');
}

/// A container with in-memory storage whose start-up data is already loaded.
Future<ProviderContainer> readyContainer({
  PlayerProgress? progress,
  AppSettings? settings,
  ProgressRepository? repo,
  RecordingFeedback? feedback,
  FakeAudioBackend? audio,
  bool ambientMotion = false,
  LevelLoader? levelLoader,
  List<Override> overrides = const [],
}) async {
  final r =
      repo ?? MemoryProgressRepository(progress: progress, settings: settings);
  final c = ProviderContainer(
    overrides: [
      progressRepositoryProvider.overrideWithValue(r),
      // Endless background animation would stop pumpAndSettle in tests.
      ambientMotionProvider.overrideWithValue(ambientMotion),
      // Levels are generated synchronously in tests (a real isolate can never
      // finish inside the fake-async test clock).
      levelLoaderProvider.overrideWithValue(
        levelLoader ?? (n) async => const LevelGenerator().generate(n),
      ),
      // No test ever touches a real audio device.
      audioBackendProvider.overrideWithValue(audio ?? FakeAudioBackend()),
      if (feedback != null)
        feedbackPlatformProvider.overrideWithValue(feedback),
      ...overrides,
    ],
  );
  await c.read(bootstrapProvider.future);
  return c;
}

Widget appScope(ProviderContainer c, Widget child) =>
    UncontrolledProviderScope(container: c, child: child);
