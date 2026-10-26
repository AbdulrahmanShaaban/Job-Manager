import 'package:uuid/uuid.dart';

import '../core/api_exception.dart';
import '../core/formatting.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/visit.dart';
import 'api_repository.dart';
import 'local_db.dart';
import 'sync_service.dart';

/// Write path for every screen.
///
/// Online: send immediately, cache the server record.
/// Offline: cache an optimistic record flagged `pending` and queue the exact
/// same request (same `operationId`) in the outbox so a retry is idempotent.
class Mutations {
  Mutations({required ApiRepository api, required LocalDb db, required SyncService sync})
    : _api = api,
      _db = db,
      _sync = sync;

  final ApiRepository _api;
  final LocalDb _db;
  final SyncService _sync;
  final Uuid _uuid = const Uuid();

  // ----------------------------------------------------------------- visits

  Future<Visit> createVisit({
    required String siteId,
    required String visitDate,
    required String completedWork,
    String? remainingWork,
    String? notes,
    String? transcript,
    String source = 'MANUAL',
  }) async {
    final operationId = _uuid.v4();
    final body = <String, dynamic>{
      'visitDate': visitDate,
      'completedWork': completedWork,
      'source': source,
      'operationId': operationId,
      if (remainingWork != null && remainingWork.trim().isNotEmpty)
        'remainingWork': remainingWork.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (transcript != null && transcript.trim().isNotEmpty) 'transcript': transcript.trim(),
    };

    try {
      final visit = await _api.createVisit(siteId, body);
      await _db.upsertVisits([visit]);
      return visit;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final now = DateTime.now();
      final optimistic = Visit(
        id: operationId,
        siteId: siteId,
        visitDate: visitDate,
        completedWork: completedWork,
        remainingWork: remainingWork,
        notes: notes,
        transcript: transcript,
        source: source,
        createdAt: now,
        updatedAt: now,
        pending: true,
      );
      await _db.upsertVisits([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: operationId,
          kind: 'visit',
          method: 'POST',
          path: '/sites/$siteId/visits',
          body: body,
          siteId: siteId,
          createdAt: now,
        ),
      );
      return optimistic;
    }
  }

