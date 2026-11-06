import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/progress/application/providers.dart';
import 'features/progress/data/legacy_prefs.dart';
import 'features/progress/data/sqlite_progress_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Nothing is awaited before the first frame: the splash screen is shown
  // at once and the database opens (and upgrades) behind it.
  runApp(
    ProviderScope(
      overrides: [
        progressRepositoryProvider.overrideWithValue(
          SqliteProgressRepository(legacy: LegacyPrefs()),
        ),
      ],
      child: const PrismPourApp(),
    ),
  );
}
