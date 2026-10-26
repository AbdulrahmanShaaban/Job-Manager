import 'json.dart';

class Visit {
  const Visit({
    required this.id,
    required this.siteId,
    required this.visitDate,
    required this.completedWork,
    this.remainingWork,
    this.notes,
    this.transcript,
    this.source = 'MANUAL',
    this.createdById,
    this.createdByName,
    this.revision = 0,
    this.editedAt,
    this.createdAt,
    this.updatedAt,
    this.siteName,
    this.pending = false,
  });

  final String id;
  final String siteId;
  final String visitDate;
  final String completedWork;
  final String? remainingWork;
  final String? notes;
  final String? transcript;
  final String source;
  final String? createdById;
  final String? createdByName;
  final int revision;
  final DateTime? editedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Present when the visit comes from the dashboard feed.
  final String? siteName;

  /// True while the visit is still queued for sync.
  final bool pending;

  bool get isVoice => source == 'VOICE';
  bool get wasEdited => revision > 0;

  factory Visit.fromJson(Map<String, dynamic> json) {
    final createdBy = asMap(json['createdBy']);
    final site = asMap(json['site']);
    return Visit(
      id: asRequiredString(json['id']),
      siteId: asRequiredString(json['siteId']),
      visitDate: asDateOnly(json['visitDate']) ?? '',
      completedWork: asRequiredString(json['completedWork']),
      remainingWork: asString(json['remainingWork']),
      notes: asString(json['notes']),
      transcript: asString(json['transcript']),
      source: asString(json['source']) ?? 'MANUAL',
      createdById: asString(json['createdById']),
      createdByName: asString(createdBy['name']),
      revision: asInt(json['revision']),
      editedAt: asDateTime(json['editedAt']),
      createdAt: asDateTime(json['createdAt']),
      updatedAt: asDateTime(json['updatedAt']),
      siteName: asString(site['name']),
      pending: json['pending'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'siteId': siteId,
      'visitDate': visitDate,
      'completedWork': completedWork,
      'remainingWork': remainingWork,
      'notes': notes,
      'transcript': transcript,
      'source': source,
      'createdById': createdById,
      'createdBy': createdByName == null ? null : {'name': createdByName},
      'revision': revision,
      'editedAt': editedAt?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      if (siteName != null) 'site': {'name': siteName},
      if (pending) 'pending': true,
    };
  }
}
