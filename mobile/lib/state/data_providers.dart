import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_exception.dart';
import '../core/config.dart';
import '../data/local_db.dart';
import '../data/sync_service.dart';
import '../models/overview.dart';
import '../models/site.dart';
import '../models/task.dart';
import '../models/visit.dart';
import 'providers.dart';

// ------------------------------------------------------------------ filters

class SitesFilter {
  const SitesFilter({
    this.scope = SiteScope.company,
    this.status = SiteStatus.active,
    this.query = '',
  });

  final SiteScope? scope;
  final SiteStatus? status;
  final String query;

  SitesFilter copyWith({SiteScope? scope, SiteStatus? status, String? query}) {
    return SitesFilter(
      scope: scope ?? this.scope,
      status: status ?? this.status,
      query: query ?? this.query,
    );
  }
}

class SitesFilterController extends Notifier<SitesFilter> {
  @override
  SitesFilter build() => const SitesFilter();

  void setScope(SiteScope scope) => state = state.copyWith(scope: scope);

  void setStatus(SiteStatus status) => state = state.copyWith(status: status);

  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
  }
}

final sitesFilterProvider = NotifierProvider<SitesFilterController, SitesFilter>(
  SitesFilterController.new,
);

class TasksFilter {
  const TasksFilter({
    this.statuses = const {TaskStatus.open, TaskStatus.inProgress},
    this.query = '',
    this.siteId,
  });

  /// `null` means every status.
  final Set<TaskStatus>? statuses;
  final String query;
  final String? siteId;

  TasksFilter copyWith({
    Set<TaskStatus>? statuses,
    bool clearStatuses = false,
    String? query,
    String? siteId,
    bool clearSite = false,
  }) {
    return TasksFilter(
      statuses: clearStatuses ? null : (statuses ?? this.statuses),
      query: query ?? this.query,
      siteId: clearSite ? null : (siteId ?? this.siteId),
    );
  }
}

class TasksFilterController extends Notifier<TasksFilter> {
  @override
  TasksFilter build() => const TasksFilter();

  void setStatuses(Set<TaskStatus>? statuses) {
    state = statuses == null
        ? state.copyWith(clearStatuses: true)
        : state.copyWith(statuses: statuses);
  }

  void setQuery(String query) {
    if (query == state.query) return;
    state = state.copyWith(query: query);
  }

  void setSite(String? siteId) {
    state = siteId == null ? state.copyWith(clearSite: true) : state.copyWith(siteId: siteId);
  }
}

final tasksFilterProvider = NotifierProvider<TasksFilterController, TasksFilter>(
  TasksFilterController.new,
);

// ------------------------------------------------------------------- sites

class SitesController extends AsyncNotifier<List<Site>> {
  @override
  Future<List<Site>> build() async {
    final filter = ref.watch(sitesFilterProvider);
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);

