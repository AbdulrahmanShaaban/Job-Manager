import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Runtime configuration.
///
/// The base URL can be overridden at build time:
/// `flutter run --dart-define=API_BASE_URL=https://example.com/api/v1`
class AppConfig {
  const AppConfig._();

  static String? _runtimeOverride;

  static void setRuntimeOverride(String? url) {
    _runtimeOverride = (url == null || url.trim().isEmpty) ? null : url.trim();
  }

  static String? get runtimeOverride => _runtimeOverride;

  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Returns a user-facing explanation when this build cannot reach a server.
  ///
  /// Debug and profile builds fall back to the developer loopback address, but
  /// a release build without `API_BASE_URL` would ship an app that fails every
  /// request with a generic network error, so it is rejected up front.
  static String? get configurationError {
    if (_override.isNotEmpty) return null;
    if (_runtimeOverride != null && _runtimeOverride!.isNotEmpty) return null;
    if (kReleaseMode) {
      return 'لم يُحدد عنوان السيرفر.\n'
          'أدخل عنوان السيرفر في شاشة تسجيل الدخول، أو أعد البناء مع\n'
          '--dart-define=API_BASE_URL=https://<server>/api/v1';
    }
    return null;
  }

  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (_runtimeOverride != null && _runtimeOverride!.isNotEmpty) return _runtimeOverride!;
    if (kReleaseMode) {
      throw StateError(
        'API_BASE_URL was not provided at build time and no runtime override is set.',
      );
    }
    if (!kIsWeb && Platform.isAndroid) {
      // Android emulator loopback to the host machine.
      return 'http://10.0.2.2:3000/api/v1';
    }
    return 'http://127.0.0.1:3000/api/v1';
  }

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 45);
  static const Duration voiceTimeout = Duration(seconds: 120);

  /// Foreground sync cadence while the app is open. There is no background
  /// worker on purpose: the spec forbids a queue service for the MVP.
  static const Duration syncInterval = Duration(seconds: 30);
}
