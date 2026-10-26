import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/voice.dart';
import '../../state/voice_controller.dart';
import '../common/ui.dart';
import 'draft_review.dart';

/// Voice assistant.
///
/// The assistant never writes on its own: every proposed visit/task change is
/// shown as an editable draft and only saved after an explicit confirmation.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(voiceControllerProvider).statusInfo == null) {
        unawaited(ref.read(voiceControllerProvider.notifier).loadStatus());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Never leave the microphone streaming while the app is in the background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      final voice = ref.read(voiceControllerProvider);
      if (voice.isLive) {
        unawaited(ref.read(voiceControllerProvider.notifier).stopLive(complete: false));
      }
    }
  }

  Future<void> _primaryAction() async {
    final controller = ref.read(voiceControllerProvider.notifier);
    final voice = ref.read(voiceControllerProvider);

    if (voice.isLive) {
      if (voice.usingFallback) {
        await controller.stopFallbackRecording();
      } else {
        await controller.stopLive();
      }
      return;
    }
    if (voice.isBusy || voice.phase == VoicePhase.reviewing) return;

    final caps = voice.statusInfo?.capabilities;
    if (caps == null) {
      await controller.loadStatus();
      return;
    }
    if (caps.geminiLive) {
      await controller.startLive();
    } else if (caps.fallbackStt && caps.fallbackLlm) {
      await controller.startFallbackRecording();
    } else {
      await controller.loadStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = ref.watch(voiceControllerProvider);
    final status = voice.statusInfo;
    final caps = status?.capabilities;
    final draft = voice.draft;

    return ScreenScaffold(
      title: 'المساعد',
      subtitle: 'احكي اللي عملته، وراجع المسودة قبل الحفظ.',
      header: const SyncBanner(),
      actions: [
        if (voice.lines.isNotEmpty || voice.error != null)
          ShadIconButton.ghost(
            icon: const Icon(LucideIcons.rotateCcw, size: 18),
            onPressed: () => ref.read(voiceControllerProvider.notifier).reset(),
          ),
      ],
      child: ListView(
        padding: Insets.page,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _AssistantStage(
            voice: voice,
            onPrimary: voice.phase == VoicePhase.reviewing ? null : _primaryAction,
          ),
          if (voice.error != null) ...[
            const SizedBox(height: 14),
            ShadAlert.destructive(
              icon: const Icon(LucideIcons.circleAlert, size: 16),
              description: Text(voice.error!),
            ),
          ],
          if (caps != null && !caps.anyVoice) ...[
            const SizedBox(height: 14),
            ShadAlert(
              icon: const Icon(LucideIcons.info, size: 16),
              title: const Text('المساعد مش متظبط'),
              description: const Text(
                'مفيش مزوّد صوتي متاح على السيرفر دلوقتي. كل حاجة تانية شغّالة، '
                'وتقدر تسجّل الزيارة والمهام يدوي عادي.',
              ),
            ),
          ] else if (caps != null && !caps.geminiLive && caps.anyVoice) ...[
            const SizedBox(height: 14),
            ShadAlert(
              icon: const Icon(LucideIcons.info, size: 16),
              title: const Text('الوضع السريع مش متاح'),
              description: const Text(
                'الجلسة المباشرة مش متاحة على السيرفر. التسجيل البطيء شغّال: '
                'اضغط الميكروفون، اتكلم، وبعدين اضغط تاني.',
              ),
            ),
          ],
          if (draft != null) ...[
            const SizedBox(height: Insets.gapLarge),
            DraftReview(draft: draft),
          ],
          if (draft == null && voice.lines.isNotEmpty) ...[
            const SizedBox(height: Insets.gapLarge),
            SectionTitle(title: 'المحادثة'),
            _TranscriptCard(lines: voice.lines),
          ],
          if (draft == null && voice.lines.isEmpty) ...[
            const SizedBox(height: Insets.gapLarge),
            const _Examples(),
          ],
          const SizedBox(height: Insets.gapLarge),
          SectionTitle(title: 'مش عايز تتكلم؟'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التسجيل اليدوي متاح دايماً، وبيشتغل بدون إنترنت. '
                  'أي مسودة صوتية بتفضل على الشاشة لو الاتصال قطع.',
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
                        onPressed: () => context.go('/sites'),
                        leading: const Icon(LucideIcons.notebookPen, size: 15),
                        child: const Text('سجّل زيارة يدوي'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ShadButton.outline(
                        size: ShadButtonSize.sm,
                        onPressed: () => context.go('/tasks'),
                        leading: const Icon(LucideIcons.checkSquare, size: 15),
                        child: const Text('المهام'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (status != null) ...[
            const SizedBox(height: Insets.gapLarge),
            _CapabilityStrip(status: status),
          ],
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- stage

class _AssistantStage extends StatelessWidget {
  const _AssistantStage({required this.voice, required this.onPrimary});

  final VoiceState voice;
  final Future<void> Function()? onPrimary;

  String get _headline {
    return switch (voice.phase) {
      VoicePhase.preparing => 'بنجهّز الجلسة…',
      VoicePhase.connecting => 'بنوصل بالمساعد…',
      VoicePhase.listening => voice.usingFallback ? 'بنسجّل صوتك…' : 'اتكلم، أنا سامعك',
      VoicePhase.thinking => 'بنفهم اللي قلته…',
      VoicePhase.speaking => 'المساعد بيرد…',
      VoicePhase.reviewing => 'مسودة جاهزة للمراجعة',
      VoicePhase.unavailable => 'المساعد مش متاح دلوقتي',
      VoicePhase.idle => 'اضغط واتكلم',
    };
  }

  String get _hint {
    return switch (voice.phase) {
      VoicePhase.listening => voice.usingFallback
          ? 'اضغط المربع لما تخلص كلامك.'
          : 'اتكلم بشكل طبيعي. اضغط المربع عشان توقف.',
      VoicePhase.reviewing => 'راجع التفاصيل تحت، عدّل أي حاجة، وبعدين أكّد الحفظ.',
      VoicePhase.unavailable => 'جرّب تاني، أو استخدم التسجيل اليدوي تحت.',
      VoicePhase.thinking => 'لحظة واحدة…',
      VoicePhase.connecting => 'بنفتح قناة صوتية آمنة.',
      VoicePhase.preparing => 'بنتأكد من إذن الميكروفون.',
      VoicePhase.speaking => 'لو حبيت تقاطع، اضغط المربع.',
      VoicePhase.idle => 'قول مثلاً: «خلصت توصيل لوحة الكهرباء في فيلا المعادي، '
          'باقي تجربة الأحمال».',
    };
  }

  bool get _showStop => voice.isLive || voice.isBusy;
  bool get _disabled => onPrimary == null || voice.isBusy;

  @override
  Widget build(BuildContext context) {
    final accent = switch (voice.phase) {
      VoicePhase.unavailable => context.scheme.destructive,
      VoicePhase.reviewing => context.scheme.primary,
      _ => context.scheme.primary,
    };

    return Column(
      children: [
        const SizedBox(height: 8),
        Semantics(
          button: true,
          enabled: !_disabled,
          label: _showStop ? 'إيقاف التسجيل' : 'ابدأ الكلام',
          child: InkWell(
            onTap: _disabled ? null : onPrimary,
            customBorder: const CircleBorder(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: voice.isLive ? accent : accent.withValues(alpha: 0.14),
                border: Border.all(
                  color: voice.isLive ? accent : accent.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: Center(
                child: voice.isBusy
                    ? SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: accent),
                      )
                    : Icon(
                        _showStop ? LucideIcons.square : LucideIcons.mic,
                        size: 40,
                        color: voice.isLive ? context.scheme.primaryForeground : accent,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _headline,
          textAlign: TextAlign.center,
          style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            _hint,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(color: context.mutedText, height: 1.55),
          ),
        ),
        if (voice.secondsLeft > 0) ...[
          const SizedBox(height: 12),
          Tag(
            label: 'الوقت المتبقي ${_clock(voice.secondsLeft)}',
            icon: LucideIcons.circleDot,
            color: context.scheme.secondary,
            foreground: context.scheme.secondaryForeground,
            outline: false,
          ),
        ],
        if (voice.micDenied) ...[
          const SizedBox(height: 12),
          ShadAlert(
            icon: const Icon(LucideIcons.triangleAlert, size: 16),
            description: const Text(
              'إذن الميكروفون مرفوض. افتح إعدادات النظام واسمح للميكروفون، '
              'أو كمّل بالتسجيل اليدوي.',
            ),
          ),
        ],
      ],
    );
  }

  static String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '$minutes:${rest.toString().padLeft(2, '0')}';
  }
}

// -------------------------------------------------------------- transcript

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.lines});

  final List<VoiceLine> lines;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (var index = 0; index < lines.length; index++) ...[
            if (index > 0) Divider(height: 1, color: context.hairline),
            _TranscriptLine(line: lines[index]),
          ],
        ],
      ),
    );
  }
}

class _TranscriptLine extends StatelessWidget {
  const _TranscriptLine({required this.line});

  final VoiceLine line;

  @override
  Widget build(BuildContext context) {
    final isUser = line.fromUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isUser ? context.scheme.secondary : context.scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isUser ? LucideIcons.userRound : LucideIcons.sparkles,
              size: 13,
              color: isUser ? context.scheme.secondaryForeground : context.scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'إنت' : 'المساعد',
                  style: context.texts.labelSmall?.copyWith(
                    color: context.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  line.text,
                  style: context.texts.bodyMedium?.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- examples

class _Examples extends StatelessWidget {
  const _Examples();

  static const List<String> _phrases = [
    'زرت موقع النصر النهارده وركّبت لوحة التوزيع.',
    'ضيف مهمة: معايرة مضخات الحريق الأسبوع الجاي.',
    'خلّص مهمة توصيل كابلات الدور التاني.',
  ];

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 15, color: context.scheme.primary),
              const SizedBox(width: 6),
              Text(
                'تقدر تقول حاجات زي',
                style: context.texts.labelMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final phrase in _phrases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '«$phrase»',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.mutedText,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- capabilities

class _CapabilityStrip extends StatelessWidget {
  const _CapabilityStrip({required this.status});

  final VoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final caps = status.capabilities;
    final usage = status.usage;
    final chips = <({String label, bool on})>[
      (label: 'جلسة مباشرة', on: caps.geminiLive),
      (label: 'تسجيل بطيء', on: caps.fallbackStt && caps.fallbackLlm),
      (label: 'بدون استدعاء مدفوع', on: !caps.paidFallbackAllowed),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'حالة المساعد',
          trailing: Text(
            '${usage.sessions} جلسة الشهر ده',
            style: context.texts.labelSmall?.copyWith(color: context.mutedText),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in chips)
              Tag(
                label: chip.label,
                icon: chip.on ? LucideIcons.circleCheck : LucideIcons.circleDot,
                color: chip.on ? null : context.scheme.muted,
                foreground: chip.on ? context.scheme.primary : context.mutedText,
              ),
          ],
        ),
        if (usage.warning != null) ...[
          const SizedBox(height: 10),
          ShadAlert(
            icon: const Icon(LucideIcons.triangleAlert, size: 16),
            description: Text(usage.warning!),
          ),
        ],
      ],
    );
  }
}
