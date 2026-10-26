import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_exception.dart';
import '../../state/data_providers.dart';

/// Shared layout and feedback widgets.
///
/// Everything here reads the shadcn theme so screens stay visually consistent
/// and the light/dark switch needs no per-screen work.
class Insets {
  const Insets._();

  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 4, 16, 28);
  static const EdgeInsets card = EdgeInsets.all(16);
  static const double gap = 16;
  static const double gapSmall = 8;
  static const double gapLarge = 24;
}

extension ThemeAccess on BuildContext {
  ShadColorScheme get scheme => ShadTheme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get mutedText => scheme.mutedForeground;

  Color get hairline => scheme.border;
}

/// Human-readable message for any thrown object.
String describeError(Object error) {
  if (error is ApiException) return error.message;
  return 'حصل خطأ غير متوقع. جرّب تاني.';
}

// ------------------------------------------------------------------ toasts

void showToast(
  BuildContext context, {
  required String title,
  String? description,
  bool destructive = false,
}) {
  final toaster = ShadToaster.maybeOf(context);
  if (toaster == null) return;
  final titleWidget = Text(title);
  final descriptionWidget = description == null ? null : Text(description);
  toaster.show(
    destructive
        ? ShadToast.destructive(title: titleWidget, description: descriptionWidget)
        : ShadToast(title: titleWidget, description: descriptionWidget),
  );
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String description,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
}) async {
  final result = await showShadDialog<bool>(
    context: context,
    builder: (dialogContext) => ShadDialog.alert(
      title: Text(title),
      description: Text(description),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        ShadButton(
          backgroundColor: destructive ? dialogContext.scheme.destructive : null,
          foregroundColor: destructive ? dialogContext.scheme.destructiveForeground : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

// -------------------------------------------------------------- page header

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.texts.bodySmall?.copyWith(color: context.mutedText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Standard page chrome: fixed header, scrollable body, optional bottom bar.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
    this.header,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget child;
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;

  /// Pinned under the page header, outside the scroll area (sync banners etc).
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final body = onRefresh == null
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh!,
            color: context.scheme.primary,
            backgroundColor: context.scheme.card,
            child: child,
          );

    return Scaffold(
      backgroundColor: context.scheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader(title: title, subtitle: subtitle, leading: leading, actions: actions),
            ?header,
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : SafeArea(top: false, child: bottomBar!),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: context.texts.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.mutedText,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ async states

class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: context.scheme.primary),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: context.texts.bodySmall?.copyWith(color: context.mutedText)),
          ],
        ],
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert, size: 34, color: context.scheme.destructive),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyMedium?.copyWith(color: context.mutedText),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ShadButton.outline(
                onPressed: onRetry,
                leading: const Icon(LucideIcons.refreshCw, size: 16),
                child: const Text('جرّب تاني'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: compact ? 20 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.scheme.muted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: context.mutedText),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.texts.bodySmall?.copyWith(color: context.mutedText, height: 1.5),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] with consistent loading and error states.
class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loadingLabel,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final String? loadingLabel;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => loading ?? LoadingState(label: loadingLabel),
      error: (error, _) => ErrorState(message: describeError(error), onRetry: onRetry),
    );
  }
}

// ------------------------------------------------------------------ pieces

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = Insets.card,
    this.onTap,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final card = ShadCard(
      padding: padding,
      backgroundColor: backgroundColor ?? context.scheme.card,
      child: child,
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.label,
    this.icon,
    this.color,
    this.foreground,
    this.outline = true,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? foreground;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: foreground ?? context.mutedText),
          const SizedBox(width: 4),
        ],
        Text(label, style: context.texts.labelSmall?.copyWith(color: foreground)),
      ],
    );
    if (outline) {
      return ShadBadge.outline(
        backgroundColor: color,
        foregroundColor: foreground,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: content,
      );
    }
    return ShadBadge(
      backgroundColor: color,
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: content,
    );
  }
}

