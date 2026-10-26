import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/overview.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/visit.dart';

/// Local SQLite cache plus the pending-write outbox.
///
/// Everything the user has already seen stays readable offline, and every write
/// is queued with a client operation id so a retry cannot duplicate it.
class LocalDb {
  LocalDb({String? path}) : _customPath = path;

  static const int _version = 1;

  final String? _customPath;
  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final path = _customPath ?? p.join(await getDatabasesPath(), 'job_manager.db');
    return openDatabase(
      path,
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        final batch = db.batch();
        batch.execute('''
          CREATE TABLE cache_sites (
            id TEXT PRIMARY KEY,
            scope TEXT NOT NULL,
            status TEXT NOT NULL,
            updated_at TEXT,
            json TEXT NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE cache_tasks (
            id TEXT PRIMARY KEY,
            site_id TEXT,
            status TEXT NOT NULL,
            updated_at TEXT,
            json TEXT NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE cache_visits (
            id TEXT PRIMARY KEY,
            site_id TEXT NOT NULL,
            visit_date TEXT NOT NULL,
            created_at TEXT,
            json TEXT NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE cache_meta (
            key TEXT PRIMARY KEY,
            json TEXT NOT NULL
          )
        ''');
        batch.execute('''
          CREATE TABLE outbox (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            method TEXT NOT NULL,
            path TEXT NOT NULL,
            body TEXT,
            site_id TEXT,
            base_updated_at TEXT,
            created_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            state TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        batch.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        batch.execute('CREATE INDEX idx_tasks_site ON cache_tasks(site_id)');
        batch.execute('CREATE INDEX idx_visits_site ON cache_visits(site_id)');
        batch.execute('CREATE INDEX idx_outbox_state ON outbox(state, created_at)');
        await batch.commit(noResult: true);
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------- sites

  Future<void> upsertSites(List<Site> sites) async {
    if (sites.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final site in sites) {
      batch.insert('cache_sites', {
        'id': site.id,
        'scope': site.scope.wire,
        'status': site.status.wire,
        'updated_at': site.updatedAt?.toIso8601String(),
        'json': jsonEncode(site.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> upsertSiteDetail(SiteDetail detail) async {
    await upsertSites([detail.site]);
    await upsertTasks(detail.tasks);
    await upsertVisits(detail.visits);
  }

  Future<List<Site>> readSites({
    SiteScope? scope,
    SiteStatus? status,
    String? query,
  }) async {
    final db = await database;
    final rows = await db.query('cache_sites', orderBy: 'updated_at DESC');
    final latestVisits = await _latestVisitPerSite();

    final needle = query?.trim();
    final sites = <Site>[];
    for (final row in rows) {
      final site = Site.fromJson(_decode(row['json']));
      if (scope != null && site.scope != scope) continue;
      if (status != null && site.status != status) continue;
      if (needle != null && needle.isNotEmpty) {
        final haystack = '${site.name} ${site.address} ${site.generalNotes ?? ''}'
            .toLowerCase();
        if (!haystack.contains(needle.toLowerCase())) continue;
      }
      final latest = latestVisits[site.id];
      sites.add(
        latest == null
            ? site
            : site.copyWith(
                lastVisit: VisitSummary(
                  id: latest.id,
                  siteId: latest.siteId,
                  visitDate: latest.visitDate,
                  completedWork: latest.completedWork,
                  remainingWork: latest.remainingWork,
                  notes: latest.notes,
                  createdByName: latest.createdByName,
                ),
              ),
      );
    }
    return sites;
  }

  Future<Site?> readSite(String id) async {
    final db = await database;
    final rows = await db.query('cache_sites', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Site.fromJson(_decode(rows.first['json']));
  }

  Future<void> updateSiteStatus(String id, SiteStatus status) async {
    final db = await database;
    final rows = await db.query('cache_sites', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final site = Site.fromJson(_decode(rows.first['json']));
    final updated = site.copyWith(status: status);
    await db.update(
      'cache_sites',
      {
        'status': status.wire,
        'json': jsonEncode(updated.toJson()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSite(String id) async {
    final db = await database;
    await db.delete('cache_sites', where: 'id = ?', whereArgs: [id]);
    await db.delete('cache_tasks', where: 'site_id = ?', whereArgs: [id]);
    await db.delete('cache_visits', where: 'site_id = ?', whereArgs: [id]);
  }

  /// Replaces a locally-generated site id with the server id after the queued
  /// create succeeds. Without this the optimistic row would survive next to the
  /// real row and the user would see the site twice.
  ///
  /// Child rows and queued writes are remapped too, so nothing keeps pointing at
  /// an id the server has never seen.
  Future<void> remapSiteId(String oldId, String newId) async {
    if (oldId == newId) return;
    final db = await database;

    final taskRows = await db.query('cache_tasks', where: 'site_id = ?', whereArgs: [oldId]);
    final visitRows = await db.query('cache_visits', where: 'site_id = ?', whereArgs: [oldId]);
    final outboxRows = await db.query('outbox', where: 'site_id = ?', whereArgs: [oldId]);

    final batch = db.batch();
    batch.delete('cache_sites', where: 'id = ?', whereArgs: [oldId]);

    for (final row in taskRows) {
      final json = _decode(row['json']);
      json['siteId'] = newId;
      batch.update(
        'cache_tasks',
        {'site_id': newId, 'json': jsonEncode(json)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    for (final row in visitRows) {
      final json = _decode(row['json']);
      json['siteId'] = newId;
      batch.update(
        'cache_visits',
        {'site_id': newId, 'json': jsonEncode(json)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    for (final row in outboxRows) {
      final rawBody = row['body'];
      Map<String, dynamic>? body;
      if (rawBody is String && rawBody.isNotEmpty) {
        try {
          body = jsonDecode(rawBody) as Map<String, dynamic>;
        } catch (_) {
          body = null;
        }
      }
      if (body != null && body['siteId'] == oldId) body['siteId'] = newId;
      batch.update(
        'outbox',
        {
          'site_id': newId,
          if (body != null) 'body': jsonEncode(body),
        },
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    await batch.commit(noResult: true);
  }

  Future<Map<String, Visit>> _latestVisitPerSite() async {
    final db = await database;
    final rows = await db.query(
      'cache_visits',
      orderBy: 'visit_date DESC, created_at DESC',
    );
    final result = <String, Visit>{};
    for (final row in rows) {
      final visit = Visit.fromJson(_decode(row['json']));
      result.putIfAbsent(visit.siteId, () => visit);
    }
    return result;
  }

  // ---------------------------------------------------------------- tasks

  Future<void> upsertTasks(List<Task> tasks) async {
    if (tasks.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final task in tasks) {
      batch.insert('cache_tasks', {
        'id': task.id,
        'site_id': task.siteId,
        'status': task.status.wire,
        'updated_at': task.updatedAt?.toIso8601String(),
        'json': jsonEncode(task.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Task>> readTasks({
    String? siteId,
    Set<TaskStatus>? statuses,
    String? query,
    int limit = 300,
  }) async {
    final db = await database;
    final rows = await db.query(
      'cache_tasks',
      where: siteId == null ? null : 'site_id = ?',
      whereArgs: siteId == null ? null : [siteId],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    final needle = query?.trim().toLowerCase();
    final tasks = <Task>[];
    for (final row in rows) {
      final task = Task.fromJson(_decode(row['json']));
      if (statuses != null && !statuses.contains(task.status)) continue;
      if (needle != null && needle.isNotEmpty) {
        final haystack = '${task.title} ${task.description ?? ''} ${task.siteName ?? ''}'
            .toLowerCase();
        if (!haystack.contains(needle)) continue;
      }
      tasks.add(task);
    }
    tasks.sort(_taskOrder);
    return tasks;
  }

  Future<void> deleteTask(String id) async {
    final db = await database;
    await db.delete('cache_tasks', where: 'id = ?', whereArgs: [id]);
  }

  static int _taskOrder(Task a, Task b) {
    final statusCompare = a.status.index.compareTo(b.status.index);
    if (statusCompare != 0) return statusCompare;
    final priorityCompare = b.priority.index.compareTo(a.priority.index);
    if (priorityCompare != 0) return priorityCompare;
    final aDue = a.dueDate ?? '9999-12-31';
    final bDue = b.dueDate ?? '9999-12-31';
    return aDue.compareTo(bDue);
  }

  // ---------------------------------------------------------------- visits

  Future<void> upsertVisits(List<Visit> visits) async {
    if (visits.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final visit in visits) {
      batch.insert('cache_visits', {
        'id': visit.id,
        'site_id': visit.siteId,
        'visit_date': visit.visitDate,
        'created_at': visit.createdAt?.toIso8601String(),
        'json': jsonEncode(visit.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Visit>> readVisits({String? siteId, int limit = 100}) async {
    final db = await database;
    final rows = await db.query(
      'cache_visits',
      where: siteId == null ? null : 'site_id = ?',
      whereArgs: siteId == null ? null : [siteId],
      orderBy: 'visit_date DESC, created_at DESC',
      limit: limit,
    );
    return rows.map((row) => Visit.fromJson(_decode(row['json']))).toList(growable: false);
  }

  Future<void> deleteVisit(String id) async {
    final db = await database;
    await db.delete('cache_visits', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------- meta

  Future<void> writeOverview(Overview overview) async {
    final db = await database;
    await db.insert('cache_meta', {
      'key': 'overview',
      'json': jsonEncode(overview.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await upsertSites(overview.recentSites);
    await upsertTasks(overview.upcomingTasks);
  }

  Future<Overview?> readOverview() async {
    final db = await database;
    final rows = await db.query(
      'cache_meta',
      where: 'key = ?',
      whereArgs: ['overview'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      return Overview.fromJson(_decode(rows.first['json']));
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> lastSyncedAt() async {
    final db = await database;
    final rows = await db.query(
      'cache_meta',
      where: 'key = ?',
      whereArgs: ['last_sync'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = _decode(rows.first['json'])['at'];
    return value is String ? DateTime.tryParse(value) : null;
  }

  Future<void> markSynced(DateTime at) async {
    final db = await database;
    await db.insert('cache_meta', {
      'key': 'last_sync',
      'json': jsonEncode({'at': at.toIso8601String()}),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------- outbox

  Future<void> enqueue(OutboxItem item) async {
    final db = await database;
    await db.insert('outbox', item.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<OutboxItem>> pendingItems() async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      // Failed items are terminal until the user retries them explicitly from
      // Settings; retrying them on every sync would hammer the server forever.
      where: "state = 'pending'",
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxItem.fromRow).toList(growable: false);
  }

  Future<List<OutboxItem>> failedItems() async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      where: "state = 'failed'",
      orderBy: 'created_at DESC',
    );
    return rows.map(OutboxItem.fromRow).toList(growable: false);
  }

  Future<OutboxItem?> itemById(String id) async {
    final db = await database;
    final rows = await db.query('outbox', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return OutboxItem.fromRow(rows.first);
  }

  Future<List<OutboxItem>> conflictItems() async {
    final db = await database;
    final rows = await db.query(
      'outbox',
      where: "state = 'conflict'",
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxItem.fromRow).toList(growable: false);
  }

  Future<List<OutboxItem>> allItems() async {
    final db = await database;
    final rows = await db.query('outbox', orderBy: 'created_at DESC');
    return rows.map(OutboxItem.fromRow).toList(growable: false);
  }

  Future<int> pendingCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS c FROM outbox WHERE state IN ('pending', 'failed', 'conflict')",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> removeItem(String id) async {
    final db = await database;
    await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markItem(
    String id, {
    required String state,
    String? error,
    bool incrementAttempts = false,
  }) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE outbox SET state = ?, last_error = ?, attempts = attempts + ? WHERE id = ?',
      [state, error, incrementAttempts ? 1 : 0, id],
    );
  }

  Future<void> requeueItem(String id, {String? newBody, bool clearBase = false}) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE outbox SET state = ?, last_error = NULL, attempts = 0, '
      'body = COALESCE(?, body), base_updated_at = CASE WHEN ? = 1 THEN NULL ELSE base_updated_at END '
      'WHERE id = ?',
      ['pending', newBody, clearBase ? 1 : 0, id],
    );
  }

  Future<void> clearPending() async {
    final db = await database;
    await db.delete('outbox');
  }

  // ---------------------------------------------------------------- settings

  Future<String?> readSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> writeSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAll() async {
    final db = await database;
    final batch = db.batch();
    for (final table in [
      'cache_sites',
      'cache_tasks',
      'cache_visits',
      'cache_meta',
      'outbox',
    ]) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }

  Map<String, dynamic> _decode(Object? value) {
    if (value is String) return jsonDecode(value) as Map<String, dynamic>;
    return const {};
  }
}

enum OutboxState { pending, failed, conflict }

/// One queued write. `id` doubles as the idempotency key for creates.
class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    required this.body,
    this.siteId,
    this.baseUpdatedAt,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.state = OutboxState.pending,
  });

  final String id;

  /// `site`, `visit`, `task`, `taskUpdate`, `siteUpdate`.
  final String kind;
  final String method;
  final String path;
  final Map<String, dynamic> body;
  final String? siteId;
  final String? baseUpdatedAt;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final OutboxState state;

  bool get isCreate => kind == 'site' || kind == 'visit' || kind == 'task';

  String get labelAr => switch (kind) {
    'site' => 'موقع جديد',
    'visit' => 'زيارة جديدة',
    'task' => 'مهمة جديدة',
    'taskUpdate' => 'تعديل مهمة',
    'siteUpdate' => 'تعديل موقع',
    _ => 'تغيير',
  };

  Map<String, Object?> toRow() => {
    'id': id,
    'kind': kind,
    'method': method,
    'path': path,
    'body': jsonEncode(body),
    'site_id': siteId,
    'base_updated_at': baseUpdatedAt,
    'created_at': createdAt.millisecondsSinceEpoch,
    'attempts': attempts,
    'last_error': lastError,
    'state': state.name,
  };

  static OutboxItem fromRow(Map<String, Object?> row) {
    final stateName = (row['state'] as String?) ?? 'pending';
    return OutboxItem(
      id: row['id'] as String,
      kind: (row['kind'] as String?) ?? 'unknown',
      method: (row['method'] as String?) ?? 'POST',
      path: (row['path'] as String?) ?? '',
      body: row['body'] == null
          ? const {}
          : jsonDecode(row['body'] as String) as Map<String, dynamic>,
      siteId: row['site_id'] as String?,
      baseUpdatedAt: row['base_updated_at'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch((row['created_at'] as int?) ?? 0),
      attempts: (row['attempts'] as int?) ?? 0,
      lastError: row['last_error'] as String?,
      state: OutboxState.values.firstWhere(
        (value) => value.name == stateName,
        orElse: () => OutboxState.pending,
      ),
    );
  }

  OutboxItem copyWith({OutboxState? state, String? lastError, int? attempts}) {
    return OutboxItem(
      id: id,
      kind: kind,
      method: method,
      path: path,
      body: body,
      siteId: siteId,
      baseUpdatedAt: baseUpdatedAt,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      state: state ?? this.state,
    );
  }
}
