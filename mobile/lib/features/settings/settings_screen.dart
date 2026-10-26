import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/formatting.dart';
import '../../data/local_db.dart';
import '../../models/user.dart';
import '../../models/voice.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/ui.dart';

final voiceStatusProvider = FutureProvider<VoiceStatus>((ref) async {
  return ref.watch(apiRepositoryProvider).voiceStatus();
});

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;

  Future<void> _exportJson() async {
    await _writeExport(
      extension: 'json',
      entity: null,
      load: () async {
        final data = await ref.read(apiRepositoryProvider).exportJson();
        return const JsonEncoder.withIndent('  ').convert(data);
      },
    );
  }

  Future<void> _pickCsvEntity() async {
    await showShadSheet(
      context: context,
      side: ShadSheetSide.bottom,
      builder: (sheetContext) => ShadSheet(
        title: const Text('تصدير CSV'),
        description: const Text('اختار البيانات اللي عايز تصدّرها.'),
        actions: [
          for (final entity in const ['sites', 'visits', 'tasks'])
            ShadButton.outline(
              width: double.infinity,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                _exportCsv(entity);
              },
              leading: const Icon(LucideIcons.fileText, size: 16),
              child: Text(_entityLabel(entity)),
            ),
          ShadButton.ghost(
            width: double.infinity,
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(String entity) async {
    await _writeExport(
      extension: 'csv',
      entity: entity,
      load: () => ref.read(apiRepositoryProvider).exportCsv(entity),
    );
  }

  Future<void> _writeExport({
    required String extension,
    required String? entity,
    required Future<String> Function() load,
  }) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final contents = await load();
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .replaceAll('T', '-');
      final name = 'job-manager-${entity ?? 'all'}-$stamp.$extension';
      final file = File('${directory.path}/$name');
      await file.writeAsString(contents, flush: true);

      // The app documents directory is private on Android and iOS, so hand the
      // file to the system share sheet where the user can save or send it.
      if (!mounted) return;
      Rect? origin;
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        origin = box.localToGlobal(Offset.zero) & box.size;
      }
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              name: name,
              mimeType: extension == 'csv' ? 'text/csv' : 'application/json',
            ),
          ],
          subject: 'تصدير مدير الشغل',
          sharePositionOrigin: origin,
        ),
      );

      if (!mounted) return;
      showToast(
        context,
        title: 'التصدير جاهز',
        description: result.status == ShareResultStatus.dismissed
            ? 'الملف $name اتحفظ على الجهاز. تقدر تشاركه في أي وقت.'
            : 'الملف $name جاهز للمشاركة أو الحفظ.',
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          title: 'مقدرناش نصدّر',
          description: describeError(error),
          destructive: true,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _syncNow() async {
    await ref.read(syncControllerProvider.notifier).syncNow();
    ref.invalidate(syncConflictProvider);
    ref.invalidate(syncFailedProvider);
    if (!mounted) return;
    final status = ref.read(syncControllerProvider);
    showToast(
      context,
      title: status.offline ? 'مفيش اتصال' : 'المزامنة خلصت',
      description: status.offline
          ? 'التغييرات محفوظة على الجهاز وهتترفع لما الشبكة ترجع.'
          : status.lastError,
      destructive: status.lastError != null && !status.offline,
    );
  }

  Future<void> _resolveConflict(OutboxItem item, {required bool keepLocal}) async {
    await ref
        .read(syncControllerProvider.notifier)
        .resolveConflict(item.id, keepLocal: keepLocal);
    ref.invalidate(syncConflictProvider);
    ref.invalidate(syncFailedProvider);
    if (!mounted) return;
    showToast(
      context,
      title: keepLocal ? 'هنرفع نسختك' : 'اتمسحت نسختك المحلية',
      description: keepLocal
          ? 'التغيير رجع لقائمة الانتظار وهيتزامن دلوقتي.'
          : 'نسخة السيرفر هي اللي هتفضل.',
    );
  }

  Future<void> _retryFailed(OutboxItem item) async {
    await ref.read(syncControllerProvider.notifier).retryFailed(item.id);
    ref.invalidate(syncFailedProvider);
    ref.invalidate(syncConflictProvider);
    if (!mounted) return;
    final remaining = await ref.read(localDbProvider).itemById(item.id);
    if (!mounted) return;
    final uploaded = remaining == null;
    final conflict = remaining?.state == OutboxState.conflict;
    showToast(
      context,
      title: uploaded ? 'اترفع' : (conflict ? 'محتاج مراجعة' : 'لسه فيه مشكلة'),
      description: uploaded
          ? 'التغيير وصل للسيرفر.'
          : conflict
          ? 'حد تاني عدّل نفس السجل. راجعه من قائمة التعارضات.'
          : 'التغيير فشل تاني. راجع التفاصيل أو امسحه وسجّله من جديد.',
      destructive: !uploaded,
    );
  }

  Future<void> _discardFailed(OutboxItem item) async {
    final confirmed = await showConfirm(
      context,
      title: 'تمسح التغيير ده؟',
      description:
          'التغيير اللي فشل هيتشال من الجهاز نهائي. لو محتاجه، سجّله من جديد بعد ما تصلّح المشكلة.',
      confirmLabel: 'امسح',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(syncControllerProvider.notifier).discardFailed(item.id);
    ref.invalidate(syncFailedProvider);
    if (!mounted) return;
    showToast(
      context,
      title: 'اتمسح',
      description: 'التغيير الفاشل اتشال من قائمة الانتظار.',
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showConfirm(
      context,
      title: 'تسجيل الخروج؟',
      description:
          'هتتشال بيانات الجلسة من الجهاز. أي تغييرات لسه بانتظار المزامنة هتضيع، '
          'فالأفضل تتأكد إن المزامنة خلصت الأول.',
      confirmLabel: 'اخرج',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(authProvider.notifier).logout();
  }

  static String _entityLabel(String entity) => switch (entity) {
    'sites' => 'المواقع',
    'visits' => 'الزيارات',
    'tasks' => 'المهام',
    _ => entity,
  };

  static String _roleLabel(String? role) => switch (role) {
    'OWNER' => 'مالك',
    'ADMIN' => 'مدير',
    'EDITOR' => 'محرر',
    'VIEWER' => 'مشاهد',
    _ => 'عضو',
  };

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider).value;
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final user = auth?.user;
    final workspaces = auth?.workspaces ?? const <Workspace>[];
    final sync = ref.watch(syncControllerProvider);

    return ScreenScaffold(
      title: 'الإعدادات',
      subtitle: 'الحساب، الخصوصية، والبيانات.',
      header: const SyncBanner(),
      child: ListView(
        padding: Insets.page,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (user != null) _AccountCard(user: user, workspaces: workspaces, offline: auth?.offline ?? false),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'الشكل'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'وضع العرض',
                  style: context.texts.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Choice(
                        label: 'غامق',
                        selected: settings.themeMode == ThemeMode.dark,
                        onTap: () => ref.read(settingsProvider.notifier).setThemeMode(ThemeMode.dark),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Choice(
                        label: 'فاتح',
                        selected: settings.themeMode == ThemeMode.light,
                        onTap: () => ref.read(settingsProvider.notifier).setThemeMode(ThemeMode.light),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Choice(
                        label: 'النظام',
                        selected: settings.themeMode == ThemeMode.system,
                        onTap: () => ref.read(settingsProvider.notifier).setThemeMode(ThemeMode.system),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Divider(height: 20, color: context.hairline),
                ShadSwitch(
                  value: settings.speakReplies,
                  label: const Text('المساعد يقرأ الرد بصوت'),
                  sublabel: const Text('بيستخدم صوت الجهاز — مجاني وبدون إنترنت.'),
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setSpeakReplies(value),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'الخصوصية'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShadSwitch(
                  value: settings.keepTranscripts,
                  label: const Text('احتفظ بنص المحادثة'),
                  sublabel: const Text(
                    'النص بيتسجل مع الزيارة اللي اتعملت بالصوت، ويساعدك تراجع اللي اتقال.',
                  ),
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setKeepTranscripts(value),
                ),
                const SizedBox(height: 10),
                Text(
                  'التطبيق مش بيسجّل الصوت نفسه. المساعد بيبعت الصوت للمزوّد وقت الجلسة بس، '
                  'والسيرفر بيحتفظ بملخص قصير للاستخدام فقط.',
                  style: context.texts.labelSmall?.copyWith(
                    color: context.mutedText,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'المساعد الصوتي والاستخدام'),
          AsyncContent<VoiceStatus>(
            value: ref.watch(voiceStatusProvider),
            onRetry: () => ref.invalidate(voiceStatusProvider),
            builder: (status) => _VoiceUsageCard(status: status),
          ),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'المزامنة'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _SyncMetric(
                        label: 'بانتظار الرفع',
                        value: '${sync.pending}',
                      ),
                    ),
                    Expanded(
                      child: _SyncMetric(
                        label: 'تعارضات',
                        value: '${sync.conflicts}',
                        alert: sync.conflicts > 0,
                      ),
                    ),
                    Expanded(
                      child: _SyncMetric(
                        label: 'فشلت',
                        value: '${sync.failed}',
                        alert: sync.failed > 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  sync.lastSyncedAt == null
                      ? 'لسه مفيش مزامنة كاملة على الجهاز.'
                      : 'آخر مزامنة: ${AppFormat.dateTime(sync.lastSyncedAt)}',
                  style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                ),
                if (sync.lastError != null) ...[
                  const SizedBox(height: 10),
                  ShadAlert(
                    icon: const Icon(LucideIcons.triangleAlert, size: 16),
                    description: Text(sync.lastError!),
                  ),
                ],
                const SizedBox(height: 12),
                ShadButton.outline(
                  width: double.infinity,
                  onPressed: sync.syncing ? null : _syncNow,
                  leading: sync.syncing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.refreshCw, size: 15),
                  child: Text(sync.syncing ? 'بنزامن…' : 'زامن دلوقتي'),
                ),
              ],
            ),
          ),
          _ConflictsSection(onResolve: _resolveConflict),
          _FailedSection(onRetry: _retryFailed, onDiscard: _discardFailed),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'بياناتك'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نزّل نسخة من مواقعك وزياراتك ومهامك بصيغة مفتوحة. '
                  'الملفات بتتحفظ على الجهاز، ومش بتتبعت لأي حد تاني.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.mutedText,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: _exporting ? null : _exportJson,
                        leading: const Icon(LucideIcons.database, size: 15),
                        child: const Text('تصدير JSON'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: _exporting ? null : _pickCsvEntity,
                        leading: const Icon(LucideIcons.fileText, size: 15),
                        child: const Text('تصدير CSV'),
                      ),
                    ),
                  ],
                ),
                if (_exporting) ...[
                  const SizedBox(height: 10),
                  Text(
                    'بنجهّز الملف…',
                    style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Insets.gapLarge),

          const SectionTitle(title: 'الحساب'),
          ShadButton.outline(
            width: double.infinity,
            onPressed: _signOut,
            leading: Icon(LucideIcons.logOut, size: 16, color: context.scheme.destructive),
            child: Text(
              'تسجيل الخروج',
              style: TextStyle(color: context.scheme.destructive),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'مدير الشغل • نسخة 1.0.0',
            textAlign: TextAlign.center,
            style: context.texts.labelSmall?.copyWith(color: context.mutedText),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ account

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.workspaces, required this.offline});

  final AppUser user;
  final List<Workspace> workspaces;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final initial = user.name.trim().isEmpty ? '؟' : user.name.trim().characters.first;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: context.scheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: context.texts.titleMedium?.copyWith(
                      color: context.scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      textDirection: TextDirection.ltr,
                      style: context.texts.bodySmall?.copyWith(color: context.mutedText),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (offline)
                Tag(
                  label: 'بدون اتصال',
                  icon: LucideIcons.cloudOff,
                  color: context.scheme.muted,
                  foreground: context.mutedText,
                ),
            ],
          ),
          if (workspaces.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: context.hairline),
            const SizedBox(height: 12),
            for (final workspace in workspaces)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(LucideIcons.building2, size: 14, color: context.mutedText),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        workspace.name,
                        style: context.texts.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Tag(
                      label: _SettingsScreenState._roleLabel(workspace.role),
                      color: context.scheme.secondary,
                      foreground: context.scheme.secondaryForeground,
                      outline: false,
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------------- voice

class _VoiceUsageCard extends StatelessWidget {
  const _VoiceUsageCard({required this.status});

  final VoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final caps = status.capabilities;
    final usage = status.usage;
    final sessionsLimit = usage.limits.sessions;
    final minutesLimit = usage.limits.minutes;
    final sessionProgress = sessionsLimit <= 0
        ? 0.0
        : (usage.sessions / sessionsLimit).clamp(0.0, 1.0);
    final minuteProgress = minutesLimit <= 0
        ? 0.0
        : (usage.minutes / minutesLimit).clamp(0.0, 1.0);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Capability(label: 'جلسة مباشرة', available: caps.geminiLive),
              _Capability(
                label: 'تسجيل بطيء',
                available: caps.fallbackStt && caps.fallbackLlm,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _UsageBar(
            label: 'الجلسات',
            value: '${usage.sessions}${sessionsLimit > 0 ? ' / $sessionsLimit' : ''}',
            progress: sessionProgress,
          ),
          const SizedBox(height: 10),
          _UsageBar(
            label: 'الدقائق',
            value: '${usage.minutes.toStringAsFixed(1)}'
                '${minutesLimit > 0 ? ' / $minutesLimit' : ''}',
            progress: minuteProgress,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                caps.paidFallbackAllowed ? LucideIcons.triangleAlert : LucideIcons.circleCheck,
                size: 14,
                color: caps.paidFallbackAllowed
                    ? context.scheme.destructive
                    : context.scheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  caps.paidFallbackAllowed
                      ? 'الاستدعاء المدفوع مسموح على السيرفر. راجع الإعدادات قبل الاستخدام.'
                      : 'مفيش استدعاءات مدفوعة: الميزانية \$${caps.budgetUsd.toStringAsFixed(0)} '
                            'والبدائل المجانية بس هي المتاحة.',
                  style: context.texts.labelSmall?.copyWith(
                    color: caps.paidFallbackAllowed
                        ? context.scheme.destructive
                        : context.mutedText,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          if (usage.warning != null) ...[
            const SizedBox(height: 12),
            ShadAlert(
              icon: const Icon(LucideIcons.triangleAlert, size: 16),
              description: Text(usage.warning!),
            ),
          ],
          if (!caps.transcriptRetentionEnabled) ...[
            const SizedBox(height: 10),
            Text(
              'السيرفر مش محتفظ بنصوص المحادثات دلوقتي.',
              style: context.texts.labelSmall?.copyWith(color: context.mutedText),
            ),
          ],
        ],
      ),
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.available});

  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    return Tag(
      label: available ? '$label متاح' : '$label مش متاح',
      icon: available ? LucideIcons.circleCheck : LucideIcons.circleDot,
      color: available ? null : context.scheme.muted,
      foreground: available ? context.scheme.primary : context.mutedText,
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.value, required this.progress});

  final String label;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.texts.labelSmall?.copyWith(color: context.mutedText),
              ),
            ),
            Text(
              value,
              style: context.texts.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ShadProgress(value: progress, minHeight: 6),
      ],
    );
  }
}

