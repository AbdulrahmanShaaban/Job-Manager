import 'json.dart';

enum TaskStatus {
  open('OPEN', 'مفتوحة'),
  inProgress('IN_PROGRESS', 'شغّال عليها'),
  done('DONE', 'خلصت');

  const TaskStatus(this.wire, this.label);

  final String wire;
  final String label;

  bool get isOpen => this != TaskStatus.done;

  static TaskStatus fromWire(String? value) {
    return switch (value) {
      'DONE' => TaskStatus.done,
      'IN_PROGRESS' => TaskStatus.inProgress,
      _ => TaskStatus.open,
    };
  }
}

enum TaskPriority {
  low('LOW', 'منخفضة'),
  normal('NORMAL', 'عادية'),
  high('HIGH', 'مهمة');

  const TaskPriority(this.wire, this.label);

  final String wire;
  final String label;

  static TaskPriority fromWire(String? value) {
    return switch (value) {
      'HIGH' => TaskPriority.high,
      'LOW' => TaskPriority.low,
      _ => TaskPriority.normal,
    };
  }
}

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.siteId,
    this.siteName,
    this.siteScope,
    this.description,
    this.dueDate,
    this.completedAt,
    this.createdById,
    this.assigneeId,
    this.assigneeName,
    this.createdAt,
    this.updatedAt,
    this.pending = false,
  });

  final String id;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final String? siteId;
  final String? siteName;
  final String? siteScope;
  final String? description;
  final String? dueDate;
  final DateTime? completedAt;
  final String? createdById;
  final String? assigneeId;
  final String? assigneeName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True while the task is still queued for sync.
  final bool pending;

  bool get isOverdue {
    if (status == TaskStatus.done || dueDate == null) return false;
    final date = DateTime.tryParse(dueDate!);
    if (date == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return date.isBefore(today);
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    final site = asMap(json['site']);
    final assignee = asMap(json['assignee']);
    return Task(
      id: asRequiredString(json['id']),
      title: asRequiredString(json['title'], 'مهمة'),
      status: TaskStatus.fromWire(asString(json['status'])),
      priority: TaskPriority.fromWire(asString(json['priority'])),
      siteId: asString(json['siteId']),
      siteName: asString(site['name']),
      siteScope: asString(site['scope']),
      description: asString(json['description']),
      dueDate: asDateOnly(json['dueDate']),
      completedAt: asDateTime(json['completedAt']),
      createdById: asString(json['createdById']),
      assigneeId: asString(json['assigneeId']),
      assigneeName: asString(assignee['name']),
      createdAt: asDateTime(json['createdAt']),
      updatedAt: asDateTime(json['updatedAt']),
      pending: json['pending'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'status': status.wire,
      'priority': priority.wire,
      'siteId': siteId,
      'site': siteName == null ? null : {'id': siteId, 'name': siteName, 'scope': siteScope},
      'description': description,
      'dueDate': dueDate,
      'completedAt': completedAt?.toIso8601String(),
      'createdById': createdById,
      'assigneeId': assigneeId,
      'assignee': assigneeName == null ? null : {'id': assigneeId, 'name': assigneeName},
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      if (pending) 'pending': true,
    };
  }

  Task copyWith({TaskStatus? status, String? title, String? description, TaskPriority? priority}) {
    return Task(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      siteId: siteId,
      siteName: siteName,
      siteScope: siteScope,
      description: description ?? this.description,
      dueDate: dueDate,
      completedAt: completedAt,
      createdById: createdById,
      assigneeId: assigneeId,
      assigneeName: assigneeName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pending: pending,
    );
  }
}
