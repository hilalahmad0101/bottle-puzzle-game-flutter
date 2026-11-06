import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/audio/audio_manager.dart';

/// Keeps the audio in step with the app's lifecycle: the music pauses when
/// the app goes to the background (home button, another app, a call) and
/// comes back only if it is still switched on. Also starts the audio system
/// with the app, so the first tap never waits for sounds to load.
class AudioGuard extends ConsumerStatefulWidget {
  const AudioGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AudioGuard> createState() => _AudioGuardState();
}

class _AudioGuardState extends ConsumerState<AudioGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Preload now (off the first tap's critical path) and start the music if
    // the saved settings want it.
    final audio = ref.read(audioManagerProvider);
    audio.init();
    audio.syncMusic();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref.read(audioManagerProvider).onLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    // Follow the sound/music switches from the widget tree too: its
    // listeners run with the frame, whatever the container's own scheduling.
    ref.listen(
      audioSwitchesProvider,
      (_, _) => ref.read(audioManagerProvider).syncMusic(),
    );
    return widget.child;
  }
}
