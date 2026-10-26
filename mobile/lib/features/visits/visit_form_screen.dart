import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/formatting.dart';
import '../../models/visit.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/ui.dart';

/// Visit editor.
///
/// Visits are append-only history: this screen edits one existing record and
/// the server stamps `revision`/`editedAt` so the change is visible later.
class VisitFormScreen extends ConsumerStatefulWidget {
  const VisitFormScreen({
    super.key,
    required this.siteId,
    this.visitId,
    this.initialVisit,
  });

  final String siteId;
  final String? visitId;
  final Visit? initialVisit;

  @override
  ConsumerState<VisitFormScreen> createState() => _VisitFormScreenState();
}

class _VisitFormScreenState extends ConsumerState<VisitFormScreen> {
  final _completed = TextEditingController();
  final _remaining = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date = DateTime.now();
  bool _loaded = false;
  bool _busy = false;
  bool _showTranscript = false;
  String? _error;
  Visit? _visit;

  bool get _isEditing => widget.visitId != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialVisit;
    if (initial != null && (widget.visitId == null || initial.id == widget.visitId)) {
      _populate(initial);
    }
  }

  @override
  void dispose() {
    _completed.dispose();
    _remaining.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _populate(Visit visit) {
    _visit = visit;
    _completed.text = visit.completedWork;
    _remaining.text = visit.remainingWork ?? '';
    _notes.text = visit.notes ?? '';
    _date = AppFormat.parseDateOnly(visit.visitDate) ?? DateTime.now();
    _loaded = true;
  }

  Future<void> _pickDate() async {
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

  Future<void> _save() async {
    if (_busy) return;

    // Editing an unloaded visit must not create a new visit (visits are
    // append-only, so a duplicate is permanent history noise).
    if (_isEditing && _visit == null) {
      setState(() => _error = 'لسه بنحمّل بيانات الزيارة. استنى لحظة وجرّب تاني.');
      return;
    }

    final site = ref.read(siteDetailProvider(widget.siteId)).value?.site;
    if (!_isEditing && site != null && site.pending) {
      setState(() => _error = 'الموقع لسه بانتظار المزامنة. استنى يترفع الأول وبعدين سجّل الزيارة.');
      return;
    }

    final completed = _completed.text.trim();
    if (completed.isEmpty) {
      setState(() => _error = 'اكتب أهم حاجة اتعملت في الزيارة.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final mutations = ref.read(mutationsProvider);
      if (!_isEditing) {
        await mutations.createVisit(
          siteId: widget.siteId,
          visitDate: AppFormat.isoDate(_date),
          completedWork: completed,
          remainingWork: _remaining.text,
          notes: _notes.text,
        );
      } else {
        await mutations.updateVisit(
          _visit!,
          visitDate: AppFormat.isoDate(_date),
          completedWork: completed,
          remainingWork: _remaining.text,
          notes: _notes.text,
        );
      }

      ref.invalidate(visitHistoryProvider(widget.siteId));
      ref.invalidate(siteDetailProvider(widget.siteId));
      ref.invalidate(overviewProvider);
      ref.invalidate(sitesProvider);
      unawaited(mutations.flushQuietly());

      if (!mounted) return;
      showToast(
        context,
        title: _isEditing ? 'الزيارة اتعدّلت' : 'الزيارة اتسجّلت',
        description: _isEditing ? 'التعديل مسجّل مع تاريخ الزيارة.' : null,
      );
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
      final detail = ref.watch(siteDetailProvider(widget.siteId)).value;
      Visit? match;
      for (final visit in detail?.visits ?? const <Visit>[]) {
        if (visit.id == widget.visitId) {
          match = visit;
          break;
        }
      }
      if (match != null) {
        final found = match;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loaded) setState(() => _populate(found));
        });
      }
    }

    final siteName = ref.watch(siteDetailProvider(widget.siteId)).value?.site.name;
    final transcript = _visit?.transcript;
    final keepTranscripts = ref.watch(settingsProvider).value?.keepTranscripts ?? true;

    return ScreenScaffold(
      title: _isEditing ? 'تعديل زيارة' : 'زيارة جديدة',
      subtitle: siteName,
      leading: ShadIconButton.ghost(
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        onPressed: () => context.pop(),
      ),
      bottomBar: FormActions(
        label: _isEditing ? 'حفظ التعديل' : 'سجّل الزيارة',
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
          if (_isEditing) ...[
            ShadAlert(
              icon: const Icon(LucideIcons.info, size: 16),
              description: const Text(
                'الزيارات سجل تاريخي. التعديل ده هيتسجل كمراجعة على نفس الزيارة، مش زيارة جديدة.',
              ),
            ),
            const SizedBox(height: 14),
          ],
          LabeledField(
            label: 'تاريخ الزيارة',
            child: Row(
              children: [
                Expanded(
                  child: ShadButton.outline(
                    size: ShadButtonSize.lg,
                    onPressed: _pickDate,
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
          const SizedBox(height: 16),
          LabeledField(
            label: 'الشغل اللي خلص',
            child: ShadTextarea(
              controller: _completed,
              placeholder: const Text('مثال: ركّبنا لوحة الكهرباء الرئيسية واختبرنا الأحمال.'),
              minHeight: 140,
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'الشغل الباقي',
            optional: true,
            helper: 'لقطة وقت الزيارة. قائمة المهام هي الحالة الحالية.',
            child: ShadTextarea(
              controller: _remaining,
              placeholder: const Text('مثال: باقي توصيل الكابلات للدور التاني.'),
              minHeight: 90,
            ),
          ),
          const SizedBox(height: 16),
          LabeledField(
            label: 'ملاحظات',
            optional: true,
            child: ShadTextarea(
              controller: _notes,
              placeholder: const Text('أي حاجة تانية: مشاكل، ملاحظات من العميل…'),
              minHeight: 90,
            ),
          ),
          if (transcript != null && transcript.trim().isNotEmpty && keepTranscripts) ...[
            const SizedBox(height: 16),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: () => setState(() => _showTranscript = !_showTranscript),
              leading: Icon(
                _showTranscript ? LucideIcons.chevronDown : LucideIcons.chevronLeft,
                size: 14,
              ),
              child: const Text('نص المحادثة الصوتية'),
            ),
            if (_showTranscript)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SurfaceCard(
                  child: Text(
                    transcript,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.mutedText,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
