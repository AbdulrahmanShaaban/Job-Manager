import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/config.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'state/providers.dart';

/// Root widget.
///
/// The app is Arabic-first: the locale is pinned to `ar_EG` and the whole tree
/// is wrapped in an RTL [Directionality] so dialogs, sheets, toasts, and form
/// fields all inherit the correct reading direction.
class JobManagerApp extends ConsumerWidget {
  const JobManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configurationError = AppConfig.configurationError;
    if (configurationError != null) {
      return MaterialApp(
        title: 'مدير الشغل',
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG')],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_ethernet, size: 42, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'إعداد ناقص',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      configurationError,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.7),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();

    return ShadApp.router(
      title: 'مدير الشغل',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: settings.themeMode,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [Locale('ar', 'EG')],
      materialThemeBuilder: (context, theme) => buildMaterialTheme(theme.brightness),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.6,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
