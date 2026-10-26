import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The bearer session token lives only in platform secure storage.
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(),
          );

  static const String _tokenKey = 'job_manager.session_token';
  static const String _emailKey = 'job_manager.last_email';
  static const String _apiUrlKey = 'job_manager.api_base_url';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> writeToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<String?> readLastEmail() => _storage.read(key: _emailKey);

  Future<void> writeLastEmail(String email) => _storage.write(key: _emailKey, value: email);

  Future<String?> readApiBaseUrl() => _storage.read(key: _apiUrlKey);

  Future<void> writeApiBaseUrl(String url) =>
      _storage.write(key: _apiUrlKey, value: url.trim());

  Future<void> clearApiBaseUrl() => _storage.delete(key: _apiUrlKey);
}