// ------------------------------------------------------------------ sync

class _SyncMetric extends StatelessWidget {
  const _SyncMetric({required this.label, required this.value, this.alert = false});

  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.texts.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: alert ? context.scheme.destructive : null,
          ),
        ),
        Text(
          label,
          style: context.texts.labelSmall?.copyWith(color: context.mutedText),
        ),
      ],
    );
  }
}

class _ConflictsSection extends ConsumerWidget {
  const _ConflictsSection({required this.onResolve});

  final Future<void> Function(OutboxItem item, {required bool keepLocal}) onResolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(syncConflictProvider);

    return conflicts.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.triangleAlert, size: 16, color: context.scheme.destructive),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${items.length} تغيير محتاج مراجعة',
                        style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'حد تاني عدّل نفس السجل على السيرفر. اختار تحتفظ بنسختك ولا بنسخة السيرفر.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.mutedText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) Divider(height: 20, color: context.hairline),
                  _ConflictRow(
                    item: items[index],
                    onKeepLocal: () => onResolve(items[index], keepLocal: true),
                    onKeepServer: () => onResolve(items[index], keepLocal: false),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FailedSection extends ConsumerWidget {
  const _FailedSection({required this.onRetry, required this.onDiscard});

  final Future<void> Function(OutboxItem item) onRetry;
  final Future<void> Function(OutboxItem item) onDiscard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(syncFailedProvider);

    return failed.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.circleAlert, size: 16, color: context.scheme.destructive),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${items.length} تغيير فشل في الرفع',
                        style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'السيرفر رفض التغييرات دي، فمش هتتزامن لوحدها. '
                  'جرّب ترفعها تاني بعد ما تصلّح السبب، أو امسحها وسجّلها من جديد.',
                  style: context.texts.bodySmall?.copyWith(
                    color: context.mutedText,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) Divider(height: 20, color: context.hairline),
                  _FailedRow(
                    item: items[index],
                    onRetry: () => onRetry(items[index]),
                    onDiscard: () => onDiscard(items[index]),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({required this.item, required this.onRetry, required this.onDiscard});

  final OutboxItem item;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.labelAr,
          style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'من ${AppFormat.relativeTime(item.createdAt)}'
          '${item.attempts > 1 ? ' • حاولنا ${item.attempts} مرات' : ''}',
          style: context.texts.labelSmall?.copyWith(color: context.mutedText),
        ),
        if (item.lastError != null) ...[
          const SizedBox(height: 4),
          Text(
            item.lastError!,
            style: context.texts.labelSmall?.copyWith(color: context.scheme.destructive),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onRetry,
                child: const Text('جرّب تاني'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onDiscard,
                child: const Text('امسح'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.item,
    required this.onKeepLocal,
    required this.onKeepServer,
  });

  final OutboxItem item;
  final VoidCallback onKeepLocal;
  final VoidCallback onKeepServer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.labelAr,
          style: context.texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'من ${AppFormat.relativeTime(item.createdAt)}',
          style: context.texts.labelSmall?.copyWith(color: context.mutedText),
        ),
        if (item.lastError != null) ...[
          const SizedBox(height: 4),
          Text(
            item.lastError!,
            style: context.texts.labelSmall?.copyWith(color: context.scheme.destructive),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                size: ShadButtonSize.sm,
                onPressed: onKeepLocal,
                child: const Text('خلّي نسختي'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ShadButton.ghost(
                size: ShadButtonSize.sm,
                onPressed: onKeepServer,
                child: const Text('نسخة السيرفر'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ pieces

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

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
