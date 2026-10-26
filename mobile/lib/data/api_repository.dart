import 'dart:typed_data';

import '../core/api_client.dart';
import '../models/json.dart';
import '../models/overview.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/user.dart';
import '../models/visit.dart';
import '../models/voice.dart';

/// Every server endpoint used by the app, typed.
class ApiRepository {
  ApiRepository(this._client);

  final ApiClient _client;

  ApiClient get client => _client;

  // ------------------------------------------------------------------ auth

  Future<AuthSession> login({required String email, required String password}) async {
    final json = await _client.post(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> acceptInvitation({
    required String token,
    required String name,
    required String password,
  }) async {
    final json = await _client.post(
      '/auth/accept-invitation',
      body: {'token': token.trim(), 'name': name.trim(), 'password': password},
    );
    return AuthSession.fromJson(json);
  }

  Future<({AppUser user, List<Workspace> workspaces})> me() async {
    final json = await _client.get('/auth/me');
    return (
      user: AppUser.fromJson(asMap(json['user'])),
      workspaces: asMapList(json['workspaces']).map(Workspace.fromJson).toList(growable: false),
    );
  }

  Future<void> logout() => _client.post('/auth/logout');

  Future<List<Workspace>> workspaces() async {
    final json = await _client.get('/workspaces');
    return asMapList(json['workspaces']).map(Workspace.fromJson).toList(growable: false);
  }

  // -------------------------------------------------------------- overview

  Future<Overview> overview() async {
    final json = await _client.get('/overview');
    return Overview.fromJson(asMap(json['overview']));
  }

  // ----------------------------------------------------------------- sites

  Future<List<Site>> sites({SiteScope? scope, SiteStatus? status, String? query}) async {
    final json = await _client.get(
      '/sites',
      query: {
        if (scope != null) 'scope': scope.wire,
        if (status != null) 'status': status.wire,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': 200,
      },
    );
    return asMapList(json['sites']).map(Site.fromJson).toList(growable: false);
  }

  Future<SiteDetail> siteDetail(String siteId) async {
    final json = await _client.get('/sites/$siteId');
    return SiteDetail.fromJson(json);
  }

  Future<Site> createSite(Map<String, dynamic> body) async {
    final json = await _client.post('/sites', body: body);
    return Site.fromJson(asMap(json['site']));
  }

  Future<Site> updateSite(String siteId, Map<String, dynamic> body) async {
    final json = await _client.patch('/sites/$siteId', body: body);
    return Site.fromJson(asMap(json['site']));
  }

  // ---------------------------------------------------------------- visits

  Future<({List<Visit> visits, String? nextCursor})> visits(
    String siteId, {
    int limit = 50,
    String? cursor,
    String? from,
    String? to,
  }) async {
    final json = await _client.get(
      '/sites/$siteId/visits',
      query: {
        'limit': limit,
        'cursor': ?cursor,
        'from': ?from,
        'to': ?to,
      },
    );
    return (
      visits: asMapList(json['visits']).map(Visit.fromJson).toList(growable: false),
      nextCursor: asString(json['nextCursor']),
    );
  }

  Future<Visit> createVisit(String siteId, Map<String, dynamic> body) async {
    final json = await _client.post('/sites/$siteId/visits', body: body);
    return Visit.fromJson(asMap(json['visit']));
  }

  Future<Visit> updateVisit(String visitId, Map<String, dynamic> body) async {
    final json = await _client.patch('/visits/$visitId', body: body);
    return Visit.fromJson(asMap(json['visit']));
  }

  // ----------------------------------------------------------------- tasks

  Future<List<Task>> tasks({
    String? siteId,
    Set<TaskStatus>? statuses,
    String? query,
  }) async {
    final json = await _client.get(
      '/tasks',
      query: {
        'siteId': ?siteId,
        if (statuses != null && statuses.isNotEmpty)
          'status': statuses.map((status) => status.wire).join(','),
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': 300,
      },
    );
    return asMapList(json['tasks']).map(Task.fromJson).toList(growable: false);
  }

  Future<Task> createTask(Map<String, dynamic> body) async {
    final json = await _client.post('/tasks', body: body);
    return Task.fromJson(asMap(json['task']));
  }

  Future<Task> updateTask(String taskId, Map<String, dynamic> body) async {
    final json = await _client.patch('/tasks/$taskId', body: body);
    return Task.fromJson(asMap(json['task']));
  }

  Future<void> deleteTask(String taskId) => _client.delete('/tasks/$taskId');

  // ----------------------------------------------------------------- voice

  Future<VoiceStatus> voiceStatus() async {
    final json = await _client.get('/voice/usage');
    return VoiceStatus.fromJson(json);
  }

  Future<VoiceCredential> voiceCredential() async {
    final json = await _client.post('/voice/session-credential');
    return VoiceCredential.fromJson(json);
  }

  Future<void> completeVoiceSession(
    String sessionId, {
    required String status,
    String? summary,
    String? transcript,
    int? estimatedSeconds,
    String? errorCode,
  }) async {
    await _client.post(
      '/voice/sessions/$sessionId/complete',
      body: {
        'status': status,
        'summary': ?summary,
        'transcript': ?transcript,
        'estimatedSeconds': ?estimatedSeconds,
        'errorCode': ?errorCode,
      },
    );
  }

  Future<Map<String, dynamic>> runTool(
    String name,
    Map<String, dynamic> args, {
    String? sessionId,
  }) async {
    final json = await _client.post(
      '/voice/tool',
      body: {'name': name, 'args': args, 'sessionId': ?sessionId},
    );
    return asMap(json['result']);
  }

  Future<FallbackTurn> fallbackTurn({
    required Uint8List audio,
    required String mimeType,
    required double durationSeconds,
  }) async {
    final json = await _client.postAudio(
      '/voice/fallback-turn',
      bytes: audio,
      mimeType: mimeType,
      query: {'durationSeconds': durationSeconds.toStringAsFixed(1)},
    );
    return FallbackTurn.fromJson(json);
  }

  // ---------------------------------------------------------------- export

  Future<Map<String, dynamic>> exportJson() => _client.get('/export', query: {'format': 'json'});

  /// Raw CSV text for a given entity, ready to be written to a file.
  Future<String> exportCsv(String entity) {
    return _client.getText('/export', query: {'format': 'csv', 'entity': entity});
  }
}