class PendingTag extends StatelessWidget {
  const PendingTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Tag(
      label: 'بانتظار المزامنة',
      icon: LucideIcons.cloudOff,
      color: context.scheme.muted,
      foreground: context.scheme.mutedForeground,
    );
  }
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.helper,
    this.optional = false,
  });

  final String label;
  final Widget child;
  final String? helper;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: context.texts.labelMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (optional) ...[
              const SizedBox(width: 6),
              Text(
                'اختياري',
                style: context.texts.labelSmall?.copyWith(color: context.mutedText),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper!,
            style: context.texts.bodySmall?.copyWith(color: context.mutedText),
          ),
        ],
      ],
    );
  }
}

/// Search box with a clear button, used on the sites and tasks screens.
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.onChanged,
    this.placeholder = 'دوّر…',
    this.initialValue = '',
  });

  final ValueChanged<String> onChanged;
  final String placeholder;
  final String initialValue;

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.initialValue.isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShadInput(
      controller: _controller,
      placeholder: Text(widget.placeholder),
      leading: Icon(LucideIcons.search, size: 16, color: context.mutedText),
      trailing: _hasText
          ? ShadIconButton.ghost(
              width: 24,
              height: 24,
              icon: const Icon(LucideIcons.x, size: 14),
              onPressed: () {
                _controller.clear();
                setState(() => _hasText = false);
                widget.onChanged('');
              },
            )
          : null,
      onChanged: (value) {
        if ((value.isNotEmpty) != _hasText) {
          setState(() => _hasText = value.isNotEmpty);
        }
        widget.onChanged(value);
      },
    );
  }
}

/// Small status line used under page headers.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    if (!status.hasQueued && !status.offline && status.lastError == null) {
      return const SizedBox.shrink();
    }

    final (title, description, icon) = switch (status) {
      SyncStatus(conflicts: final conflicts) when conflicts > 0 => (
        '$conflicts تغيير محتاج مراجعة',
        'حد تاني عدّل نفس الحاجة على السيرفر. افتح الإعدادات واختار نسختك.',
        LucideIcons.triangleAlert,
      ),
      SyncStatus(offline: true) => (
        'مفيش اتصال',
        'كل حاجة بتتقرا من الكاش، وأي تعديل بيتحفظ ويتزامن لما الشبكة ترجع.',
        LucideIcons.wifiOff,
      ),
      SyncStatus(pending: final pending) when pending > 0 => (
        '$pending تغيير مستني المزامنة',
        'التغييرات محفوظة على الجهاز وهترفع لوحدها.',
        LucideIcons.cloudOff,
      ),
      _ => (
        'المزامنة وقفت',
        status.lastError ?? 'جرّب المزامنة يدوي.',
        LucideIcons.circleAlert,
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ShadAlert(
        icon: Icon(icon, size: 18),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        description: Text(description),
        trailing: ShadButton.ghost(
          size: ShadButtonSize.sm,
          onPressed: status.syncing ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
          child: status.syncing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('زامن'),
        ),
      ),
    );
  }
}

/// A metric tile used on the dashboard. Values are always real counts.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: context.mutedText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: context.texts.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Bottom action bar for forms.
class FormActions extends StatelessWidget {
  const FormActions({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.secondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: context.scheme.background,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: Row(
        children: [
          if (secondary != null) ...[secondary!, const SizedBox(width: 10)],
          Expanded(
            child: ShadButton(
              size: ShadButtonSize.lg,
              onPressed: busy ? null : onPressed,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(label),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens a URL and surfaces a readable failure instead of throwing.
Future<void> openExternalLink(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) {
    showToast(context, title: 'مفيش لينك متاح', description: 'ضيف عنوان أو إحداثيات للموقع الأول.');
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) {
    showToast(context, title: 'اللينك غير صالح', destructive: true);
    return;
  }
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showToast(context, title: 'مقدرناش نفتح الخريطة', destructive: true);
    }
  } catch (_) {
    if (context.mounted) {
      showToast(context, title: 'مقدرناش نفتح الخريطة', destructive: true);
    }
  }
}
