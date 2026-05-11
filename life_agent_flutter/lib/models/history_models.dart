// Task completion history models for the History Screen.

class TaskHistoryResponse {
  final String id;
  final String userId;
  final String taskId;
  final int taskIndex; // 1-based position in the plan roadmap
  final String taskName;
  final String? milestoneId;
  final String? milestoneName;
  final String planId;
  final String planName;
  final bool planCompleted;
  final int? workingDayIndex;
  final String calendarDate;
  final String completedAt;
  final String createdAt;

  const TaskHistoryResponse({
    required this.id,
    required this.userId,
    required this.taskId,
    required this.taskIndex,
    required this.taskName,
    this.milestoneId,
    this.milestoneName,
    required this.planId,
    required this.planName,
    this.planCompleted = false,
    this.workingDayIndex,
    required this.calendarDate,
    required this.completedAt,
    required this.createdAt,
  });

  factory TaskHistoryResponse.fromJson(Map<String, dynamic> json) {
    return TaskHistoryResponse(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      taskId: json['task_id'] as String,
      taskIndex: json['task_index'] as int? ?? 0,
      taskName: json['task_name'] as String,
      milestoneId: json['milestone_id'] as String?,
      milestoneName: json['milestone_name'] as String?,
      planId: json['plan_id'] as String,
      planName: json['plan_name'] as String,
      planCompleted: json['plan_completed'] as bool? ?? false,
      workingDayIndex: json['working_day_index'] as int?,
      calendarDate: json['calendar_date'] as String,
      completedAt: json['completed_at'] as String,
      createdAt: json['created_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'task_id': taskId,
      'task_index': taskIndex,
      'task_name': taskName,
      'milestone_id': milestoneId,
      'milestone_name': milestoneName,
      'plan_id': planId,
      'plan_name': planName,
      'plan_completed': planCompleted,
      'working_day_index': workingDayIndex,
      'calendar_date': calendarDate,
      'completed_at': completedAt,
      'created_at': createdAt,
    };
  }
}

class TaskHistoryListResponse {
  final List<TaskHistoryResponse> history;
  final int total;

  const TaskHistoryListResponse({required this.history, required this.total});

  factory TaskHistoryListResponse.fromJson(Map<String, dynamic> json) {
    return TaskHistoryListResponse(
      history: (json['history'] as List? ?? [])
          .map((h) => TaskHistoryResponse.fromJson(h))
          .toList(),
      total: json['total'] as int? ?? 0,
    );
  }
}

/// A group of history entries for a single plan.
class HistoryPlanGroup {
  final String planId;
  final String planName;
  final bool planCompleted;
  final List<HistoryDateGroup> dateGroups;
  final DateTime mostRecentCompletion;

  const HistoryPlanGroup({
    required this.planId,
    required this.planName,
    required this.planCompleted,
    required this.dateGroups,
    required this.mostRecentCompletion,
  });
}

/// A group of history entries for a single date within a plan.
class HistoryDateGroup {
  final String dateLabel; // "Today", "Yesterday", or actual date string
  final String calendarDate;
  final List<TaskHistoryResponse> entries;

  const HistoryDateGroup({
    required this.dateLabel,
    required this.calendarDate,
    required this.entries,
  });
}
