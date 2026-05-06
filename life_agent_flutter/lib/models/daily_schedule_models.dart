import 'task_models.dart';

class PlanSummary {
  final String id;
  final String? title;
  final String? priority;
  final String? status;

  const PlanSummary({
    required this.id,
    this.title,
    this.priority,
    this.status,
  });

  factory PlanSummary.fromJson(Map<String, dynamic> json) {
    return PlanSummary(
      id: json['id'] as String,
      title: json['title'] as String?,
      priority: json['priority'] as String?,
      status: json['status'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'priority': priority,
      'status': status,
    };
  }
}

class MilestoneSummary {
  final String id;
  final String planId;
  final String title;
  final String status;
  final int orderIndex;

  const MilestoneSummary({
    required this.id,
    required this.planId,
    required this.title,
    required this.status,
    required this.orderIndex,
  });

  factory MilestoneSummary.fromJson(Map<String, dynamic> json) {
    return MilestoneSummary(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plan_id': planId,
      'title': title,
      'status': status,
      'order_index': orderIndex,
    };
  }
}

class DailySchedule {
  final String date;
  final List<TaskResponse> tasks;
  final int totalAvailable;
  final int selectedCount;
  final int maxTasksPerDay;
  final List<String> selectedTaskIds;
  final Map<String, PlanSummary> plansMetadata;
  final Map<String, MilestoneSummary> milestonesMetadata;
  final Map<String, dynamic> metadata;

  const DailySchedule({
    required this.date,
    required this.tasks,
    required this.totalAvailable,
    required this.selectedCount,
    required this.maxTasksPerDay,
    required this.selectedTaskIds,
    required this.plansMetadata,
    required this.milestonesMetadata,
    required this.metadata,
  });

  factory DailySchedule.empty() {
    return const DailySchedule(
      date: '',
      tasks: [],
      totalAvailable: 0,
      selectedCount: 0,
      maxTasksPerDay: 0,
      selectedTaskIds: [],
      plansMetadata: {},
      milestonesMetadata: {},
      metadata: {},
    );
  }

  factory DailySchedule.fromJson(Map<String, dynamic> json) {
    final plansRaw = Map<String, dynamic>.from(
      json['plans_metadata'] as Map? ?? const {},
    );
    final milestonesRaw = Map<String, dynamic>.from(
      json['milestones_metadata'] as Map? ?? const {},
    );

    return DailySchedule(
      date: json['date'] as String? ?? '',
      tasks: (json['tasks'] as List? ?? const [])
          .map((t) => TaskResponse.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      totalAvailable: json['total_available'] as int? ?? 0,
      selectedCount: json['selected_count'] as int? ?? 0,
      maxTasksPerDay: json['max_tasks_per_day'] as int? ?? 0,
      selectedTaskIds: (json['selected_task_ids'] as List? ?? const [])
          .map((id) => id.toString())
          .toList(),
      plansMetadata: plansRaw.map(
        (key, value) => MapEntry(
          key,
          PlanSummary.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      milestonesMetadata: milestonesRaw.map(
        (key, value) => MapEntry(
          key,
          MilestoneSummary.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'total_available': totalAvailable,
      'selected_count': selectedCount,
      'max_tasks_per_day': maxTasksPerDay,
      'selected_task_ids': selectedTaskIds,
      'plans_metadata': plansMetadata.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'milestones_metadata': milestonesMetadata.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'metadata': metadata,
    };
  }
}