    try {
      final sites = await api.sites(
        scope: filter.scope,
        status: filter.status,
        query: filter.query,
      );
      await db.upsertSites(sites);
      return sites;
    } on ApiException catch (error) {
      if (error.isNetworkError) {
        return db.readSites(scope: filter.scope, status: filter.status, query: filter.query);
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final sitesProvider = AsyncNotifierProvider<SitesController, List<Site>>(SitesController.new);

/// Every active site the user can see, regardless of the list screen's filter.
/// Used by pickers (task site, filters) so they never depend on tab state.
class AllSitesController extends AsyncNotifier<List<Site>> {
  @override
  Future<List<Site>> build() async {
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);
    try {
      final sites = await api.sites();
      await db.upsertSites(sites);
      return sites;
    } on ApiException catch (error) {
      if (error.isNetworkError) return db.readSites();
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final allSitesProvider = AsyncNotifierProvider<AllSitesController, List<Site>>(
  AllSitesController.new,
);

class SiteDetailController extends AsyncNotifier<SiteDetail?> {
  SiteDetailController(this.siteId);

  final String siteId;

  @override
  Future<SiteDetail?> build() async {
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);
    try {
      final detail = await api.siteDetail(siteId);
      await db.upsertSiteDetail(detail);
      return detail;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final site = await db.readSite(siteId);
      if (site == null) return null;
      final tasks = await db.readTasks(siteId: siteId);
      final visits = await db.readVisits(siteId: siteId);
      return SiteDetail(site: site, tasks: tasks, visits: visits, access: site.access);
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final siteDetailProvider =
    AsyncNotifierProvider.family<SiteDetailController, SiteDetail?, String>(
      SiteDetailController.new,
    );

class VisitHistoryController extends AsyncNotifier<List<Visit>> {
  VisitHistoryController(this.siteId);

  final String siteId;

  @override
  Future<List<Visit>> build() async {
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);
    try {
      final page = await api.visits(siteId, limit: 100);
      await db.upsertVisits(page.visits);
      return page.visits;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      return db.readVisits(siteId: siteId);
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final visitHistoryProvider =
    AsyncNotifierProvider.family<VisitHistoryController, List<Visit>, String>(
      VisitHistoryController.new,
    );

// ------------------------------------------------------------------- tasks

class TasksController extends AsyncNotifier<List<Task>> {
  @override
  Future<List<Task>> build() async {
    final filter = ref.watch(tasksFilterProvider);
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);

    try {
      final tasks = await api.tasks(
        siteId: filter.siteId,
        statuses: filter.statuses,
        query: filter.query,
      );
      await db.upsertTasks(tasks);
      return tasks;
    } on ApiException catch (error) {
      if (error.isNetworkError) {
        return db.readTasks(
          siteId: filter.siteId,
          statuses: filter.statuses,
          query: filter.query,
        );
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final tasksProvider = AsyncNotifierProvider<TasksController, List<Task>>(TasksController.new);

// ---------------------------------------------------------------- overview

class OverviewController extends AsyncNotifier<Overview?> {
  @override
  Future<Overview?> build() async {
    final api = ref.read(apiRepositoryProvider);
    final db = ref.read(localDbProvider);
    try {
      final overview = await api.overview();
      await db.writeOverview(overview);
      await db.markSynced(DateTime.now());
      return overview;
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      return db.readOverview();
    }
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }
}

final overviewProvider = AsyncNotifierProvider<OverviewController, Overview?>(
  OverviewController.new,
);

// ------------------------------------------------------------- sync status

class SyncStatus {
  const SyncStatus({
    this.pending = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.syncing = false,
    this.lastSyncedAt,
    this.lastError,
    this.offline = false,
  });

  final int pending;
  final int conflicts;
  final int failed;
  final bool syncing;
  final DateTime? lastSyncedAt;
  final String? lastError;
  final bool offline;

  bool get hasQueued => pending > 0 || conflicts > 0 || failed > 0;

  static const Object _unset = Object();

  SyncStatus copyWith({
    int? pending,
    int? conflicts,
    int? failed,
    bool? syncing,
    DateTime? lastSyncedAt,
    Object? lastError = _unset,
    bool? offline,
  }) {
    return SyncStatus(
      pending: pending ?? this.pending,
      conflicts: conflicts ?? this.conflicts,
      failed: failed ?? this.failed,
      syncing: syncing ?? this.syncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      // `lastError` needs an explicit clear: omitting it must keep the current
      // message, while passing `null` clears it.
      lastError: identical(lastError, _unset) ? this.lastError : lastError as String?,
      offline: offline ?? this.offline,
    );
  }
}

class SyncController extends Notifier<SyncStatus> {
  Timer? _timer;

  @override
  SyncStatus build() {
    ref.onDispose(() => _timer?.cancel());
    return const SyncStatus();
  }

  /// Starts the foreground sync loop. Safe to call more than once.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => syncNow(silent: true));
    unawaited(refreshCounts());
  }

  /// Stops the timer while the app is in the background. The next `start()`
  /// re-arms it on resume.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refreshCounts() async {
    final db = ref.read(localDbProvider);
    final all = await db.allItems();
    final lastSyncedAt = await db.lastSyncedAt();
    state = state.copyWith(
      pending: all.where((item) => item.state == OutboxState.pending).length,
      conflicts: all.where((item) => item.state == OutboxState.conflict).length,
      failed: all.where((item) => item.state == OutboxState.failed).length,
      lastSyncedAt: lastSyncedAt,
    );
    // The Settings lists stay mounted across tab switches, so they must be
    // invalidated whenever the outbox is re-counted.
    ref.invalidate(syncConflictProvider);
    ref.invalidate(syncFailedProvider);
  }

  Future<SyncOutcome?> syncNow({bool silent = false}) async {
    if (state.syncing) return null;
    if (!silent) state = state.copyWith(syncing: true);

    final sync = ref.read(syncServiceProvider);
    SyncOutcome? outcome;
    String? error;
    try {
      outcome = await sync.flushOutbox();
      if (!outcome.offline) {
        try {
          await sync.refreshCache();
          ref.invalidate(overviewProvider);
          ref.invalidate(sitesProvider);
          ref.invalidate(allSitesProvider);
          ref.invalidate(tasksProvider);
          // Family providers are invalidated at the root so every open detail
          // and visit history refreshes after a sync.
          ref.invalidate(siteDetailProvider);
          ref.invalidate(visitHistoryProvider);
        } on ApiException catch (exception) {
          error = exception.message;
        }
      } else {
        error = 'مفيش اتصال. التغييرات محفوظة وهتتزامن لما الشبكة ترجع.';
      }
    } catch (exception) {
      error = exception is ApiException ? exception.message : exception.toString();
    }

    state = state.copyWith(
      syncing: false,
      lastError: error,
      offline: outcome?.offline ?? false,
    );
    await refreshCounts();
    return outcome;
  }

  Future<void> resolveConflict(String id, {required bool keepLocal}) async {
    final sync = ref.read(syncServiceProvider);
    if (keepLocal) {
      await sync.keepLocalConflict(id);
    } else {
      await sync.discardConflict(id);
    }
    await syncNow();
  }

  /// Puts a permanently failed write back in the queue and tries again.
  Future<void> retryFailed(String id) async {
    await ref.read(syncServiceProvider).retryFailed(id);
    await syncNow();
  }

  /// Drops a permanently failed write and its optimistic cache row.
  Future<void> discardFailed(String id) async {
    await ref.read(syncServiceProvider).discardFailed(id);
    ref.invalidate(overviewProvider);
    ref.invalidate(sitesProvider);
    ref.invalidate(allSitesProvider);
    ref.invalidate(tasksProvider);
    ref.invalidate(siteDetailProvider);
    ref.invalidate(visitHistoryProvider);
    await refreshCounts();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// Queued writes that need the user's decision. Defined here so the sync
/// controller can refresh them whenever the outbox changes.
final syncConflictProvider = FutureProvider<List<OutboxItem>>((ref) async {
  return ref.watch(localDbProvider).conflictItems();
});

final syncFailedProvider = FutureProvider<List<OutboxItem>>((ref) async {
  return ref.watch(localDbProvider).failedItems();
});
