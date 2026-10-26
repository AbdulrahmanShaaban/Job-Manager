import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../models/overview.dart';
import '../../models/site.dart';
import '../../models/task.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/list_items.dart';
import '../common/ui.dart';

class SiteDetailScreen extends ConsumerStatefulWidget {
  const SiteDetailScreen({super.key, required this.siteId});

  final String siteId;

  @override
  ConsumerState<SiteDetailScreen> createState() => _SiteDetailScreenState();
}

class _SiteDetailScreenState extends ConsumerState<SiteDetailScreen> {
  bool _showAllVisits = false;

  Future<void> _refresh() async {
    await ref.read(siteDetailProvider(widget.siteId).notifier).refresh();
    ref.invalidate(visitHistoryProvider(widget.siteId));
  }

  Future<void> _toggleTask(Task task) async {
    final next = task.status == TaskStatus.done ? TaskStatus.open : TaskStatus.done;
    try {
      await ref.read(mutationsProvider).updateTask(task, status: next);
      await ref.read(siteDetailProvider(widget.siteId).notifier).refresh();
      ref.invalidate(tasksProvider);
      ref.invalidate(overviewProvider);
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          title: 'مقدرناش نحدّث المهمة',
          description: describeError(error),
          destructive: true,
        );
      }
    }
  }

  Future<void> _setArchived(Site site, bool archived) async {
    try {
      await ref.read(mutationsProvider).updateSite(
        site,
        status: archived ? SiteStatus.archived : SiteStatus.active,
      );
      ref.invalidate(sitesProvider);
      ref.invalidate(overviewProvider);
      await ref.read(siteDetailProvider(widget.siteId).notifier).refresh();
      if (mounted) {
        showToast(
          context,
          title: archived ? 'الموقع اتأرشف' : 'الموقع رجع نشط',
          description: archived ? 'مش هيظهر في قائمة المواقع النشطة.' : null,
        );
      }
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          title: 'مقدرناش نحدّث الموقع',
          description: describeError(error),
          destructive: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(siteDetailProvider(widget.siteId));

    return AsyncContent<SiteDetail?>(
      value: detailAsync,
      onRetry: _refresh,
      builder: (detail) {
        if (detail == null) {
          return ScreenScaffold(
            title: 'الموقع',
            leading: ShadIconButton.ghost(
              icon: const Icon(LucideIcons.arrowRight, size: 18),
              onPressed: () => context.pop(),
            ),
            child: const EmptyState(
              icon: LucideIcons.mapPin,
              title: 'الموقع مش موجود',
              message: 'ممكن يكون اتشال أو ملكش صلاحية تشوفه.',
            ),
          );
        }

        final site = detail.site;
        final canWrite = detail.access?.canWrite ?? true;
        // A site that is still queued has no server id, so anything attached to
        // it would be written against an id the server has never seen.
        final canAddChildren = canWrite && !site.pending;
        final history = ref.watch(visitHistoryProvider(widget.siteId));
        final visits = history.value ?? detail.visits;
        final visibleVisits = _showAllVisits ? visits : visits.take(4).toList(growable: false);
        final openTasks = detail.openTasks;
        final doneTasks = detail.doneTasks;

        return ScreenScaffold(
          title: site.name,
          subtitle: site.scope == SiteScope.company
              ? (site.workspaceName ?? 'موقع شركة')
              : 'موقع خاص',
          onRefresh: _refresh,
          leading: ShadIconButton.ghost(
            icon: const Icon(LucideIcons.arrowRight, size: 18),
            onPressed: () => context.pop(),
          ),
          actions: [
            if (canAddChildren)
              ShadIconButton.ghost(
                icon: const Icon(LucideIcons.squarePen, size: 18),
                onPressed: () => context.push(
                  '/sites/${site.id}/edit',
                  extra: site,
                ),
              ),
            ShadIconButton.ghost(
              icon: const Icon(LucideIcons.ellipsis, size: 18),
              onPressed: () => _showActions(site, canAddChildren),
            ),
          ],
          child: ListView(
            padding: Insets.page,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _StatusRow(site: site),
              const SizedBox(height: 12),
              _LocationCard(site: site),
              if (site.generalNotes != null && site.generalNotes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(LucideIcons.fileText, size: 15, color: context.mutedText),
                          const SizedBox(width: 6),
                          Text(
                            'ملاحظات عامة',
                            style: context.texts.labelMedium?.copyWith(
                              color: context.mutedText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(site.generalNotes!, style: context.texts.bodyMedium?.copyWith(height: 1.55)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (canAddChildren)
                Row(
                  children: [
                    Expanded(
                      child: ShadButton(
                        size: ShadButtonSize.lg,
                        onPressed: () => context.push('/sites/${site.id}/visits/new'),
                        leading: const Icon(LucideIcons.notebookPen, size: 17),
                        child: const Text('زيارة جديدة'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ShadButton.outline(
                        size: ShadButtonSize.lg,
                        onPressed: () => context.push('/tasks/new?siteId=${site.id}'),
                        leading: const Icon(LucideIcons.plus, size: 17),
                        child: const Text('مهمة'),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              SectionTitle(
                title: 'المهام الحالية (${openTasks.length})',
                trailing: openTasks.isEmpty
                    ? null
                    : ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        onPressed: () {
                          ref.read(tasksFilterProvider.notifier).setSite(site.id);
                          context.go('/tasks');
                        },
                        child: const Text('الكل'),
                      ),
              ),
              if (openTasks.isEmpty)
                const EmptyState(
                  icon: LucideIcons.checkCheck,
                  title: 'مفيش مهام مفتوحة',
                  message: 'المهام دي هي الشغل الحالي على الموقع.',
                  compact: true,
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < openTasks.length; index++) ...[
                        if (index > 0) Divider(height: 1, color: context.hairline),
                        TaskRow(
                          task: openTasks[index],
                          showSite: false,
                          onTap: canWrite
                              ? () => context.push(
                                  '/tasks/${openTasks[index].id}/edit',
                                  extra: openTasks[index],
                                )
                              : null,
                          onToggle: canWrite ? () => _toggleTask(openTasks[index]) : null,
                        ),
                      ],
                    ],
                  ),
                ),
              if (doneTasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                _DoneTasks(tasks: doneTasks, onToggle: canWrite ? _toggleTask : null),
              ],
              const SizedBox(height: 24),
              SectionTitle(
                title: 'سجل الزيارات (${visits.length})',
                trailing: visits.length > 4
                    ? ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        onPressed: () => setState(() => _showAllVisits = !_showAllVisits),
                        child: Text(_showAllVisits ? 'أقل' : 'الكل'),
                      )
                    : null,
              ),
              if (visits.isEmpty)
                const EmptyState(
                  icon: LucideIcons.history,
                  title: 'مفيش زيارات مسجّلة',
                  message: 'كل زيارة بتتسجل لوحدها، والتاريخ ما بيتغيرش.',
                  compact: true,
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < visibleVisits.length; index++) ...[
                        if (index > 0) Divider(height: 1, color: context.hairline),
                        VisitRow(
                          visit: visibleVisits[index],
                          onTap: canWrite
                              ? () => context.push(
                                  '/sites/${site.id}/visits/${visibleVisits[index].id}/edit',
                                  extra: visibleVisits[index],
                                )
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'الزيارات سجل تاريخي. تعديل زيارة بيتم بضغطة صريحة وبيتسجل معاها إنها اتعدّلت.',
                style: context.texts.labelSmall?.copyWith(color: context.mutedText, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showActions(Site site, bool canWrite) async {
    final archived = site.status == SiteStatus.archived;
    await showShadSheet(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (sheetContext) => ShadSheet(
        title: Text(site.name),
        description: const Text('إجراءات الموقع'),
        actions: [
          if (canWrite)
            ShadButton.outline(
              width: double.infinity,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _setArchived(site, !archived);
              },
              leading: Icon(archived ? LucideIcons.rotateCcw : LucideIcons.archive, size: 16),
              child: Text(archived ? 'رجّع الموقع نشط' : 'أرشف الموقع'),
            ),
          ShadButton.ghost(
            width: double.infinity,
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.site});

  final Site site;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        Tag(
          label: site.scope == SiteScope.company ? 'موقع شركة' : 'شغلي',
          icon: site.scope == SiteScope.company ? LucideIcons.building2 : LucideIcons.userRound,
          color: context.scheme.secondary,
          foreground: context.scheme.secondaryForeground,
          outline: false,
        ),
        if (site.status == SiteStatus.archived)
          Tag(label: 'مؤرشف', icon: LucideIcons.archive),
        if (site.pending) const PendingTag(),
        if (site.lastVisit != null)
          Tag(
            label: 'آخر زيارة ${AppFormat.relativeDay(site.lastVisit!.visitDate)}',
            icon: LucideIcons.history,
          ),
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.site});

  final Site site;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.mapPin, size: 17, color: context.scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  site.address.isEmpty ? 'مفيش عنوان مسجّل' : site.address,
                  style: context.texts.bodyMedium?.copyWith(height: 1.45),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ShadButton.outline(
                  size: ShadButtonSize.sm,
                  onPressed: () => openExternalLink(context, site.mapLink),
                  leading: const Icon(LucideIcons.externalLink, size: 14),
                  child: const Text('افتح الخريطة'),
                ),
              ),
              if (site.contactPhone != null && site.contactPhone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => openExternalLink(context, 'tel:${site.contactPhone}'),
                    leading: const Icon(LucideIcons.phone, size: 14),
                    child: Text(site.contactPhone!, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ],
          ),
          if (site.contactName != null && site.contactName!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(LucideIcons.userRound, size: 13, color: context.mutedText),
                const SizedBox(width: 6),
                Text(
                  'جهة الاتصال: ${site.contactName}',
                  style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DoneTasks extends StatefulWidget {
  const _DoneTasks({required this.tasks, this.onToggle});

  final List<Task> tasks;
  final Future<void> Function(Task task)? onToggle;

  @override
  State<_DoneTasks> createState() => _DoneTasksState();
}

class _DoneTasksState extends State<_DoneTasks> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: () => setState(() => _open = !_open),
          leading: Icon(
            _open ? LucideIcons.chevronDown : LucideIcons.chevronLeft,
            size: 14,
          ),
          child: Text('مهام خلصت (${widget.tasks.length})'),
        ),
        if (_open)
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < widget.tasks.length; index++) ...[
                  if (index > 0) Divider(height: 1, color: context.hairline),
                  TaskRow(
                    task: widget.tasks[index],
                    showSite: false,
                    onToggle: widget.onToggle == null
                        ? null
                        : () => widget.onToggle!(widget.tasks[index]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
