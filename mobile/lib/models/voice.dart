import 'json.dart';

/// Short-lived Live API credential issued by the server. The permanent Gemini
/// key never reaches the device.
class VoiceCredential {
  const VoiceCredential({
    required this.sessionId,
    required this.token,
    required this.model,
    required this.setup,
    required this.maxSessionSeconds,
    this.expiresAt,
    this.newSessionExpireTime,
    this.transcriptRetentionEnabled = false,
  });

  final String sessionId;
  final String token;
  final String model;

  /// Exact setup payload to send as the first WebSocket message.
  final Map<String, dynamic> setup;
  final int maxSessionSeconds;
  final String? expiresAt;
  final String? newSessionExpireTime;
  final bool transcriptRetentionEnabled;

  factory VoiceCredential.fromJson(Map<String, dynamic> json) {
    return VoiceCredential(
      sessionId: asRequiredString(json['sessionId']),
      token: asRequiredString(json['token']),
      model: asRequiredString(json['model']),
      setup: asMap(json['setup']),
      maxSessionSeconds: asInt(json['maxSessionSeconds'], 300),
      expiresAt: asString(json['expiresAt']),
      newSessionExpireTime: asString(json['newSessionExpireTime']),
      transcriptRetentionEnabled: json['transcriptRetentionEnabled'] == true,
    );
  }
}

class VoiceLimits {
  const VoiceLimits({
    this.sessions = 0,
    this.minutes = 0,
    this.budgetUsd = 0,
  });

  final int sessions;
  final int minutes;
  final double budgetUsd;

  factory VoiceLimits.fromJson(Map<String, dynamic> json) {
    return VoiceLimits(
      sessions: asInt(json['sessions']),
      minutes: asInt(json['minutes']),
      budgetUsd: asDouble(json['budgetUsd']) ?? 0,
    );
  }
}

class VoiceUsage {
  const VoiceUsage({
    this.sessions = 0,
    this.seconds = 0,
    this.minutes = 0,
    this.monthStart,
    this.limits = const VoiceLimits(),
    this.percentOfSessionLimit = 0,
    this.percentOfMinuteLimit = 0,
    this.warning,
  });

  final int sessions;
  final double seconds;
  final double minutes;
  final String? monthStart;
  final VoiceLimits limits;
  final int percentOfSessionLimit;
  final int percentOfMinuteLimit;
  final String? warning;

  factory VoiceUsage.fromJson(Map<String, dynamic> json) {
    return VoiceUsage(
      sessions: asInt(json['sessions']),
      seconds: asDouble(json['seconds']) ?? 0,
      minutes: asDouble(json['minutes']) ?? 0,
      monthStart: asString(json['monthStart']),
      limits: VoiceLimits.fromJson(asMap(json['limits'])),
      percentOfSessionLimit: asInt(json['percentOfSessionLimit']),
      percentOfMinuteLimit: asInt(json['percentOfMinuteLimit']),
      warning: asString(json['warning']),
    );
  }

  Map<String, dynamic> toJson() => {
    'sessions': sessions,
    'seconds': seconds,
    'minutes': minutes,
    'monthStart': monthStart,
    'limits': {
      'sessions': limits.sessions,
      'minutes': limits.minutes,
      'budgetUsd': limits.budgetUsd,
    },
    'percentOfSessionLimit': percentOfSessionLimit,
    'percentOfMinuteLimit': percentOfMinuteLimit,
    'warning': warning,
  };
}

class VoiceCapabilities {
  const VoiceCapabilities({
    this.geminiLive = false,
    this.fallbackStt = false,
    this.fallbackLlm = false,
    this.transcriptRetentionEnabled = false,
    this.paidFallbackAllowed = false,
    this.budgetUsd = 0,
    this.maxSessionSeconds = 300,
    this.fallbackMaxSeconds = 30,
  });

  final bool geminiLive;
  final bool fallbackStt;
  final bool fallbackLlm;
  final bool transcriptRetentionEnabled;
  final bool paidFallbackAllowed;
  final double budgetUsd;
  final int maxSessionSeconds;
  final int fallbackMaxSeconds;

  bool get anyVoice => geminiLive || (fallbackStt && fallbackLlm);

  factory VoiceCapabilities.fromJson(Map<String, dynamic> json) {
    return VoiceCapabilities(
      geminiLive: json['geminiLive'] == true,
      fallbackStt: json['fallbackStt'] == true,
      fallbackLlm: json['fallbackLlm'] == true,
      transcriptRetentionEnabled: json['transcriptRetentionEnabled'] == true,
      paidFallbackAllowed: json['paidFallbackAllowed'] == true,
      budgetUsd: asDouble(json['budgetUsd']) ?? 0,
      maxSessionSeconds: asInt(json['maxSessionSeconds'], 300),
      fallbackMaxSeconds: asInt(json['fallbackMaxSeconds'], 30),
    );
  }

