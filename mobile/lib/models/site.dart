import 'json.dart';

enum SiteScope {
  personal('PERSONAL', 'شغلي'),
  company('COMPANY', 'مواقع الشركة');

  const SiteScope(this.wire, this.label);

  final String wire;
  final String label;

  static SiteScope fromWire(String? value) {
    return value == 'COMPANY' ? SiteScope.company : SiteScope.personal;
  }
}

enum SiteStatus {
  active('ACTIVE', 'نشط'),
  archived('ARCHIVED', 'مؤرشف');

  const SiteStatus(this.wire, this.label);

  final String wire;
  final String label;

  static SiteStatus fromWire(String? value) {
    return value == 'ARCHIVED' ? SiteStatus.archived : SiteStatus.active;
  }
}

class SiteAccess {
  const SiteAccess({required this.canWrite, required this.canManage, this.role});

  final bool canWrite;
  final bool canManage;
  final String? role;

  factory SiteAccess.fromJson(Map<String, dynamic> json) {
    return SiteAccess(
      canWrite: json['canWrite'] == true,
      canManage: json['canManage'] == true,
      role: asString(json['role']),
    );
  }

  Map<String, dynamic> toJson() => {
    'canWrite': canWrite,
    'canManage': canManage,
    'role': role,
  };
}

class Site {
  const Site({
    required this.id,
    required this.name,
    required this.scope,
    required this.status,
    required this.address,
    this.workspaceId,
    this.workspaceName,
    this.contactName,
    this.contactPhone,
    this.mapUrl,
    this.latitude,
    this.longitude,
    this.generalNotes,
    this.openTaskCount = 0,
    this.lastVisit,
    this.createdAt,
    this.updatedAt,
    this.access,
    this.pending = false,
  });

  final String id;
  final String name;
  final SiteScope scope;
  final SiteStatus status;
  final String address;
  final String? workspaceId;
  final String? workspaceName;
  final String? contactName;
  final String? contactPhone;
  final String? mapUrl;
  final double? latitude;
  final double? longitude;
  final String? generalNotes;
  final int openTaskCount;
  final VisitSummary? lastVisit;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final SiteAccess? access;

  /// True while a locally-created or locally-edited record is still queued.
  final bool pending;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Coordinates are preferred for the map action; a stored URL is the fallback.
  String? get mapLink {
    if (mapUrl != null && mapUrl!.isNotEmpty) return mapUrl;
    if (hasCoordinates) {
      return 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude';
    }
    if (address.isNotEmpty) {
      return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}';
    }
    return null;
  }

  factory Site.fromJson(Map<String, dynamic> json) {
    final workspace = asMap(json['workspace']);
    final lastVisitJson = json['lastVisit'];
    final accessJson = asMap(json['access']);
    return Site(
      id: asRequiredString(json['id']),
      name: asRequiredString(json['name'], 'موقع بدون اسم'),
      scope: SiteScope.fromWire(asString(json['scope'])),
      status: SiteStatus.fromWire(asString(json['status'])),
      address: asRequiredString(json['address']),
      workspaceId: asString(json['workspaceId']) ?? asString(workspace['id']),
      workspaceName: asString(workspace['name']),
      contactName: asString(json['contactName']),
      contactPhone: asString(json['contactPhone']),
      mapUrl: asString(json['mapUrl']),
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      generalNotes: asString(json['generalNotes']),
      openTaskCount: asInt(json['openTaskCount']),
      lastVisit: lastVisitJson == null ? null : VisitSummary.fromJson(asMap(lastVisitJson)),
      createdAt: asDateTime(json['createdAt']),
      updatedAt: asDateTime(json['updatedAt']),
      access: accessJson.isEmpty ? null : SiteAccess.fromJson(accessJson),
      pending: json['pending'] == true,
    );
  }

  /// Serialised without nested collections so the local cache keeps one row per
  /// site; tasks and visits are cached in their own tables.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scope': scope.wire,
      'status': status.wire,
      'address': address,
      'workspaceId': workspaceId,
      'workspace': workspaceName == null ? null : {'id': workspaceId, 'name': workspaceName},
      'contactName': contactName,
      'contactPhone': contactPhone,
      'mapUrl': mapUrl,
      'latitude': latitude,
      'longitude': longitude,
      'generalNotes': generalNotes,
      'openTaskCount': openTaskCount,
      'lastVisit': lastVisit?.toJson(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'access': access?.toJson(),
      if (pending) 'pending': true,
    };
  }

  Site copyWith({
    String? name,
    SiteStatus? status,
    int? openTaskCount,
    VisitSummary? lastVisit,
    SiteAccess? access,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      scope: scope,
      status: status ?? this.status,
      address: address,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
      contactName: contactName,
      contactPhone: contactPhone,
      mapUrl: mapUrl,
      latitude: latitude,
      longitude: longitude,
      generalNotes: generalNotes,
      openTaskCount: openTaskCount ?? this.openTaskCount,
      lastVisit: lastVisit ?? this.lastVisit,
      createdAt: createdAt,
      updatedAt: updatedAt,
      access: access ?? this.access,
      pending: pending,
    );
  }
}

/// The lightweight visit shape embedded in site lists.
class VisitSummary {
  const VisitSummary({
    required this.id,
    required this.siteId,
    required this.visitDate,
    required this.completedWork,
    this.remainingWork,
    this.notes,
    this.createdByName,
  });

  final String id;
  final String siteId;
  final String visitDate;
  final String completedWork;
  final String? remainingWork;
  final String? notes;
  final String? createdByName;

  factory VisitSummary.fromJson(Map<String, dynamic> json) {
    final createdBy = asMap(json['createdBy']);
    return VisitSummary(
      id: asRequiredString(json['id']),
      siteId: asRequiredString(json['siteId']),
      visitDate: asDateOnly(json['visitDate']) ?? '',
      completedWork: asRequiredString(json['completedWork']),
      remainingWork: asString(json['remainingWork']),
      notes: asString(json['notes']),
      createdByName: asString(createdBy['name']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'siteId': siteId,
    'visitDate': visitDate,
    'completedWork': completedWork,
    'remainingWork': remainingWork,
    'notes': notes,
    'createdBy': createdByName == null ? null : {'name': createdByName},
  };
}
