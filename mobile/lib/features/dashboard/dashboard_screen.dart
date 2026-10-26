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

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await ref.read(overviewProvider.notifier).refresh();
  }

  Future<void> _toggleTask(Task task) async {
    final next = task.status == TaskStatus.done ? TaskStatus.open : TaskStatus.done;
    try {
      await ref.read(mutationsProvider).updateTask(task, status: next);
      ref.invalidate(overviewProvider);
      ref.invalidate(tasksProvider);
    } catch (error) {
      if (mounted) showToast(context, title: 'مقدرناش نحدّث المهمة', description: describeError(error), destructive: true);
    }
  }

  List<Site> _filterSites(List<Site> sites) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return sites;
    return sites
        .where(
          (site) =>
              site.name.toLowerCase().contains(query) ||
              site.address.toLowerCase().contains(query) ||
              (site.workspaceName?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final user = currentUserOf(ref);
    final overview = ref.watch(overviewProvider);
    // The dashboard's own site list is a short "recent" slice. Searching must
    // look at every site the user can see, otherwise sites outside the slice
    // are silently unreachable from the home screen.
    final allSites = ref.watch(allSitesProvider);

    return ScreenScaffold(
      title: user == null ? 'الرئيسية' : 'أهلاً، ${user.name.split(' ').first}',
      subtitle: overview.value == null ? null : AppFormat.fullDate(overview.value!.today),
      header: const SyncBanner(),
      onRefresh: _refresh,
      actions: [
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          onPressed: _refresh,
        ),
      ],
      child: AsyncContent<Overview?>(
        value: overview,
        onRetry: _refresh,
        builder: (data) {
          if (data == null) {
            return const EmptyState(
              icon: LucideIcons.database,
              title: 'مفيش بيانات محفوظة',
              message: 'اتصل بالإنترنت مرة واحدة عشان نحمّل مواقعك ومهامك.',
            );
          }

          final searchPool = _query.trim().isEmpty
              ? data.recentSites
              : (allSites.value ?? data.recentSites);
          final sites = _filterSites(searchPool);

          return ListView(
            padding: Insets.page,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _VoiceCard(onTap: () => context.go('/voice')),
              const SizedBox(height: Insets.gap),
              ShadInput(
                controller: _search,
                placeholder: const Text('دوّر على موقع بالاسم أو العنوان…'),
                leading: Icon(LucideIcons.search, size: 16, color: context.mutedText),
                trailing: _query.isEmpty
                    ? null
                    : ShadIconButton.ghost(
                        width: 24,
                        height: 24,
                        icon: const Icon(LucideIcons.x, size: 14),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: Insets.gap),
              _Metrics(counts: data.counts),
              const SizedBox(height: Insets.gapLarge),
              if (_query.isNotEmpty) ...[
                SectionTitle(title: 'نتائج البحث (${sites.length})'),
                if (sites.isEmpty)
                  const EmptyState(
                    icon: LucideIcons.search,
                    title: 'مفيش نتائج',
                    message: 'جرّب اسم تاني أو جزء من العنوان.',
                    compact: true,
                  )
                else
                  SurfaceCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var index = 0; index < sites.length; index++) ...[
                          if (index > 0) Divider(height: 1, color: context.hairline),
                          SiteRow(
                            site: sites[index],
                            showScope: true,
                            onTap: () => context.push('/sites/${sites[index].id}'),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: Insets.gapLarge),
              ],
              SectionTitle(
                title: 'زيارات النهارده',
                trailing: data.todayVisits.isEmpty
                    ? null
                    : Text(
                        '${data.todayVisits.length}',
                        style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                      ),
              ),
              if (data.todayVisits.isEmpty)
                const EmptyState(
                  icon: LucideIcons.history,
                  title: 'مفيش زيارات النهارده',
                  message: 'أول ما تسجّل زيارة هتظهر هنا.',
                  compact: true,
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < data.todayVisits.length; index++) ...[
                        if (index > 0) Divider(height: 1, color: context.hairline),
                        VisitRow(
                          visit: data.todayVisits[index],
                          showSite: true,
                          onTap: data.todayVisits[index].siteId.isEmpty
                              ? null
                              : () => context.push('/sites/${data.todayVisits[index].siteId}'),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: Insets.gapLarge),
              SectionTitle(
                title: 'مهام مفتوحة',
                trailing: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => context.go('/tasks'),
                  child: const Text('الكل'),
                ),
              ),
              if (data.upcomingTasks.isEmpty)
                const EmptyState(
                  icon: LucideIcons.checkCheck,
                  title: 'مفيش مهام مفتوحة',
                  message: 'كل حاجة خلصت. تقدر تضيف مهمة من تاب المهام.',
                  compact: true,
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < data.upcomingTasks.length; index++) ...[
                        if (index > 0) Divider(height: 1, color: context.hairline),
                        TaskRow(
                          task: data.upcomingTasks[index],
                          onTap: () => context.push(
                            '/tasks/${data.upcomingTasks[index].id}/edit',
                            extra: data.upcomingTasks[index],
                          ),
                          onToggle: () => _toggleTask(data.upcomingTasks[index]),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: Insets.gapLarge),
              SectionTitle(
                title: 'مواقع اتحدّثت قريب',
                trailing: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => context.go('/sites'),
                  child: const Text('الكل'),
                ),
              ),
              if (data.recentSites.isEmpty)
                EmptyState(
                  icon: LucideIcons.mapPin,
                  title: 'مفيش مواقع لسه',
                  message: 'ابدأ بإضافة موقع الشركة الأول أو موقع خاص بشغلك.',
                  action: ShadButton(
                    onPressed: () => context.push('/sites/new'),
                    leading: const Icon(LucideIcons.plus, size: 16),
                    child: const Text('ضيف موقع'),
                  ),
                  compact: true,
                )
              else
                SurfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var index = 0; index < data.recentSites.length; index++) ...[
                        if (index > 0) Divider(height: 1, color: context.hairline),
                        SiteRow(
                          site: data.recentSites[index],
                          showScope: true,
                          onTap: () => context.push('/sites/${data.recentSites[index].id}'),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(18),
      backgroundColor: context.scheme.primary.withValues(alpha: context.isDark ? 0.14 : 0.09),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.sparkles,
                  size: 19,
                  color: context.scheme.primaryForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'احكي اللي عملته',
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'المساعد يسمعك، يجهّز مسودة زيارة، وإنت تأكّد قبل الحفظ.',
                      style: context.texts.bodySmall?.copyWith(color: context.mutedText, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ShadButton(
            size: ShadButtonSize.lg,
            width: double.infinity,
            onPressed: onTap,
            leading: const Icon(LucideIcons.mic, size: 17),
            child: const Text('افتح المساعد'),
          ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.counts});

  final OverviewCounts counts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'مواقع الشركة',
                value: '${counts.companySites}',
                icon: LucideIcons.building2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'شغلي',
                value: '${counts.personalSites}',
                icon: LucideIcons.userRound,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: MetricTile(
                label: 'زيارات النهارده',
                value: '${counts.todayVisits}',
                icon: LucideIcons.history,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                label: 'مهام مفتوحة',
                value: '${counts.openTasks}',
                icon: LucideIcons.checkSquare,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
