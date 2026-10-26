import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/session_store.dart';
import '../data/api_repository.dart';
import '../data/local_db.dart';
import '../data/mutations.dart';
import '../data/sync_service.dart';
import '../models/json.dart';
import '../models/user.dart';

// ---------------------------------------------------------------- plumbing

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository(ref.watch(apiClientProvider));
});

final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb();
  ref.onDispose(db.close);
  return db;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(api: ref.watch(apiRepositoryProvider), db: ref.watch(localDbProvider));
});

final mutationsProvider = Provider<Mutations>((ref) {
  return Mutations(
    api: ref.watch(apiRepositoryProvider),
    db: ref.watch(localDbProvider),
    sync: ref.watch(syncServiceProvider),
  );
});

// ------------------------------------------------------------------- auth

class AuthState {
  const AuthState({this.user, this.workspaces = const [], this.offline = false});

  final AppUser? user;
  final List<Workspace> workspaces;

  /// True when the session was restored from cache because the server was
  /// unreachable. Cached data stays readable and writes queue up.
  final bool offline;

  bool get isAuthenticated => user != null;

  static const AuthState signedOut = AuthState();
}

class AuthController extends AsyncNotifier<AuthState> {
  static const String _cacheKey = 'auth_user';

  @override
  Future<AuthState> build() async {
    final store = ref.read(sessionStoreProvider);
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);

    final token = await store.readToken();
    if (token == null || token.isEmpty) return AuthState.signedOut;

    client.setToken(token);
    try {
      final me = await ref.read(apiRepositoryProvider).me();
      await _cacheUser(db, me.user, me.workspaces);
      return AuthState(user: me.user, workspaces: me.workspaces);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        client.setToken(null);
        await store.clearToken();
        return AuthState.signedOut;
      }
      final cached = await _readCachedUser(db);
      if (cached != null) {
        return AuthState(user: cached.user, workspaces: cached.workspaces, offline: true);
      }
      return AuthState.signedOut;
    }
  }

  Future<void> login({required String email, required String password}) async {
    final session = await ref
        .read(apiRepositoryProvider)
        .login(email: email, password: password);
    await _applySession(session);
  }

  Future<void> acceptInvitation({
    required String code,
    required String name,
    required String password,
  }) async {
    final session = await ref
        .read(apiRepositoryProvider)
        .acceptInvitation(token: code, name: name, password: password);
    await _applySession(session);
  }

  Future<void> _applySession(AuthSession session) async {
    final client = ref.read(apiClientProvider);
    final store = ref.read(sessionStoreProvider);
    final db = ref.read(localDbProvider);

    client.setToken(session.token);
    await store.writeToken(session.token);
    await store.writeLastEmail(session.user.email);
    await _cacheUser(db, session.user, session.workspaces);

    state = AsyncData(AuthState(user: session.user, workspaces: session.workspaces));
  }

  Future<void> logout() async {
    final client = ref.read(apiClientProvider);
    final store = ref.read(sessionStoreProvider);
    final db = ref.read(localDbProvider);

    try {
      await ref.read(apiRepositoryProvider).logout();
    } catch (_) {
      // Revoking the local session is what matters for this device.
    }
    client.setToken(null);
    await store.clearToken();
    await db.clearAll();
    state = const AsyncData(AuthState.signedOut);
  }

  /// Re-checks the session after a network failure.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(build);
  }

  Future<void> _cacheUser(LocalDb db, AppUser user, List<Workspace> workspaces) async {
    await db.writeSetting(
      _cacheKey,
      jsonEncode({
        'user': user.toJson(),
        'workspaces': workspaces.map((workspace) => workspace.toJson()).toList(),
      }),
    );
  }

  Future<({AppUser user, List<Workspace> workspaces})?> _readCachedUser(LocalDb db) async {
    final raw = await db.readSetting(_cacheKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return (
        user: AppUser.fromJson(asMap(json['user'])),
        workspaces: asMapList(json['workspaces']).map(Workspace.fromJson).toList(growable: false),
      );
    } catch (_) {
      return null;
    }
  }
}

final authProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience accessors used by screens.
AppUser? currentUserOf(WidgetRef ref) => ref.watch(authProvider).value?.user;

// --------------------------------------------------------------- settings

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.speakReplies = true,
    this.keepTranscripts = true,
  });

  final ThemeMode themeMode;

  /// Read assistant replies aloud using the device TTS engine (free).
  final bool speakReplies;

  /// Whether a voice transcript may be attached to a visit.
  final bool keepTranscripts;

  AppSettings copyWith({ThemeMode? themeMode, bool? speakReplies, bool? keepTranscripts}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      speakReplies: speakReplies ?? this.speakReplies,
      keepTranscripts: keepTranscripts ?? this.keepTranscripts,
    );
  }
}

class SettingsController extends AsyncNotifier<AppSettings> {
  static const String _themeKey = 'theme_mode';
  static const String _speakKey = 'speak_replies';
  static const String _transcriptKey = 'keep_transcripts';

  @override
  Future<AppSettings> build() async {
    final db = ref.read(localDbProvider);
    final theme = await db.readSetting(_themeKey);
    final speak = await db.readSetting(_speakKey);
    final transcripts = await db.readSetting(_transcriptKey);
    return AppSettings(
      themeMode: switch (theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      speakReplies: speak != 'false',
      keepTranscripts: transcripts != 'false',
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = state.value ?? const AppSettings();
    await ref.read(localDbProvider).writeSetting(_themeKey, mode.name);
    state = AsyncData(current.copyWith(themeMode: mode));
  }

  Future<void> setSpeakReplies(bool value) async {
    final current = state.value ?? const AppSettings();
    await ref.read(localDbProvider).writeSetting(_speakKey, value.toString());
    state = AsyncData(current.copyWith(speakReplies: value));
  }

  Future<void> setKeepTranscripts(bool value) async {
    final current = state.value ?? const AppSettings();
    await ref.read(localDbProvider).writeSetting(_transcriptKey, value.toString());
    state = AsyncData(current.copyWith(keepTranscripts: value));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