  Future<Visit> updateVisit(
    Visit visit, {
    required String visitDate,
    required String completedWork,
    String? remainingWork,
    String? notes,
  }) async {
    _rejectPending(visit.pending, 'الزيارة');
    final body = <String, dynamic>{
      'visitDate': visitDate,
      'completedWork': completedWork,
      'remainingWork': remainingWork?.trim().isEmpty ?? true ? null : remainingWork!.trim(),
      'notes': notes?.trim().isEmpty ?? true ? null : notes!.trim(),
      if (visit.updatedAt != null) 'baseUpdatedAt': visit.updatedAt!.toIso8601String(),
    };

    try {
      final updated = await _api.updateVisit(visit.id, body);
      await _db.upsertVisits([updated]);
      return updated;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final optimistic = Visit(
        id: visit.id,
        siteId: visit.siteId,
        visitDate: visitDate,
        completedWork: completedWork,
        remainingWork: remainingWork,
        notes: notes,
        transcript: visit.transcript,
        source: visit.source,
        createdById: visit.createdById,
        createdByName: visit.createdByName,
        revision: visit.revision + 1,
        editedAt: DateTime.now(),
        createdAt: visit.createdAt,
        updatedAt: DateTime.now(),
        pending: true,
      );
      await _db.upsertVisits([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: _uuid.v4(),
          kind: 'visitUpdate',
          method: 'PATCH',
          path: '/visits/${visit.id}',
          body: body,
          siteId: visit.siteId,
          baseUpdatedAt: visit.updatedAt?.toIso8601String(),
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  // ------------------------------------------------------------------ tasks

  Future<Task> createTask({
    String? siteId,
    required String title,
    String? description,
    TaskStatus status = TaskStatus.open,
    TaskPriority priority = TaskPriority.normal,
    String? dueDate,
  }) async {
    final operationId = _uuid.v4();
    final body = <String, dynamic>{
      'title': title,
      'status': status.wire,
      'priority': priority.wire,
      'operationId': operationId,
      'siteId': ?siteId,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (dueDate != null && dueDate.isNotEmpty) 'dueDate': dueDate,
    };

    try {
      final task = await _api.createTask(body);
      await _db.upsertTasks([task]);
      return task;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final now = DateTime.now();
      final optimistic = Task(
        id: operationId,
        title: title,
        status: status,
        priority: priority,
        siteId: siteId,
        description: description,
        dueDate: dueDate,
        createdAt: now,
        updatedAt: now,
        pending: true,
      );
      await _db.upsertTasks([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: operationId,
          kind: 'task',
          method: 'POST',
          path: '/tasks',
          body: body,
          siteId: siteId,
          createdAt: now,
        ),
      );
      return optimistic;
    }
  }

  Future<Task> updateTask(
    Task task, {
    TaskStatus? status,
    String? title,
    String? description,
    TaskPriority? priority,
    String? dueDate,
    bool clearDueDate = false,
  }) async {
    _rejectPending(task.pending, 'المهمة');
    final body = <String, dynamic>{
      if (status != null) 'status': status.wire,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      if (description != null) 'description': description.trim().isEmpty ? null : description.trim(),
      if (priority != null) 'priority': priority.wire,
      if (clearDueDate) 'dueDate': null,
      if (!clearDueDate && dueDate != null && dueDate.isNotEmpty) 'dueDate': dueDate,
      if (task.updatedAt != null) 'baseUpdatedAt': task.updatedAt!.toIso8601String(),
    };
    if (body.length <= (task.updatedAt != null ? 1 : 0)) {
      throw ApiException(message: 'مفيش تغييرات مطلوبة.', code: 'BAD_REQUEST');
    }

    try {
      final updated = await _api.updateTask(task.id, body);
      await _db.upsertTasks([updated]);
      return updated;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final optimistic = Task(
        id: task.id,
        title: title ?? task.title,
        status: status ?? task.status,
        priority: priority ?? task.priority,
        siteId: task.siteId,
        siteName: task.siteName,
        siteScope: task.siteScope,
        description: description ?? task.description,
        dueDate: clearDueDate ? null : (dueDate ?? task.dueDate),
        completedAt: status == TaskStatus.done ? DateTime.now() : task.completedAt,
        createdById: task.createdById,
        assigneeId: task.assigneeId,
        assigneeName: task.assigneeName,
        createdAt: task.createdAt,
        updatedAt: DateTime.now(),
        pending: true,
      );
      await _db.upsertTasks([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: _uuid.v4(),
          kind: 'taskUpdate',
          method: 'PATCH',
          path: '/tasks/${task.id}',
          body: body,
          siteId: task.siteId,
          baseUpdatedAt: task.updatedAt?.toIso8601String(),
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  Future<void> deleteTask(Task task) async {
    _rejectPending(task.pending, 'المهمة');
    await _api.deleteTask(task.id);
    await _db.deleteTask(task.id);
  }

  // ------------------------------------------------------------------ sites

  Future<Site> createSite({
    required String name,
    required SiteScope scope,
    String? workspaceId,
    required String address,
    String? contactName,
    String? contactPhone,
    String? mapUrl,
    double? latitude,
    double? longitude,
    String? generalNotes,
  }) async {
    final operationId = _uuid.v4();
    final body = <String, dynamic>{
      'name': name.trim(),
      'scope': scope.wire,
      'address': address.trim(),
      'operationId': operationId,
      if (scope == SiteScope.company && workspaceId != null) 'workspaceId': workspaceId,
      if (contactName != null && contactName.trim().isNotEmpty) 'contactName': contactName.trim(),
      if (contactPhone != null && contactPhone.trim().isNotEmpty)
        'contactPhone': contactPhone.trim(),
      if (mapUrl != null && mapUrl.trim().isNotEmpty) 'mapUrl': mapUrl.trim(),
      'latitude': ?latitude,
      'longitude': ?longitude,
      if (generalNotes != null && generalNotes.trim().isNotEmpty)
        'generalNotes': generalNotes.trim(),
    };

    try {
      final site = await _api.createSite(body);
      await _db.upsertSites([site]);
      return site;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final now = DateTime.now();
      final optimistic = Site(
        id: operationId,
        name: name,
        scope: scope,
        status: SiteStatus.active,
        address: address,
        workspaceId: scope == SiteScope.company ? workspaceId : null,
        contactName: contactName,
        contactPhone: contactPhone,
        mapUrl: mapUrl,
        latitude: latitude,
        longitude: longitude,
        generalNotes: generalNotes,
        createdAt: now,
        updatedAt: now,
        pending: true,
      );
      await _db.upsertSites([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: operationId,
          kind: 'site',
          method: 'POST',
          path: '/sites',
          body: body,
          createdAt: now,
        ),
      );
      return optimistic;
    }
  }

  Future<Site> updateSite(
    Site site, {
    String? name,
    String? address,
    String? contactName,
    String? contactPhone,
    String? mapUrl,
    String? generalNotes,
    SiteStatus? status,
  }) async {
    _rejectPending(site.pending, 'الموقع');
    final body = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (address != null && address.trim().isNotEmpty) 'address': address.trim(),
      if (contactName != null) 'contactName': contactName.trim().isEmpty ? null : contactName.trim(),
      if (contactPhone != null)
        'contactPhone': contactPhone.trim().isEmpty ? null : contactPhone.trim(),
      if (mapUrl != null) 'mapUrl': mapUrl.trim().isEmpty ? null : mapUrl.trim(),
      if (generalNotes != null)
        'generalNotes': generalNotes.trim().isEmpty ? null : generalNotes.trim(),
      if (status != null) 'status': status.wire,
      if (site.updatedAt != null) 'baseUpdatedAt': site.updatedAt!.toIso8601String(),
    };

    try {
      final updated = await _api.updateSite(site.id, body);
      await _db.upsertSites([updated]);
      return updated;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final optimistic = Site(
        id: site.id,
        name: name ?? site.name,
        scope: site.scope,
        status: status ?? site.status,
        address: address ?? site.address,
        workspaceId: site.workspaceId,
        workspaceName: site.workspaceName,
        contactName: contactName ?? site.contactName,
        contactPhone: contactPhone ?? site.contactPhone,
        mapUrl: mapUrl ?? site.mapUrl,
        latitude: site.latitude,
        longitude: site.longitude,
        generalNotes: generalNotes ?? site.generalNotes,
        openTaskCount: site.openTaskCount,
        lastVisit: site.lastVisit,
        createdAt: site.createdAt,
        updatedAt: DateTime.now(),
        pending: true,
      );
      await _db.upsertSites([optimistic]);
      await _db.enqueue(
        OutboxItem(
          id: _uuid.v4(),
          kind: 'siteUpdate',
          method: 'PATCH',
          path: '/sites/${site.id}',
          body: body,
          siteId: site.id,
          baseUpdatedAt: site.updatedAt?.toIso8601String(),
          createdAt: DateTime.now(),
        ),
      );
      return optimistic;
    }
  }

  /// Runs the outbox flush right after a write; failures are non-fatal because
  /// the queued item is already persisted.
  Future<void> flushQuietly() async {
    try {
      await _sync.flushOutbox();
    } catch (_) {
      // The outbox keeps the work; the sync banner surfaces the error.
    }
  }

  void _rejectPending(bool pending, String label) {
    if (!pending) return;
    throw ApiException(
      message: '$label لسه بانتظار المزامنة. وصّل الإنترنت الأول أو استنى المزامنة تخلص.',
      code: 'PENDING_SYNC',
    );
  }

  String todayIso() => AppFormat.todayIso();
}
