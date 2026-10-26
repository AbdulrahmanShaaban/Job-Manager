import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Arabic month and weekday names for every date shown in the UI.
  await initializeDateFormatting('ar');
  // Restore a user-configured server URL (if any) so release builds can point
  // at a backend without being rebuilt.
  try {
    final stored = await SessionStore().readApiBaseUrl();
    if (stored != null && stored.isNotEmpty) {
      AppConfig.setRuntimeOverride(stored);
    }
  } catch (_) {
    // Secure storage may be unavailable on some platforms; fall back to the
    // build-time define (or the developer loopback in debug).
  }
  runApp(const ProviderScope(child: JobManagerApp()));
}
