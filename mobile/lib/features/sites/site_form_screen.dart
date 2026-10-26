import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/overview.dart';
import '../../models/site.dart';
import '../../state/data_providers.dart';
import '../../state/providers.dart';
import '../common/ui.dart';

/// Create or edit a site.
///
/// Personal sites are private to the signed-in user; company sites belong to a
/// workspace and are only writable by members with an editor role or above.
class SiteFormScreen extends ConsumerStatefulWidget {
  const SiteFormScreen({super.key, this.siteId, this.initialSite});

  final String? siteId;
  final Site? initialSite;

  @override
  ConsumerState<SiteFormScreen> createState() => _SiteFormScreenState();
}

class _SiteFormScreenState extends ConsumerState<SiteFormScreen> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();
  final _mapUrl = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _notes = TextEditingController();

  SiteScope _scope = SiteScope.personal;
  String? _workspaceId;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  bool get _isEditing => widget.siteId != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSite;
    if (initial != null && (widget.siteId == null || initial.id == widget.siteId)) {
      _populate(initial);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    _mapUrl.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _populate(Site site) {
    _name.text = site.name;
    _address.text = site.address;
    _contactName.text = site.contactName ?? '';
    _contactPhone.text = site.contactPhone ?? '';
    _mapUrl.text = site.mapUrl ?? '';
    _latitude.text = site.latitude?.toString() ?? '';
    _longitude.text = site.longitude?.toString() ?? '';
    _notes.text = site.generalNotes ?? '';
    _scope = site.scope;
    _workspaceId = site.workspaceId;
    _loaded = true;
  }

  Future<void> _save(Site? existing) async {
    if (_busy) return;

    // Editing must never fall through to "create". If the record has not loaded
    // yet (deep link, slow network, cold cache) the safe action is to wait
    // instead of inserting a duplicate site.
    if (_isEditing && existing == null) {
      setState(() => _error = 'لسه بنحمّل بيانات الموقع. استنى لحظة وجرّب تاني.');
      return;
    }

    final name = _name.text.trim();
    final address = _address.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الموقع مطلوب.');
      return;
    }
    if (address.isEmpty) {
      setState(() => _error = 'العنوان أو المنطقة مطلوب.');
      return;
    }

    final latText = _latitude.text.trim();
    final lngText = _longitude.text.trim();
    double? latitude;
    double? longitude;
    if (latText.isNotEmpty || lngText.isNotEmpty) {
      latitude = double.tryParse(latText);
      longitude = double.tryParse(lngText);
      if (latitude == null || longitude == null) {
        setState(() => _error = 'الإحداثيات لازم تكون أرقام، والاتنين مع بعض.');
        return;
      }
      if (latitude.abs() > 90 || longitude.abs() > 180) {
        setState(() => _error = 'الإحداثيات خارج النطاق الصحيح.');
        return;
      }
    }

    final mapUrl = _mapUrl.text.trim();
    if (mapUrl.isNotEmpty && !(mapUrl.startsWith('http://') || mapUrl.startsWith('https://'))) {
      setState(() => _error = 'لينك الخريطة لازم يبدأ بـ http أو https.');
      return;
    }

    if (!_isEditing && _scope == SiteScope.company && _workspaceId == null) {
      setState(() => _error = 'اختار الشركة اللي الموقع تابع لها.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final mutations = ref.read(mutationsProvider);
      if (!_isEditing) {
        await mutations.createSite(
          name: name,
          scope: _scope,
          workspaceId: _scope == SiteScope.company ? _workspaceId : null,
          address: address,
          contactName: _contactName.text,
          contactPhone: _contactPhone.text,
          mapUrl: mapUrl,
          latitude: latitude,
          longitude: longitude,
          generalNotes: _notes.text,
        );
      } else {
        await mutations.updateSite(
          existing!,
          name: name,
          address: address,
          contactName: _contactName.text,
          contactPhone: _contactPhone.text,
          mapUrl: mapUrl,
          generalNotes: _notes.text,
        );
      }

      ref.invalidate(sitesProvider);
      ref.invalidate(overviewProvider);
      if (widget.siteId != null) ref.invalidate(siteDetailProvider(widget.siteId!));
      unawaited(mutations.flushQuietly());

      if (!mounted) return;
      showToast(
        context,
        title: _isEditing ? 'الموقع اتحدّث' : 'الموقع اتضاف',
        description: _isEditing ? null : 'تقدر تضيف زيارة أو مهمة من صفحة الموقع.',
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
    final workspaces = ref.watch(authProvider).value?.workspaces ?? const [];
    SiteDetail? detail;
    if (_isEditing && !_loaded) {
      detail = ref.watch(siteDetailProvider(widget.siteId!)).value;
      if (detail != null) {
        final site = detail.site;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loaded) {
            setState(() => _populate(site));
          }
        });
      }
    }

    final initial = widget.initialSite;
    final existing = initial != null && (!_isEditing || initial.id == widget.siteId)
        ? initial
        : detail?.site;

    return ScreenScaffold(
      title: _isEditing ? 'تعديل الموقع' : 'موقع جديد',
      subtitle: _isEditing ? existing?.name : 'بيانات الموقع الأساسية والملاحظات.',
      leading: ShadIconButton.ghost(
        icon: const Icon(LucideIcons.arrowRight, size: 18),
        onPressed: () => context.pop(),
      ),
      bottomBar: FormActions(
        label: _isEditing ? 'حفظ التعديلات' : 'إضافة الموقع',
        busy: _busy,
        onPressed: () => _save(existing),
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
            label: 'اسم الموقع',
            child: ShadInput(
              controller: _name,
              placeholder: const Text('مثال: برج النيل – الدور 7'),
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'العنوان أو المنطقة',
            child: ShadInput(
              controller: _address,
              placeholder: const Text('المعادي، القاهرة'),
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(height: 14),
          if (!_isEditing) ...[
            LabeledField(
              label: 'نوع الموقع',
              helper: _scope == SiteScope.company
                  ? 'هيتشاف لكل أعضاء الشركة اللي ليهم صلاحية.'
                  : 'موقع خاص بيك، محدش تاني بيشوفه.',
              child: Row(
                children: [
                  Expanded(
                    child: _ScopeOption(
                      label: 'شغلي',
                      icon: LucideIcons.userRound,
                      selected: _scope == SiteScope.personal,
                      onTap: () => setState(() => _scope = SiteScope.personal),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ScopeOption(
                      label: 'مواقع الشركة',
                      icon: LucideIcons.building2,
                      selected: _scope == SiteScope.company,
                      enabled: workspaces.isNotEmpty,
                      onTap: workspaces.isEmpty
                          ? null
                          : () => setState(() {
                              _scope = SiteScope.company;
                              _workspaceId ??= workspaces.first.id;
                            }),
                    ),
                  ),
                ],
              ),
            ),
            if (_scope == SiteScope.company && workspaces.length > 1) ...[
              const SizedBox(height: 14),
              LabeledField(
                label: 'الشركة',
                child: ShadSelect<String>(
                  initialValue: _workspaceId ?? workspaces.first.id,
                  placeholder: const Text('اختار الشركة'),
                  selectedOptionBuilder: (context, value) => Text(
                    workspaces.firstWhere((w) => w.id == value).name,
                  ),
                  options: [
                    for (final workspace in workspaces)
                      ShadOption(value: workspace.id, child: Text(workspace.name)),
                  ],
                  onChanged: (value) => setState(() => _workspaceId = value),
                ),
              ),
            ],
            if (_scope == SiteScope.company && workspaces.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'مش عضو في أي شركة لسه، فتقدر تضيف مواقع خاصة بس.',
                style: context.texts.bodySmall?.copyWith(color: context.mutedText),
              ),
            ],
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'اسم جهة الاتصال',
                  optional: true,
                  child: ShadInput(
                    controller: _contactName,
                    placeholder: const Text('م. أحمد'),
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LabeledField(
                  label: 'التليفون',
                  optional: true,
                  child: ShadInput(
                    controller: _contactPhone,
                    placeholder: const Text('01xxxxxxxxx'),
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'لينك الخريطة',
            optional: true,
            helper: 'لو معاك لينك Google Maps، الصقه هنا.',
            child: ShadInput(
              controller: _mapUrl,
              placeholder: const Text('https://maps.google.com/…'),
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: 'خط العرض',
                  optional: true,
                  child: ShadInput(
                    controller: _latitude,
                    placeholder: const Text('30.0444'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LabeledField(
                  label: 'خط الطول',
                  optional: true,
                  child: ShadInput(
                    controller: _longitude,
                    placeholder: const Text('31.2357'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: 'ملاحظات عامة',
            optional: true,
            helper: 'أي تفاصيل ثابتة عن الموقع: دور، بوابة، توقيت الوصول…',
            child: ShadTextarea(
              controller: _notes,
              placeholder: const Text('مثال: الدخول من البوابة الشمالية، اسأل على الأمن.'),
              minHeight: 112,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _ScopeOption extends StatelessWidget {
  const _ScopeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final foreground = !enabled
        ? context.mutedText.withValues(alpha: 0.5)
        : selected
        ? context.scheme.primary
        : context.scheme.foreground;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? context.scheme.primary.withValues(alpha: 0.12)
                : context.scheme.muted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? context.scheme.primary : context.hairline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: context.texts.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(LucideIcons.check, size: 15, color: context.scheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
