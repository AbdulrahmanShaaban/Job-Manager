import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/site.dart';
import '../../state/data_providers.dart';
import '../common/list_items.dart';
import '../common/ui.dart';

class SitesScreen extends ConsumerStatefulWidget {
  const SitesScreen({super.key});

  @override
  ConsumerState<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends ConsumerState<SitesScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      ref.read(sitesFilterProvider.notifier).setQuery(value.trim());
    });
  }

  Future<void> _refresh() => ref.read(sitesProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(sitesFilterProvider);
    final sites = ref.watch(sitesProvider);

    return ScreenScaffold(
      title: 'المواقع',
      subtitle: 'مواقع الشركة المشتركة، والمواقع الخاصة بشغلك.',
      header: const SyncBanner(),
      onRefresh: _refresh,
      actions: [
        ShadIconButton.ghost(
          icon: const Icon(LucideIcons.plus, size: 20),
          onPressed: () => context.push('/sites/new'),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SearchBox(
              placeholder: 'دوّر بالاسم أو العنوان…',
              onChanged: _onQueryChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ShadTabs<SiteScope>(
              value: filter.scope ?? SiteScope.company,
              tabs: [
                ShadTab<SiteScope>(
                  value: SiteScope.company,
                  content: const SizedBox.shrink(),
                  child: const Text('مواقع الشركة'),
                ),
                ShadTab<SiteScope>(
                  value: SiteScope.personal,
                  content: const SizedBox.shrink(),
                  child: const Text('شغلي'),
                ),
              ],
              onChanged: (value) {
                ref.read(sitesFilterProvider.notifier).setScope(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                _StatusChip(
                  label: 'نشط',
                  selected: filter.status == SiteStatus.active,
                  onTap: () => ref.read(sitesFilterProvider.notifier).setStatus(SiteStatus.active),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  label: 'مؤرشف',
                  selected: filter.status == SiteStatus.archived,
                  onTap: () =>
                      ref.read(sitesFilterProvider.notifier).setStatus(SiteStatus.archived),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncContent<List<Site>>(
              value: sites,
              onRetry: _refresh,
              builder: (list) {
                if (list.isEmpty) {
                  final searching = filter.query.isNotEmpty;
                  final archived = filter.status == SiteStatus.archived;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 30),
                      EmptyState(
                        icon: searching
                            ? LucideIcons.search
                            : archived
                            ? LucideIcons.archive
                            : LucideIcons.mapPin,
                        title: searching
                            ? 'مفيش نتائج'
                            : archived
                            ? 'مفيش مواقع مؤرشفة'
                            : 'مفيش مواقع هنا لسه',
                        message: searching
                            ? 'جرّب كلمة تانية.'
                            : archived
                            ? 'المواقع اللي بتأرشفها بتظهر هنا.'
                            : 'ضيف أول موقع، وابدأ تسجّل زيارات ومهام عليه.',
                        action: searching || archived
                            ? null
                            : ShadButton(
                                onPressed: () => context.push('/sites/new'),
                                leading: const Icon(LucideIcons.plus, size: 16),
                                child: const Text('ضيف موقع'),
                              ),
                      ),
                    ],
                  );
                }

                return ListView.separated(
                  padding: Insets.page,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: list.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final site = list[index];
                    return SurfaceCard(
                      padding: EdgeInsets.zero,
                      child: SiteRow(
                        site: site,
                        onTap: () => context.push('/sites/${site.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.selected, required this.onTap});

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
