import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/task.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/list_items.dart';
import '../common/ui.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      ref.read(tasksFilterProvider.notifier).setQuery(value.trim());
    });
  }

  Future<void> _refresh() => ref.read(tasksProvider.notifier).refresh();

  Future<void> _toggle(Task task) async {
    final next = task.status == TaskStatus.done ? TaskStatus.open : TaskStatus.done;
    try {
      await ref.read(mutationsProvider).updateTask(task, status: next);
      ref.invalidate(tasksProvider);
      ref.invalidate(overviewProvider);
      if (task.siteId != null) ref.invalidate(siteDetailProvider(task.siteId!));
      unawaited(ref.read(mutationsProvider).flushQuietly());
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

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(tasksFilterProvider);
    final tasks = ref.watch(tasksProvider);
    final siteId = filter.siteId;

    return ScreenScaffold(
      title: 'المهام',
      subtitle: 'قائمة الشغل الحالية. الزيارات سجل منفصل.',
      header: const SyncBanner(),
      onRefresh: _refresh,
      actions: [
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.plus, size: 20),
          onPressed: () => context.push('/tasks/new'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SearchBox(
              placeholder: 'دوّر على مهمة…',
              onChanged: _onQueryChanged,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'مفتوحة',
                  selected: _sameSet(filter.statuses, const {
                    TaskStatus.open,
                    TaskStatus.inProgress,
                  }),
                  onTap: () => ref.read(tasksFilterProvider.notifier).setStatuses(const {
                    TaskStatus.open,
                    TaskStatus.inProgress,
                  }),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'شغّال عليها',
                  selected: _sameSet(filter.statuses, const {TaskStatus.inProgress}),
                  onTap: () => ref.read(tasksFilterProvider.notifier).setStatuses(const {
                    TaskStatus.inProgress,
                  }),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'خلصت',
                  selected: _sameSet(filter.statuses, const {TaskStatus.done}),
                  onTap: () => ref.read(tasksFilterProvider.notifier).setStatuses(const {
                    TaskStatus.done,
                  }),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'الكل',
                  selected: filter.statuses == null,
                  onTap: () => ref.read(tasksFilterProvider.notifier).setStatuses(null),
                ),
              ],
            ),
          ),
          if (siteId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Tag(
                    label: 'مفلترة على موقع واحد',
                    icon: LucideIcons.mapPin,
                    color: context.scheme.secondary,
                    foreground: context.scheme.secondaryForeground,
                    outline: false,
                  ),
                  const SizedBox(width: 8),
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () => ref.read(tasksFilterProvider.notifier).setSite(null),
                    child: const Text('شيل الفلتر'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: AsyncContent<List<Task>>(
              value: tasks,
              onRetry: _refresh,
              builder: (list) {
                if (list.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 30),
                      EmptyState(
                        icon: filter.query.isNotEmpty
                            ? LucideIcons.search
                            : LucideIcons.checkCheck,
                        title: filter.query.isNotEmpty ? 'مفيش نتائج' : 'مفيش مهام هنا',
                        message: filter.query.isNotEmpty
                            ? 'جرّب كلمة تانية.'
                            : 'ضيف مهمة عشان تتابع الشغل الحالي على المواقع.',
                        action: filter.query.isNotEmpty
                            ? null
                            : ShadButton(
                                onPressed: () => context.push(
                                  siteId == null ? '/tasks/new' : '/tasks/new?siteId=$siteId',
                                ),
                                leading: const Icon(LucideIcons.plus, size: 16),
                                child: const Text('ضيف مهمة'),
                              ),
                      ),
                    ],
                  );
                }

                final open = list.where((task) => task.status.isOpen).toList(growable: false);
                final done = list.where((task) => !task.status.isOpen).toList(growable: false);

                return ListView(
                  padding: Insets.page,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (open.isNotEmpty) ...[
                      SectionTitle(title: 'شغّل جاري (${open.length})'),
                      SurfaceCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var index = 0; index < open.length; index++) ...[
                              if (index > 0) Divider(height: 1, color: context.hairline),
                              TaskRow(
                                task: open[index],
                                onTap: () => context.push(
                                  '/tasks/${open[index].id}/edit',
                                  extra: open[index],
                                ),
                                onToggle: () => _toggle(open[index]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (done.isNotEmpty) ...[
                      SectionTitle(title: 'خلصت (${done.length})'),
                      SurfaceCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var index = 0; index < done.length; index++) ...[
                              if (index > 0) Divider(height: 1, color: context.hairline),
                              TaskRow(
                                task: done[index],
                                onTap: () => context.push(
                                  '/tasks/${done[index].id}/edit',
                                  extra: done[index],
                                ),
                                onToggle: () => _toggle(done[index]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameSet(Set<TaskStatus>? a, Set<TaskStatus> b) {
    if (a == null) return false;
    return setEquals(a, b);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return ShadButton(
        size: ShadButtonSize.sm,
        onPressed: onTap,
        child: Text(label),
      );
    }
    return ShadButton.outline(
      size: ShadButtonSize.sm,
      onPressed: onTap,
      child: Text(label),
    );
  }
}
