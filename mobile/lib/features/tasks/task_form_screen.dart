import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../models/site.dart';
import '../../models/task.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/ui.dart';

class TaskFormScreen extends ConsumerStatefulWidget {
  const TaskFormScreen({super.key, this.taskId, this.siteId, this.initialTask});

  final String? taskId;
  final String? siteId;
  final Task? initialTask;

  @override
  ConsumerState<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends ConsumerState<TaskFormScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  String _siteId = '';
  TaskPriority _priority = TaskPriority.normal;
  TaskStatus _status = TaskStatus.open;
  DateTime? _dueDate;
  bool _loaded = false;
  bool _busy = false;
  String? _error;
  Task? _task;

  bool get _isEditing => widget.taskId != null;

  @override
  void initState() {
    super.initState();
    _siteId = widget.siteId ?? '';
    final initial = widget.initialTask;
    if (initial != null && (widget.taskId == null || initial.id == widget.taskId)) {
      _populate(initial);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _populate(Task task) {
    _task = task;
    _title.text = task.title;
    _description.text = task.description ?? '';
    _siteId = task.siteId ?? '';
    _priority = task.priority;
    _status = task.status;
    _dueDate = AppFormat.parseDateOnly(task.dueDate);
    _loaded = true;
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      helpText: 'تاريخ الاستحقاق',
      cancelText: 'إلغاء',
      confirmText: 'تمام',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    if (_busy) return;

    // Editing an unloaded task must not create a new one.
    if (_isEditing && _task == null) {
      setState(() => _error = 'لسه بنحمّل بيانات المهمة. استنى لحظة وجرّب تاني.');
      return;
    }

    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'عنوان المهمة مطلوب.');
      return;
    }

    final sites = ref.read(allSitesProvider).value ?? const <Site>[];
    final selectedSite = _siteId.isEmpty
        ? null
        : sites.where((site) => site.id == _siteId).firstOrNull;
    if (_siteId.isNotEmpty && selectedSite != null && selectedSite.pending) {
      setState(() => _error = 'الموقع لسه بانتظار المزامنة. استنى يترفع الأول وبعدين ضيف المهمة.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final mutations = ref.read(mutationsProvider);
      final siteId = _siteId.isEmpty ? null : _siteId;
      final due = _dueDate == null ? null : AppFormat.isoDate(_dueDate!);

      if (!_isEditing) {
        await mutations.createTask(
          siteId: siteId,
          title: title,
          description: _description.text,
          priority: _priority,
          dueDate: due,
        );
      } else {
        await mutations.updateTask(
          _task!,
          title: title,
          description: _description.text,
          priority: _priority,
          status: _status,
          dueDate: due,
          clearDueDate: due == null && _task!.dueDate != null,
        );
      }

      ref.invalidate(tasksProvider);
      ref.invalidate(overviewProvider);
      if (siteId != null) ref.invalidate(siteDetailProvider(siteId));
      unawaited(mutations.flushQuietly());

      if (!mounted) return;
      showToast(context, title: _isEditing ? 'المهمة اتحدّثت' : 'المهمة اتضافت');
      context.pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final task = _task;
    if (task == null) return;
    final confirmed = await showConfirm(
      context,
      title: 'تحذف المهمة؟',
      description: 'المهمة هتتشال من القائمة نهائي. الزيارات مش هتتأثر.',
      confirmLabel: 'احذف',
      destructive: true,
    );
    if (!confirmed) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mutationsProvider).deleteTask(task);
      ref.invalidate(tasksProvider);
      ref.invalidate(overviewProvider);
      if (task.siteId != null) ref.invalidate(siteDetailProvider(task.siteId!));
      if (!mounted) return;
      showToast(context, title: 'المهمة اتحذفت');
      context.pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing && !_loaded) {
      final task = ref
          .watch(tasksProvider)
          .value
          ?.where((candidate) => candidate.id == widget.taskId)
          .firstOrNull;
      if (task != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loaded) setState(() => _populate(task));
        });
      }
    }

    // Pending sites have no server id yet, so a task cannot reference them.
    final sites = (ref.watch(allSitesProvider).value ?? const <Site>[])
        .where((site) => !site.pending)
        .toList(growable: false);
    final selectedSiteId = sites.any((site) => site.id == _siteId) ? _siteId : '';

    return ScreenScaffold(
      title: _isEditing ? 'تعديل مهمة' : 'مهمة جديدة',
      subtitle: _isEditing ? _task?.siteName : 'مهمة بتتابعها لحد ما تخلص.',
      leading: ShadIconButton.ghost(
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        onPressed: () => context.pop(),
      ),
      bottomBar: FormActions(
        label: _isEditing ? 'حفظ التعديلات' : 'إضافة المهمة',
        busy: _busy,
        onPressed: _save,
      ),
      child: ListView(
        padding: Insets.page,
        children: [
          if (_error != null) ...[
            ShadAlert.destructive(
              icon: const Icon(LucideIcons.circleAlert, size: 16),
              description: Text(_error!),
            ),
            const SizedBox(height: 14),
          ],
          LabeledField(
            label: 'عنوان المهمة',
            child: ShadInput(
              controller: _title,
              placeholder: const Text('مثال: توريد لوحة الكهرباء'),
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'التفاصيل',
            optional: true,
            child: ShadTextarea(
              controller: _description,
              placeholder: const Text('خطوات، مقاسات، أو أي تفاصيل محتاجة.'),
              minHeight: 90,
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'الموقع',
            optional: true,
            helper: sites.isEmpty ? 'مفيش مواقع متاحة دلوقتي. تقدر تضيف المهمة من غير موقع.' : null,
            child: ShadSelect<String>(
              initialValue: selectedSiteId,
              placeholder: const Text('بدون موقع'),
              selectedOptionBuilder: (context, value) {
                if (value.isEmpty) return const Text('بدون موقع');
                final match = sites.where((site) => site.id == value).firstOrNull;
                return Text(match?.name ?? 'موقع');
              },
              options: [
                const ShadOption(value: '', child: Text('بدون موقع')),
                for (final site in sites)
                  ShadOption(
                    value: site.id,
                    child: Text(
                      site.scope == SiteScope.company
                          ? '${site.name} • ${site.workspaceName ?? 'شركة'}'
                          : site.name,
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _siteId = value ?? ''),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'الأولوية',
                  child: ShadSelect<TaskPriority>(
                    initialValue: _priority,
                    placeholder: const Text('الأولوية'),
                    selectedOptionBuilder: (context, value) => Text(value.label),
                    options: [
                      for (final priority in TaskPriority.values)
                        ShadOption(value: priority, child: Text(priority.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _priority = value);
                    },
                  ),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    label: 'الحالة',
                    child: ShadSelect<TaskStatus>(
                      initialValue: _status,
                      placeholder: const Text('الحالة'),
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
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'تاريخ الاستحقاق',
            optional: true,
            child: Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    size: ShadButtonSize.lg,
                    onPressed: _pickDueDate,
                    leading: const Icon(LucideIcons.calendar, size: 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _dueDate == null
                            ? 'بدون تاريخ'
                            : AppFormat.fullDate(AppFormat.isoDate(_dueDate!)),
                      ),
                    ),
                  ),
                ),
                if (_dueDate != null) ...[
                  const SizedBox(width: 8),
                  ShadIconButton.ghost(
                    icon: const Icon(LucideIcons.x, size: 16),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
                ],
              ],
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 26),
            ShadButton.outline(
              onPressed: _busy ? null : _delete,
              foregroundColor: context.scheme.destructive,
              leading: const Icon(LucideIcons.trash2, size: 16),
              child: const Text('حذف المهمة'),
            ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