  Map<String, dynamic> toJson() => {
    'geminiLive': geminiLive,
    'fallbackStt': fallbackStt,
    'fallbackLlm': fallbackLlm,
    'transcriptRetentionEnabled': transcriptRetentionEnabled,
    'paidFallbackAllowed': paidFallbackAllowed,
    'budgetUsd': budgetUsd,
    'maxSessionSeconds': maxSessionSeconds,
    'fallbackMaxSeconds': fallbackMaxSeconds,
  };
}

class VoiceStatus {
  const VoiceStatus({
    this.usage = const VoiceUsage(),
    this.capabilities = const VoiceCapabilities(),
    this.cooldowns = const {},
  });

  final VoiceUsage usage;
  final VoiceCapabilities capabilities;
  final Map<String, dynamic> cooldowns;

  factory VoiceStatus.fromJson(Map<String, dynamic> json) {
    return VoiceStatus(
      usage: VoiceUsage.fromJson(asMap(json['usage'])),
      capabilities: VoiceCapabilities.fromJson(asMap(json['capabilities'])),
      cooldowns: asMap(json['cooldowns']),
    );
  }
}

/// Result of one turn through the free fallback chain.
class FallbackTurn {
  const FallbackTurn({
    required this.sessionId,
    required this.transcript,
    required this.reply,
    this.toolResult,
    this.toolError,
    this.provider = '',
  });

  final String sessionId;
  final String transcript;
  final String reply;
  final Map<String, dynamic>? toolResult;
  final String? toolError;
  final String provider;

  factory FallbackTurn.fromJson(Map<String, dynamic> json) {
    return FallbackTurn(
      sessionId: asRequiredString(json['sessionId']),
      transcript: asString(json['transcript']) ?? '',
      reply: asString(json['reply']) ?? '',
      toolResult: json['toolResult'] == null ? null : asMap(json['toolResult']),
      toolError: asString(json['toolError']),
      provider: asString(json['provider']) ?? '',
    );
  }
}

/// A proposed change produced by the assistant. It is never applied without an
/// explicit confirmation from the review screen.
class AssistantDraft {
  const AssistantDraft({
    required this.kind,
    required this.operationId,
    this.siteId,
    this.siteName,
    this.visitDate,
    this.completedWork,
    this.remainingWork,
    this.notes,
    this.title,
    this.description,
    this.priority,
    this.dueDate,
    this.taskId,
    this.proposedStatus,
    this.baseUpdatedAt,
    this.warning,
    this.before,
  });

  /// `visit`, `task`, or `taskUpdate`.
  final String kind;
  final String operationId;
  final String? siteId;
  final String? siteName;
  final String? visitDate;
  final String? completedWork;
  final String? remainingWork;
  final String? notes;
  final String? title;
  final String? description;
  final String? priority;
  final String? dueDate;
  final String? taskId;
  final String? proposedStatus;
  final String? baseUpdatedAt;
  final String? warning;
  final Map<String, dynamic>? before;

  bool get isVisit => kind == 'visit';
  bool get isTask => kind == 'task';
  bool get isTaskUpdate => kind == 'taskUpdate';

  /// Extracts a draft from `{ok: true, result: {...}}`, returning `null` for
  /// read-only tool results (searches, summaries) which need no confirmation.
  static AssistantDraft? tryParse(Map<String, dynamic>? toolResult) {
    if (toolResult == null) return null;
    final result = asMap(toolResult['result']);
    if (result.isEmpty) return null;
    final kind = asString(result['kind']);
    if (kind == null || result['requiresConfirmation'] != true) return null;

    return AssistantDraft(
      kind: kind,
      operationId: asString(result['operationId']) ?? '',
      siteId: asString(asMap(result['site'])['id']) ?? asString(result['siteId']),
      siteName: asString(asMap(result['site'])['name']),
      visitDate: asDateOnly(result['visitDate']),
      completedWork: asString(result['completedWork']),
      remainingWork: asString(result['remainingWork']),
      notes: asString(result['notes']),
      title: asString(result['title']),
      description: asString(result['description']),
      priority: asString(result['priority']),
      dueDate: asDateOnly(result['dueDate']),
      taskId: asString(result['taskId']),
      proposedStatus: asString(asMap(result['proposed'])['status']),
      baseUpdatedAt: asString(result['baseUpdatedAt']),
      warning: asString(result['warning']),
      before: result['before'] == null ? null : asMap(result['before']),
    );
  }
}
