import 'dart:convert';

import '../core/api_exception.dart';
import '../models/overview.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/visit.dart';
import 'api_repository.dart';
import 'local_db.dart';

class SyncOutcome {
  const SyncOutcome({
    this.pushed = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.offline = false,
  });

  final int pushed;
  final int conflicts;
  final int failed;
  final bool offline;

  bool get didSomething => pushed > 0 || conflicts > 0 || failed > 0;
}

/// Pushes queued writes and refreshes the read cache.
///
/// Deliberately simple: no background worker, no queue service. It runs on app
/// start, on resume, after each write, and on a foreground timer.
class SyncService {
  SyncService({required ApiRepository api, required LocalDb db}) : _api = api, _db = db;

  final ApiRepository _api;
  final LocalDb _db;

  bool _running = false;

  bool get isRunning => _running;

  /// Flushes pending writes in creation order.
  Future<SyncOutcome> flushOutbox() async {
    if (_running) return const SyncOutcome();
    _running = true;
    var pushed = 0;
    var conflicts = 0;
    var failed = 0;
    var offline = false;

    try {
      final items = await _db.pendingItems();
      for (final item in items) {
        try {
          await _apply(item);
          await _db.removeItem(item.id);
          pushed += 1;
        } on ApiException catch (error) {
          if (error.isNetworkError) {
            await _db.markItem(
              item.id,
              state: 'pending',
              error: error.message,
              incrementAttempts: true,
            );
            offline = true;
            break;
          }
          if (error.isConflict) {
            await _db.markItem(item.id, state: 'conflict', error: error.message);
            conflicts += 1;
            continue;
          }
          if (error.isUnauthorized) {
            break;
          }
          // A validation or permission error will not fix itself on retry.
          await _db.markItem(
            item.id,
            state: 'failed',
            error: error.validationMessage ?? error.message,
            incrementAttempts: true,
          );
          await _removeOptimistic(item);
          failed += 1;
        } catch (error) {
          await _db.markItem(item.id, state: 'failed', error: error.toString());
          await _removeOptimistic(item);
          failed += 1;
        }
      }

      if (pushed > 0) await _db.markSynced(DateTime.now());
    } finally {
      _running = false;
    }

    return SyncOutcome(
      pushed: pushed,
      conflicts: conflicts,
      failed: failed,
      offline: offline,
    );
  }

  Future<void> _apply(OutboxItem item) async {
    switch (item.kind) {
      case 'site':
        final site = await _api.createSite(item.body);
        // The server assigns its own id; drop the optimistic placeholder and
        // move anything queued against it to the real id.
        await _db.remapSiteId(item.id, site.id);
        await _db.upsertSites([site]);
      case 'siteUpdate':
        final site = await _api.updateSite(item.path.split('/').last, item.body);
        await _db.upsertSites([site]);
      case 'visit':
        final visit = await _api.createVisit(item.siteId!, item.body);
        if (visit.id != item.id) await _db.deleteVisit(item.id);
        await _db.upsertVisits([visit]);
      case 'visitUpdate':
        final visit = await _api.updateVisit(item.path.split('/').last, item.body);
        await _db.upsertVisits([visit]);
      case 'task':
        final task = await _api.createTask(item.body);
        if (task.id != item.id) await _db.deleteTask(item.id);
        await _db.upsertTasks([task]);
      case 'taskUpdate':
        final task = await _api.updateTask(item.path.split('/').last, item.body);
        await _db.upsertTasks([task]);
      default:
        throw ApiException(message: 'نوع التغيير غير معروف: ${item.kind}', code: 'BAD_REQUEST');
    }
  }

  /// Removes the optimistic cache row for a queued create that will never be
  /// retried, so it cannot linger as a phantom duplicate.
  Future<void> _removeOptimistic(OutboxItem item) async {
    if (!item.isCreate) return;
    switch (item.kind) {
      case 'site':
        await _db.deleteSite(item.id);
      case 'visit':
        await _db.deleteVisit(item.id);
      case 'task':
        await _db.deleteTask(item.id);
    }
  }

  /// Resolves a conflict by discarding the local change.
  Future<void> discardConflict(String itemId) async {
    final item = await _db.itemById(itemId);
    if (item != null) await _removeOptimistic(item);
    await _db.removeItem(itemId);
  }

  /// Retries a write that previously failed with a permanent error. The user
  /// has presumably fixed the cause (permissions, missing site, …), so the
  /// attempt counter is reset and the item rejoins the queue.
  Future<void> retryFailed(String itemId) async {
    await _db.requeueItem(itemId);
  }

  /// Gives up on a failed write and removes its optimistic cache row.
  Future<void> discardFailed(String itemId) async {
    await discardConflict(itemId);
  }

  /// Resolves a conflict by re-sending the local change without the stale
  /// `baseUpdatedAt` guard (the user explicitly chose to keep their version).
  Future<void> keepLocalConflict(String itemId) async {
    final items = await _db.conflictItems();
    OutboxItem? match;
    for (final item in items) {
      if (item.id == itemId) {
        match = item;
        break;
      }
    }
    if (match == null) return;

    final body = Map<String, dynamic>.from(match.body)..remove('baseUpdatedAt');
    final encoded = body.isEmpty ? null : jsonEncode(body);
    await _db.requeueItem(itemId, newBody: encoded, clearBase: true);
  }

  /// Pulls the dashboard, site list, and task list into the local cache.
  Future<Overview> refreshCache() async {
    final overview = await _api.overview();
    await _db.writeOverview(overview);

    final sites = await _api.sites();
    await _db.upsertSites(sites);

    final tasks = await _api.tasks();
    await _db.upsertTasks(tasks);

    await _db.markSynced(DateTime.now());
    return overview;
  }

  /// Loads one site with its tasks and visits, refreshing the cache.
  Future<SiteDetail> loadSiteDetail(String siteId) async {
    final detail = await _api.siteDetail(siteId);
    await _db.upsertSiteDetail(detail);
    return detail;
  }

  Future<List<Visit>> loadVisitHistory(String siteId, {int limit = 50}) async {
    final page = await _api.visits(siteId, limit: limit);
    await _db.upsertVisits(page.visits);
    return page.visits;
  }

  /// Cached fallbacks used when the network is unavailable.
  Future<Overview?> cachedOverview() => _db.readOverview();

  Future<List<Site>> cachedSites({SiteScope? scope, SiteStatus? status, String? query}) {
    return _db.readSites(scope: scope, status: status, query: query);
  }

  Future<List<Task>> cachedTasks({
    String? siteId,
    Set<TaskStatus>? statuses,
    String? query,
  }) {
    return _db.readTasks(siteId: siteId, statuses: statuses, query: query);
  }

  Future<List<Visit>> cachedVisits(String siteId) => _db.readVisits(siteId: siteId);

  Future<SiteDetail?> cachedSiteDetail(String siteId) async {
    final site = await _db.readSite(siteId);
    if (site == null) return null;
    final tasks = await _db.readTasks(siteId: siteId);
    final visits = await _db.readVisits(siteId: siteId);
    return SiteDetail(site: site, tasks: tasks, visits: visits, access: site.access);
  }
}
