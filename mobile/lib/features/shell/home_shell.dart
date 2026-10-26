import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../state/data_providers.dart';
import '../../state/voice_controller.dart';
import '../common/ui.dart';

/// Five-tab shell: dashboard, sites, assistant, tasks, settings.
///
/// The assistant sits in the middle as the one large, high-contrast action so
/// it stays reachable with a thumb while standing at a site.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Foreground-only sync loop; there is no background worker by design.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncControllerProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(syncControllerProvider.notifier).start();
      unawaited(ref.read(syncControllerProvider.notifier).syncNow(silent: true));
    } else if (state == AppLifecycleState.paused) {
      // No background worker by design, and the microphone must not keep
      // streaming while the app is in the background.
      ref.read(syncControllerProvider.notifier).pause();
      unawaited(ref.read(voiceControllerProvider.notifier).stopLive());
    }
  }

  void _go(int index) {
    // The assistant tab owns the microphone and the Live socket. Leaving the
    // tab must release both, otherwise audio keeps streaming off-screen.
    if (widget.shell.currentIndex == 2 && index != 2) {
      unawaited(ref.read(voiceControllerProvider.notifier).stopLive());
    }
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scheme.background,
      body: widget.shell,
      bottomNavigationBar: _BottomBar(
        currentIndex: widget.shell.currentIndex,
        onSelected: _go,
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

const List<_NavItem> _items = [
  _NavItem(LucideIcons.house, 'الرئيسية'),
  _NavItem(LucideIcons.mapPin, 'المواقع'),
  _NavItem(LucideIcons.mic, 'المساعد'),
  _NavItem(LucideIcons.checkSquare, 'المهام'),
  _NavItem(LucideIcons.settings, 'الإعدادات'),
];

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.background,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++)
                Expanded(
                  child: index == 2
                      ? _VoiceTab(
                          item: _items[index],
                          selected: currentIndex == index,
                          onTap: () => onSelected(index),
                        )
                      : _Tab(
                          item: _items[index],
                          selected: currentIndex == index,
                          onTap: () => onSelected(index),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.scheme.primary : context.mutedText;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 21, color: color),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: context.texts.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceTab extends StatelessWidget {
  const _VoiceTab({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected ? context.scheme.primary : context.scheme.secondary,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: selected ? context.scheme.primary : context.hairline,
                ),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: selected ? context.scheme.primaryForeground : context.scheme.foreground,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: context.texts.labelSmall?.copyWith(
                color: selected ? context.scheme.primary : context.mutedText,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
