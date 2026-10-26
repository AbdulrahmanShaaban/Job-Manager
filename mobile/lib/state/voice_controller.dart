import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api_exception.dart';
import '../core/speech.dart';
import '../models/task.dart';
import '../models/voice.dart';
import '../state/data_providers.dart';
import '../state/providers.dart';

enum VoicePhase {
  idle,
  preparing,
  connecting,
  listening,
  thinking,
  speaking,
  reviewing,
  unavailable,
}

class VoiceLine {
  const VoiceLine({required this.fromUser, required this.text, this.partial = false});

  final bool fromUser;
  final String text;
  final bool partial;

  VoiceLine copyWith({String? text, bool? partial}) {
    return VoiceLine(
      fromUser: fromUser,
      text: text ?? this.text,
      partial: partial ?? this.partial,
    );
  }
}

class VoiceState {
  const VoiceState({
    this.phase = VoicePhase.idle,
    this.lines = const [],
    this.status,
    this.error,
    this.draft,
    this.statusInfo,
    this.usingFallback = false,
    this.secondsLeft = 0,
    this.sessionId,
    this.micDenied = false,
  });

  final VoicePhase phase;
  final List<VoiceLine> lines;
  final String? status;
  final String? error;
  final AssistantDraft? draft;
  final VoiceStatus? statusInfo;
  final bool usingFallback;
  final int secondsLeft;
  final String? sessionId;
  final bool micDenied;

  bool get isBusy =>
      phase == VoicePhase.preparing ||
      phase == VoicePhase.connecting ||
      phase == VoicePhase.thinking;

  bool get isLive => phase == VoicePhase.listening || phase == VoicePhase.speaking;

  bool get canRecord =>
      phase == VoicePhase.idle || phase == VoicePhase.unavailable || phase == VoicePhase.reviewing;

  static const Object _unset = Object();

  VoiceState copyWith({
    VoicePhase? phase,
    List<VoiceLine>? lines,
    Object? status = _unset,
    Object? error = _unset,
    AssistantDraft? draft,
    bool clearDraft = false,
    VoiceStatus? statusInfo,
    bool? usingFallback,
    int? secondsLeft,
    String? sessionId,
    bool clearSession = false,
    bool? micDenied,
  }) {
    return VoiceState(
      phase: phase ?? this.phase,
      lines: lines ?? this.lines,
      // Status and error need an explicit clear: omitting them must preserve the
      // current message instead of silently wiping it on every state update.
      status: identical(status, _unset) ? this.status : status as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      draft: clearDraft ? null : (draft ?? this.draft),
      statusInfo: statusInfo ?? this.statusInfo,
      usingFallback: usingFallback ?? this.usingFallback,
      secondsLeft: secondsLeft ?? this.secondsLeft,
      sessionId: clearSession ? null : (sessionId ?? this.sessionId),
      micDenied: micDenied ?? this.micDenied,
    );
  }
}

/// Drives the Gemini Live session and the free fallback chain.
///
/// The permanent provider key never exists on this device: the server issues a
/// single-use Live token, and every tool call is executed server-side.
class VoiceController extends Notifier<VoiceState> {
  static const String _liveEndpoint =
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained';

  final AudioRecorder _recorder = AudioRecorder();
  final SpeechService _speech = SpeechService();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _countdown;
  DateTime? _sessionStartedAt;
  bool _setupComplete = false;
  bool _stoppingFallback = false;
  bool _stoppingLive = false;

  @override
  VoiceState build() {
    ref.onDispose(() {
      _teardown();
      _recorder.dispose();
      _speech.dispose();
    });
    return const VoiceState();
  }

