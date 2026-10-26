import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../models/site.dart';
import '../../models/task.dart';
import '../../models/voice.dart';
import '../../state/data_providers.dart';
import '../../state/voice_controller.dart';
import '../common/ui.dart';

/// Editable review of an assistant draft.
///
/// Nothing is written until the user presses the confirm button. Cancelling
/// leaves the manual forms untouched.
class DraftReview extends ConsumerStatefulWidget {
  const DraftReview({super.key, required this.draft});

  final AssistantDraft draft;

  @override
  ConsumerState<DraftReview> createState() => _DraftReviewState();
}

class _DraftReviewState extends ConsumerState<DraftReview> {
  static const String _noSite = '__none__';

  final _completed = TextEditingController();
  final _remaining = TextEditingController();
  final _notes = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();

  String? _siteId;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  TaskPriority _priority = TaskPriority.normal;
  TaskStatus? _status;
  bool _busy = false;
  String? _error;

  AssistantDraft get _draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _siteId = _draft.siteId;
    _date = AppFormat.parseDateOnly(_draft.visitDate) ?? DateTime.now();
    _dueDate = AppFormat.parseDateOnly(_draft.dueDate);
    _priority = TaskPriority.fromWire(_draft.priority);
    _status = _draft.proposedStatus == null ? null : TaskStatus.fromWire(_draft.proposedStatus);
    _completed.text = _draft.completedWork ?? '';
    _remaining.text = _draft.remainingWork ?? '';
    _notes.text = _draft.notes ?? '';
    _title.text = _draft.title ?? '';
    _description.text = _draft.description ?? '';
  }

  @override
  void dispose() {
    _completed.dispose();
    _remaining.dispose();
    _notes.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickVisitDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'تاريخ الزيارة',
      cancelText: 'إلغاء',
      confirmText: 'تمام',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: 'تاريخ الاستحقاق',
      cancelText: 'إلغاء',
      confirmText: 'تمام',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  AssistantDraft _editedDraft() {
    final isTask = _draft.isTask || _draft.isTaskUpdate;
    final siteId = _siteId == _noSite || (_siteId?.isEmpty ?? true) ? null : _siteId;

    return AssistantDraft(
      kind: _draft.kind,
      operationId: _draft.operationId,
      siteId: siteId,
      siteName: _draft.siteName,
      visitDate: _draft.isVisit ? AppFormat.isoDate(_date) : null,
      completedWork: _draft.isVisit ? _completed.text.trim() : null,
      remainingWork: _draft.isVisit && _remaining.text.trim().isNotEmpty
          ? _remaining.text.trim()
          : null,
      notes: _draft.isVisit && _notes.text.trim().isNotEmpty ? _notes.text.trim() : null,
      title: isTask && _title.text.trim().isNotEmpty ? _title.text.trim() : null,
      description: isTask && _description.text.trim().isNotEmpty
          ? _description.text.trim()
          : null,
      priority: isTask ? _priority.wire : null,
      dueDate: isTask ? (_dueDate == null ? null : AppFormat.isoDate(_dueDate!)) : null,
      taskId: _draft.taskId,
      proposedStatus: _draft.isTaskUpdate ? _status?.wire : null,
      baseUpdatedAt: _draft.baseUpdatedAt,
      warning: _draft.warning,
      before: _draft.before,
    );
  }

  Future<void> _confirm() async {
    if (_busy) return;

    final siteId = _siteId == _noSite ? null : _siteId;
    if (_draft.isVisit) {
      if (siteId == null || siteId.isEmpty) {
        setState(() => _error = 'اختار الموقع اللي الزيارة تتبعه.');
        return;
      }
      if (_completed.text.trim().isEmpty) {
        setState(() => _error = 'اكتب أهم حاجة اتعملت في الزيارة.');
        return;
      }
    }
    if (_draft.isTask && _title.text.trim().isEmpty) {
      setState(() => _error = 'اكتب عنوان للمهمة.');
      return;
    }
    if (_draft.isTaskUpdate && _status == null) {
      setState(() => _error = 'اختار الحالة الجديدة للمهمة.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final saved = await ref
        .read(voiceControllerProvider.notifier)
        .confirmDraft(edited: _editedDraft());

    if (!mounted) return;
    if (saved) {
      showToast(
        context,
        title: 'تم الحفظ',
        description: 'التغيير اتحفظ، ولو الشبكة مقطوعة هيتزامن لوحده.',
      );
    } else {
      setState(() {
        _busy = false;
        _error = ref.read(voiceControllerProvider).error ?? 'مقدرناش نحفظ المسودة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(allSitesProvider);
    final kindLabel = switch (_draft.kind) {
      'visit' => 'زيارة',
      'task' => 'مهمة جديدة',
      'taskUpdate' => 'تعديل مهمة',
      _ => 'تغيير',
    };

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: context.scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.sparkles, size: 15, color: context.scheme.primary),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مسودة $kindLabel',
                      style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'راجعها قبل الحفظ — مفيش حاجة اتسجلت لسه.',
                      style: context.texts.labelSmall?.copyWith(color: context.mutedText),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_draft.warning != null) ...[
            const SizedBox(height: 12),
            ShadAlert(
              icon: const Icon(LucideIcons.triangleAlert, size: 16),
              description: Text(_draft.warning!),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            ShadAlert.destructive(
              icon: const Icon(LucideIcons.circleAlert, size: 16),
              description: Text(_error!),
            ),
          ],
          const SizedBox(height: 16),
          if (_draft.isTaskUpdate) _TaskContext(draft: _draft),
          if (_draft.isVisit || _draft.isTask) ...[
            LabeledField(
              label: 'الموقع',
              optional: _draft.isTask,
              child: _SitePicker(
                sites: sites,
                value: _siteId,
                noSiteValue: _noSite,
                includeNone: _draft.isTask,
                fallbackName: _draft.siteName,
                onChanged: (value) => setState(() => _siteId = value),
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_draft.isVisit) ...[
            LabeledField(
              label: 'تاريخ الزيارة',
              child: Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      size: ShadButtonSize.lg,
                      onPressed: _pickVisitDate,
                      leading: const Icon(LucideIcons.calendar, size: 16),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(AppFormat.fullDate(AppFormat.isoDate(_date))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadButton.ghost(
                    size: ShadButtonSize.lg,
                    onPressed: () => setState(() => _date = DateTime.now()),
                    child: const Text('النهارده'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'الشغل اللي خلص',
              child: ShadTextarea(
                controller: _completed,
                placeholder: const Text('اكتب اللي اتعمل فعلاً في الزيارة.'),
                minHeight: 112,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'الشغل الباقي',
              optional: true,
              helper: 'لقطة وقت الزيارة، مش بديل عن قائمة المهام.',
              child: ShadTextarea(
                controller: _remaining,
                placeholder: const Text('اللي لسه محتاج يتعمل.'),
                minHeight: 64,
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'ملاحظات',
              optional: true,
              child: ShadTextarea(
                controller: _notes,
                placeholder: const Text('أي تفاصيل إضافية.'),
                minHeight: 64,
              ),
            ),
          ],
          if (_draft.isTask || _draft.isTaskUpdate) ...[
            LabeledField(
              label: 'عنوان المهمة',
              child: ShadInput(
                controller: _title,
                placeholder: const Text('مثال: معايرة مضخات الحريق'),
              ),
            ),
            const SizedBox(height: 14),
            LabeledField(
              label: 'التفاصيل',
              optional: true,
              child: ShadTextarea(
                controller: _description,
                placeholder: const Text('أي تفاصيل تساعد في التنفيذ.'),
                minHeight: 64,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'الأولوية',
                    child: ShadSelect<TaskPriority>(
                      initialValue: _priority,
                      selectedOptionBuilder: (context, value) => Text(value.label),
                      options: [
                        for (final priority in TaskPriority.values)
                          ShadOption(
                            value: priority,
                            child: Text(priority.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _priority = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    label: 'الاستحقاق',
                    optional: true,
                    child: ShadButton.outline(
                      onPressed: _pickDueDate,
                      leading: const Icon(LucideIcons.calendar, size: 15),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _dueDate == null ? 'بدون تاريخ' : AppFormat.shortDate(AppFormat.isoDate(_dueDate!)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_dueDate != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ShadButton.ghost(
                  size: ShadButtonSize.sm,
                  onPressed: () => setState(() => _dueDate = null),
                  child: const Text('شيل تاريخ الاستحقاق'),
                ),
              ),
            ],
            if (_draft.isTaskUpdate) ...[
              const SizedBox(height: 14),
              LabeledField(
                label: 'الحالة الجديدة',
                child: ShadSelect<TaskStatus>(
                  initialValue: _status ?? TaskStatus.inProgress,
                  selectedOptionBuilder: (context, value) => Text(value.label),
                  options: [
                    for (final status in TaskStatus.values)
                      ShadOption(value: status, child: Text(status.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ShadButton(
                  size: ShadButtonSize.lg,
                  onPressed: _busy ? null : _confirm,
                  leading: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.check, size: 17),
                  child: const Text('أكّد واحفظ'),
                ),
              ),
              const SizedBox(width: 10),
              ShadButton.outline(
                size: ShadButtonSize.lg,
                onPressed: _busy
                    ? null
                    : () => ref.read(voiceControllerProvider.notifier).dismissDraft(),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskContext extends StatelessWidget {
  const _TaskContext({required this.draft});

  final AssistantDraft draft;

  @override
  Widget build(BuildContext context) {
    final before = draft.before ?? const <String, dynamic>{};
    final title = before['title']?.toString() ?? draft.title ?? 'مهمة';
    final status = before['status']?.toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ShadAlert(
        icon: const Icon(LucideIcons.info, size: 16),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        description: Text(
          status == null
              ? 'هيتعمل تعديل على المهمة دي.'
              : 'الحالة الحالية: ${TaskStatus.fromWire(status).label}.',
        ),
      ),
    );
  }
}

class _SitePicker extends StatelessWidget {
  const _SitePicker({
    required this.sites,
    required this.value,
    required this.noSiteValue,
    required this.includeNone,
    required this.onChanged,
    this.fallbackName,
  });

  final AsyncValue<List<Site>> sites;
  final String? value;
  final String noSiteValue;
  final bool includeNone;
  final String? fallbackName;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final list = sites.value ?? const <Site>[];
    final known = list.any((site) => site.id == value);

    return sites.when(
      data: (all) {
        if (all.isEmpty && value == null) {
          return ShadAlert(
            icon: const Icon(LucideIcons.mapPin, size: 16),
            description: const Text(
              'مفيش مواقع متاحة. ضيف موقع الأول من تاب المواقع، وبعدين سجّل الزيارة.',
            ),
          );
        }
        return ShadSelect<String>(
          initialValue: value,
          placeholder: const Text('اختار الموقع'),
          selectedOptionBuilder: (context, selected) {
            if (selected == noSiteValue) return const Text('بدون موقع');
            Site? match;
            for (final site in all) {
              if (site.id == selected) {
                match = site;
                break;
              }
            }
            return Text(
              match?.name ?? fallbackName ?? 'الموقع المحدد',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
          options: [
            if (includeNone)
              ShadOption<String>(
                value: noSiteValue,
                child: const Text('بدون موقع'),
              ),
            if (value != null && !known && value != noSiteValue)
              ShadOption<String>(
                value: value!,
                child: Text(fallbackName ?? 'الموقع المحدد'),
              ),
            for (final site in all)
              ShadOption<String>(
                value: site.id,
                child: Text(
                  site.scope == SiteScope.company && site.workspaceName != null
                      ? '${site.name} • ${site.workspaceName}'
                      : site.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        );
      },
      loading: () => const LoadingState(),
      error: (error, _) => ErrorState(message: describeError(error)),
    );
  }
}
