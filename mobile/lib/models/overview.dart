import 'json.dart';
import 'site.dart';
import 'task.dart';
import 'visit.dart';
import 'user.dart';

class OverviewCounts {
  const OverviewCounts({
    this.personalSites = 0,
    this.companySites = 0,
    this.todayVisits = 0,
    this.openTasks = 0,
  });

  final int personalSites;
  final int companySites;
  final int todayVisits;
  final int openTasks;

  factory OverviewCounts.fromJson(Map<String, dynamic> json) {
    return OverviewCounts(
      personalSites: asInt(json['personalSites']),
      companySites: asInt(json['companySites']),
      todayVisits: asInt(json['todayVisits']),
      openTasks: asInt(json['openTasks']),
    );
  }

  Map<String, dynamic> toJson() => {
    'personalSites': personalSites,
    'companySites': companySites,
    'todayVisits': todayVisits,
    'openTasks': openTasks,
  };
}

class Overview {
  const Overview({
    required this.today,
    required this.counts,
    required this.recentSites,
    required this.todayVisits,
    required this.upcomingTasks,
    required this.workspaces,
  });

  final String today;
  final OverviewCounts counts;
  final List<Site> recentSites;
  final List<Visit> todayVisits;
  final List<Task> upcomingTasks;
  final List<Workspace> workspaces;

  factory Overview.fromJson(Map<String, dynamic> json) {
    return Overview(
      today: asDateOnly(json['today']) ?? '',
      counts: OverviewCounts.fromJson(asMap(json['counts'])),
      recentSites: asMapList(json['recentSites']).map(Site.fromJson).toList(growable: false),
      todayVisits: asMapList(json['todayVisits']).map(Visit.fromJson).toList(growable: false),
      upcomingTasks: asMapList(json['upcomingTasks']).map(Task.fromJson).toList(growable: false),
      workspaces: asMapList(json['workspaces']).map(Workspace.fromJson).toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'today': today,
    'counts': counts.toJson(),
    'recentSites': recentSites.map((site) => site.toJson()).toList(),
    'todayVisits': todayVisits.map((visit) => visit.toJson()).toList(),
    'upcomingTasks': upcomingTasks.map((task) => task.toJson()).toList(),
    'workspaces': workspaces.map((workspace) => workspace.toJson()).toList(),
  };
}

/// A site plus its live task list and visit history, as returned by
/// `GET /sites/:id`.
class SiteDetail {
  const SiteDetail({required this.site, required this.tasks, required this.visits, this.access});

  final Site site;
  final List<Task> tasks;
  final List<Visit> visits;
  final SiteAccess? access;

  List<Task> get openTasks => tasks.where((task) => task.status.isOpen).toList(growable: false);
  List<Task> get doneTasks => tasks.where((task) => task.status == TaskStatus.done).toList(growable: false);

  factory SiteDetail.fromJson(Map<String, dynamic> json) {
    final siteJson = asMap(json['site']);
    final accessJson = asMap(json['access']);
    return SiteDetail(
      site: Site.fromJson(siteJson).copyWith(
        access: accessJson.isEmpty ? null : SiteAccess.fromJson(accessJson),
      ),
      tasks: asMapList(siteJson['tasks']).map(Task.fromJson).toList(growable: false),
      visits: asMapList(siteJson['visits']).map(Visit.fromJson).toList(growable: false),
      access: accessJson.isEmpty ? null : SiteAccess.fromJson(accessJson),
    );
  }
}
