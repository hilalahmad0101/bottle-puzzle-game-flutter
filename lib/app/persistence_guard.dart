import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/progress/application/providers.dart';

/// Makes sure everything accepted so far is written to disk whenever the app
/// leaves the foreground (home button, app switcher, an incoming call, the
/// process about to be killed).
///
/// Games are already saved after every committed move, so this only drains
/// the small write queue. It cannot recover a move that was never committed.
class PersistenceGuard extends ConsumerStatefulWidget {
  const PersistenceGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PersistenceGuard> createState() => _PersistenceGuardState();
}

class _PersistenceGuardState extends ConsumerState<PersistenceGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    unawaited(
      ref.read(progressRepositoryProvider).flush().catchError((Object e) {
        debugPrint('Could not flush saved data: $e');
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