  Future<void> loadStatus() async {
    try {
      final status = await ref.read(apiRepositoryProvider).voiceStatus();
      state = state.copyWith(
        statusInfo: status,
        phase: status.capabilities.anyVoice ? VoicePhase.idle : VoicePhase.unavailable,
        status: status.capabilities.anyVoice
            ? null
            : 'المساعد الصوتي مش متظبط على السيرفر. التسجيل اليدوي شغّال عادي.',
      );
    } on ApiException catch (error) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        status: error.isNetworkError
            ? 'مفيش اتصال. المساعد الصوتي محتاج إنترنت، بس تقدر تسجّل الزيارة يدوي.'
            : error.message,
      );
    }
  }

  // ------------------------------------------------------------- live mode

  Future<void> startLive() async {
    if (_stoppingLive || _stoppingFallback) return;
    if (state.phase == VoicePhase.connecting || state.phase == VoicePhase.preparing) return;

    state = state.copyWith(
      phase: VoicePhase.preparing,
      status: 'بنجهّز جلسة الصوت…',
      error: null,
      usingFallback: false,
      // Do not clear the draft here: if connecting fails, the user must still
      // find their reviewed draft on screen.
      lines: const [],
    );

    final granted = await _ensureMicrophone();
    if (!granted) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        micDenied: true,
        status: 'محتاجين إذن الميكروفون عشان نسمعك. تقدر تسجّل يدوي في أي وقت.',
      );
      return;
    }

    VoiceCredential credential;
    try {
      credential = await ref.read(apiRepositoryProvider).voiceCredential();
    } on ApiException catch (error) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        error: error.message,
        status: error.isAiUnavailable
            ? 'المساعد السريع مش متاح دلوقتي. جرّب الوضع البطيء أو سجّل يدوي.'
            : null,
      );
      return;
    }

    state = state.copyWith(
      phase: VoicePhase.connecting,
      sessionId: credential.sessionId,
      status: 'بنوصل بالمساعد…',
      secondsLeft: credential.maxSessionSeconds,
    );

    try {
      final uri = Uri.parse('$_liveEndpoint?access_token=${Uri.encodeComponent(credential.token)}');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 20));
      _channel = channel;
      _setupComplete = false;
      _sessionStartedAt = DateTime.now();

      _socketSub = channel.stream.listen(
        _onSocketData,
        onError: (Object error) => _failLive('الاتصال بالمساعد اتقطع. جرّب تاني.'),
        onDone: _onSocketClosed,
        cancelOnError: false,
      );

      channel.sink.add(jsonEncode({'setup': credential.setup}));
      _startCountdown(
        credential.maxSessionSeconds,
        onDone: () => stopLive(endMessage: 'خلص وقت الجلسة.'),
      );
    } catch (error) {
      _failLive('تعذر بدء الجلسة الصوتية. جرّب الوضع البطيء أو التسجيل اليدوي.');
    }
  }

  Future<void> _onSetupComplete() async {
    _setupComplete = true;
    state = state.copyWith(phase: VoicePhase.listening, status: 'اتكلم…');
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSub = stream.listen((chunk) {
        if (chunk.isEmpty || _channel == null || !_setupComplete) return;
        _send({
          'realtimeInput': {
            'audio': {'mimeType': 'audio/pcm;rate=16000', 'data': base64Encode(chunk)},
          },
        });
      });
    } catch (_) {
      _failLive('تعذر تشغيل الميكروفون. جرّب الوضع البطيء أو التسجيل اليدوي.');
    }
  }

  void _onSocketData(dynamic raw) {
    final String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      return;
    }

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } catch (_) {
      return;
    }

    if (message.containsKey('setupComplete')) {
      unawaited(_onSetupComplete());
      return;
    }

    final toolCall = message['toolCall'];
    if (toolCall is Map) {
      unawaited(_handleToolCall(Map<String, dynamic>.from(toolCall)));
    }

    final content = message['serverContent'];
    if (content is Map) {
      _handleServerContent(Map<String, dynamic>.from(content));
    }
  }

  void _handleServerContent(Map<String, dynamic> content) {
    final input = content['inputTranscription'];
    if (input is Map && input['text'] is String) {
      _appendLine(fromUser: true, text: input['text'] as String);
    }

    final output = content['outputTranscription'];
    if (output is Map && output['text'] is String) {
      _appendLine(fromUser: false, text: output['text'] as String);
    }

    final turn = content['modelTurn'];
    if (turn is Map && turn['parts'] is List) {
      final buffer = StringBuffer();
      for (final part in turn['parts'] as List) {
        if (part is Map && part['text'] is String) buffer.write(part['text'] as String);
      }
      if (buffer.isNotEmpty) {
        _appendLine(fromUser: false, text: buffer.toString());
      }
    }

    if (content['turnComplete'] == true) {
      state = state.copyWith(phase: VoicePhase.listening, status: 'اتكلم…');
      final lastAssistant = _lastAssistantText();
      if (lastAssistant != null && _shouldSpeak()) {
        unawaited(_speakSafely(lastAssistant));
      }
    }
  }

  Future<void> _handleToolCall(Map<String, dynamic> toolCall) async {
    final calls = toolCall['functionCalls'];
    if (calls is! List) return;

    state = state.copyWith(phase: VoicePhase.thinking, status: 'بجهّز الطلب…');
    final responses = <Map<String, dynamic>>[];

    for (final rawCall in calls) {
      if (rawCall is! Map) continue;
      final call = Map<String, dynamic>.from(rawCall);
      final id = call['id']?.toString() ?? '';
      final name = call['name']?.toString() ?? '';
      final args = call['args'] is Map
          ? Map<String, dynamic>.from(call['args'] as Map)
          : <String, dynamic>{};

      try {
        final result = await ref
            .read(apiRepositoryProvider)
            .runTool(name, args, sessionId: state.sessionId);
        final draft = AssistantDraft.tryParse(result);
        responses.add({
          'id': id,
          'name': name,
          'response': {'result': result},
        });
        if (draft != null) {
          await _stopListening();
          state = state.copyWith(
            draft: draft,
            phase: VoicePhase.reviewing,
            status: 'راجع المسودة قبل الحفظ.',
          );
        }
      } on ApiException catch (error) {
        responses.add({
          'id': id,
          'name': name,
          'response': {
            'error': {'message': error.message, 'code': error.code},
          },
        });
      }
    }

    if (responses.isNotEmpty) {
      _send({
        'toolResponse': {'functionResponses': responses},
      });
    }
    if (state.phase == VoicePhase.thinking) {
      state = state.copyWith(phase: VoicePhase.listening, status: 'اتكلم…');
    }
  }

  Future<void> _stopListening() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder.isRecording()) {
        _send({
          'realtimeInput': {'audioStreamEnd': true},
        });
        await _recorder.stop();
      }
    } catch (_) {}
  }

  Future<void> stopLive({bool complete = true, String? endMessage}) async {
    // Tab switch, app pause, and the countdown can all request a stop; the
    // session must be closed and reported exactly once.
    if (_stoppingLive) return;
    _stoppingLive = true;
    try {
      final sessionId = state.sessionId;
      final seconds = _sessionStartedAt == null
          ? 0
          : DateTime.now().difference(_sessionStartedAt!).inSeconds;

      await _stopListening();
      _countdown?.cancel();
      _countdown = null;

      await _socketSub?.cancel();
      _socketSub = null;
      try {
        await _channel?.sink.close();
      } catch (_) {}
      _channel = null;
      _setupComplete = false;

      if (complete && sessionId != null) {
        try {
          await ref.read(apiRepositoryProvider).completeVoiceSession(
            sessionId,
            status: 'COMPLETED',
            summary: _lastAssistantText()?.substring(
              0,
              _lastAssistantText()!.length > 280 ? 280 : _lastAssistantText()!.length,
            ),
            estimatedSeconds: seconds,
          );
        } catch (_) {
          // Usage metadata is best-effort; the user's draft is unaffected.
        }
      }

      state = state.copyWith(
        phase: state.draft != null ? VoicePhase.reviewing : VoicePhase.idle,
        status: endMessage,
        clearSession: true,
      );
    } finally {
      _stoppingLive = false;
    }
  }

  void _startCountdown(int maxSeconds, {required Future<void> Function() onDone}) {
    _countdown?.cancel();
    var remaining = maxSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      remaining -= 1;
      if (remaining <= 0) {
        timer.cancel();
        _countdown = null;
        state = state.copyWith(secondsLeft: 0);
        unawaited(onDone());
        return;
      }
      state = state.copyWith(secondsLeft: remaining);
    });
  }

  void _onSocketClosed() {
    if (state.phase == VoicePhase.reviewing || state.phase == VoicePhase.idle) return;
    _failLive('الجلسة اتقفلت. جرّب تاني أو استخدم التسجيل اليدوي.');
  }

  Future<void> _stopRecorder() async {
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  void _failLive(String message) {
    _countdown?.cancel();
    _countdown = null;
    unawaited(_stopRecorder());
    _socketSub?.cancel();
    _socketSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setupComplete = false;

    final sessionId = state.sessionId;
    if (sessionId != null) {
      unawaited(_reportSessionFailure(sessionId));
    }

    state = state.copyWith(
      phase: state.draft != null ? VoicePhase.reviewing : VoicePhase.unavailable,
      status: message,
      secondsLeft: 0,
      clearSession: true,
    );
  }

  Future<void> _reportSessionFailure(String sessionId) async {
    try {
      await ref
          .read(apiRepositoryProvider)
          .completeVoiceSession(sessionId, status: 'FAILED', errorCode: 'LIVE_FAILED');
    } catch (_) {
      // Best effort: the server reaps stale sessions on its own.
    }
  }

  // --------------------------------------------------------- fallback mode

  Future<void> startFallbackRecording() async {
    // Ignore a second tap while a turn is already being recorded or uploaded.
    if (_stoppingFallback || state.phase == VoicePhase.listening) return;

    final granted = await _ensureMicrophone();
    if (!granted) {
      state = state.copyWith(micDenied: true, status: 'محتاجين إذن الميكروفون.');
      return;
    }

    final maxSeconds = state.statusInfo?.capabilities.fallbackMaxSeconds ?? 30;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice-turn-${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _fallbackPath = path;
      state = state.copyWith(
        usingFallback: true,
        phase: VoicePhase.listening,
        status: 'بنسجّل… اضغط تاني لما تخلص.',
        error: null,
        secondsLeft: maxSeconds,
      );
      // One timer only: it drives the visible countdown and stops the
      // recording exactly once. A second timer used to fire concurrently and
      // send the same turn twice.
      _startCountdown(maxSeconds, onDone: stopFallbackRecording);
    } catch (_) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        status: 'تعذر تشغيل الميكروفون. اكتب الزيارة يدوي.',
      );
    }
  }

  String? _fallbackPath;

  Future<void> stopFallbackRecording() async {
    // The tap handler and the countdown can both call this; only the first
    // call may stop the recorder and upload the turn.
    if (_stoppingFallback) return;
    _stoppingFallback = true;
    _countdown?.cancel();
    _countdown = null;

    final pendingPath = _fallbackPath;
    _fallbackPath = null;
    state = state.copyWith(phase: VoicePhase.thinking, status: 'بنفهم الكلام…');

    File? file;
    try {
      String? path;
      try {
        if (await _recorder.isRecording()) path = await _recorder.stop();
      } catch (_) {}
      path ??= pendingPath;
      if (path == null || path.isEmpty) {
        state = state.copyWith(
          phase: VoicePhase.idle,
          status: 'مفيش تسجيل. جرّب تاني.',
        );
        return;
      }

      file = File(path);
      if (!file.existsSync()) {
        state = state.copyWith(
          phase: VoicePhase.idle,
          status: 'مفيش تسجيل. جرّب تاني.',
        );
        return;
      }
      final bytes = await file.readAsBytes();
      final duration = ((bytes.length / 32000).clamp(0.5, 120)).toDouble();
      final turn = await ref.read(apiRepositoryProvider).fallbackTurn(
        audio: bytes,
        mimeType: 'audio/wav',
        durationSeconds: duration,
      );

      final lines = <VoiceLine>[
        if (turn.transcript.isNotEmpty) VoiceLine(fromUser: true, text: turn.transcript),
        if (turn.reply.isNotEmpty) VoiceLine(fromUser: false, text: turn.reply),
      ];
      final draft = AssistantDraft.tryParse(turn.toolResult);

      state = state.copyWith(
        lines: [...state.lines, ...lines],
        draft: draft,
        phase: draft != null ? VoicePhase.reviewing : VoicePhase.idle,
        status: turn.toolError ?? (draft != null ? 'راجع المسودة قبل الحفظ.' : null),
        error: turn.toolError,
        sessionId: turn.sessionId,
      );

      if (_shouldSpeak() && turn.reply.isNotEmpty) {
        await _speakSafely(turn.reply);
      }
    } on ApiException catch (error) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        status: error.message,
        error: error.message,
      );
    } catch (error) {
      state = state.copyWith(
        phase: VoicePhase.unavailable,
        status: 'حصل خطأ في التسجيل. جرّب تاني أو اكتب يدوي.',
      );
    } finally {
      // The clip is only needed until the server has transcribed it; leaving it
      // in the temp directory would silently grow the app's disk usage.
      if (file != null) {
        try {
          if (file.existsSync()) await file.delete();
        } catch (_) {}
      }
      _stoppingFallback = false;
    }
  }

  // ------------------------------------------------------------- draft flow

  /// Applies a reviewed draft. Returns `true` when something was saved.
  Future<bool> confirmDraft({AssistantDraft? edited}) async {
    final draft = edited ?? state.draft;
    if (draft == null) return false;

    final mutations = ref.read(mutationsProvider);
    final db = ref.read(localDbProvider);
    final keepTranscripts = ref.read(settingsProvider).value?.keepTranscripts ?? true;

    try {
      if (draft.isVisit) {
        if (draft.siteId == null || draft.completedWork == null) {
          state = state.copyWith(error: 'المسودة ناقصة: لازم موقع ووصف للشغل اللي خلص.');
          return false;
        }
        await mutations.createVisit(
          siteId: draft.siteId!,
          visitDate: draft.visitDate ?? mutations.todayIso(),
          completedWork: draft.completedWork!,
          remainingWork: draft.remainingWork,
          notes: draft.notes,
          transcript: keepTranscripts ? _currentTranscript() : null,
          source: 'VOICE',
        );
      } else if (draft.isTask) {
        await mutations.createTask(
          siteId: draft.siteId,
          title: draft.title ?? 'مهمة جديدة',
          description: draft.description,
          priority: TaskPriority.fromWire(draft.priority),
          dueDate: draft.dueDate,
        );
      } else if (draft.isTaskUpdate) {
        if (draft.taskId == null) {
          state = state.copyWith(error: 'المسودة ناقصة: مهمة غير معروفة.');
          return false;
        }
        final tasks = await db.readTasks();
        Task? target;
        for (final task in tasks) {
          if (task.id == draft.taskId) {
            target = task;
            break;
          }
        }
        if (target == null) {
          state = state.copyWith(error: 'المهمة دي مش موجودة على الجهاز. افتح المهام وحدّثها الأول.');
          return false;
        }
        await mutations.updateTask(
          target,
          status: draft.proposedStatus == null
              ? null
              : TaskStatus.fromWire(draft.proposedStatus),
          title: draft.title,
          description: draft.description,
          priority: draft.priority == null ? null : TaskPriority.fromWire(draft.priority),
          dueDate: draft.dueDate,
        );
      } else {
        return false;
      }

      await mutations.flushQuietly();
      await ref.read(syncControllerProvider.notifier).refreshCounts();
      ref.invalidate(overviewProvider);
      ref.invalidate(sitesProvider);
      ref.invalidate(tasksProvider);
      if (draft.siteId != null) ref.invalidate(siteDetailProvider(draft.siteId!));

      state = state.copyWith(
        draft: null,
        clearDraft: true,
        phase: VoicePhase.idle,
        status: 'تم الحفظ. لو الشبكة مقطوعة هيتزامن لوحده.',
        error: null,
      );
      return true;
    } on ApiException catch (error) {
      state = state.copyWith(error: error.message);
      return false;
    }
  }

  void dismissDraft() {
    state = state.copyWith(clearDraft: true, phase: VoicePhase.idle, status: null);
  }

  void reset() {
    unawaited(stopLive(complete: false));
    state = const VoiceState();
    unawaited(loadStatus());
  }

  // ---------------------------------------------------------------- helpers

  Future<bool> _ensureMicrophone() async {
    try {
      // `record` owns the microphone permission: hasPermission() shows the OS
      // dialog when needed and reports the result. Keeping a second permission
      // plugin only added an Android SDK 37 build requirement.
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  bool _shouldSpeak() {
    return ref.read(settingsProvider).value?.speakReplies ?? true;
  }

  Future<void> _speakSafely(String text) async {
    try {
      await _speech.speak(text);
    } catch (_) {}
  }

  String? _lastAssistantText() {
    for (final line in state.lines.reversed) {
      if (!line.fromUser && line.text.trim().isNotEmpty) return line.text.trim();
    }
    return null;
  }

  /// Everything the user said during this session, for the optional visit
  /// transcript. Returns `null` when the user said nothing.
  ///
  /// Capped at the server's 12 000-character limit so a long session cannot
  /// turn a confirmed visit into a validation failure.
  String? _currentTranscript() {
    final said = state.lines
        .where((line) => line.fromUser && line.text.trim().isNotEmpty)
        .map((line) => line.text.trim())
        .join('\n');
    if (said.isEmpty) return null;
    return said.length > 12000 ? said.substring(0, 12000) : said;
  }

  void _appendLine({required bool fromUser, required String text}) {
    if (text.isEmpty) return;
    final lines = List<VoiceLine>.from(state.lines);
    if (lines.isNotEmpty && lines.last.fromUser == fromUser) {
      lines[lines.length - 1] = lines.last.copyWith(text: '${lines.last.text}$text');
    } else {
      lines.add(VoiceLine(fromUser: fromUser, text: text));
    }
    state = state.copyWith(lines: lines);
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _teardown() {
    _countdown?.cancel();
    _countdown = null;
    _audioSub?.cancel();
    _socketSub?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setupComplete = false;
    _stoppingFallback = false;
    _stoppingLive = false;
    _fallbackPath = null;
    // A disposed provider must not leave the microphone open.
    unawaited(_stopRecorder());
  }
}

final voiceControllerProvider = NotifierProvider<VoiceController, VoiceState>(
  VoiceController.new,
);
