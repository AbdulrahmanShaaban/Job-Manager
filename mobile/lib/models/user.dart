import 'json.dart';

class AppUser {
  const AppUser({required this.id, required this.name, required this.email});

  final String id;
  final String name;
  final String email;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: asRequiredString(json['id']),
      name: asRequiredString(json['name'], 'مستخدم'),
      email: asRequiredString(json['email']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email};
}

class Workspace {
  const Workspace({
    required this.id,
    required this.name,
    this.role,
    this.memberCount,
    this.siteCount,
  });

  final String id;
  final String name;
  final String? role;
  final int? memberCount;
  final int? siteCount;

  bool get canWrite => role == 'OWNER' || role == 'ADMIN' || role == 'EDITOR';
  bool get canManage => role == 'OWNER' || role == 'ADMIN';

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: asRequiredString(json['id']),
      name: asRequiredString(json['name'], 'شركة'),
      role: asString(json['role']),
      memberCount: json['memberCount'] == null ? null : asInt(json['memberCount']),
      siteCount: json['siteCount'] == null ? null : asInt(json['siteCount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (role != null) 'role': role,
    if (memberCount != null) 'memberCount': memberCount,
    if (siteCount != null) 'siteCount': siteCount,
  };
}

/// Result of `POST /auth/login` and `POST /auth/accept-invitation`.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.user,
    required this.workspaces,
    this.expiresAt,
  });

  final String token;
  final AppUser user;
  final List<Workspace> workspaces;
  final DateTime? expiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: asRequiredString(json['token']),
      user: AppUser.fromJson(asMap(json['user'])),
      workspaces: asMapList(
        json['workspaces'],
      ).map(Workspace.fromJson).toList(growable: false),
      expiresAt: asDateTime(json['expiresAt']),
    );
  }
}
