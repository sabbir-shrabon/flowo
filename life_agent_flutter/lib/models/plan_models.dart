import 'milestone_models.dart';

enum PlanStatus { setup, active, paused, completed }

enum PlanPriority { high, medium, low }

enum PlanIntensity { light, moderate, intense }

class PlanResponse {
  final String id;
  final String? goalId;
  final String? memoryId;
  final String? userId;
  final String? title;
  final PlanStatus status;
  final PlanPriority priority;
  final PlanIntensity intensity;
  final int? durationDays;
  final Map<String, dynamic>? schedulePrefs;
  final double progressPct;
  final int totalTasks;
  final int remainingTasks;
  final String createdAt;
  final String updatedAt;

  const PlanResponse({
    required this.id,
    this.goalId,
    this.memoryId,
    this.userId,
    this.title,
    required this.status,
    required this.priority,
    required this.intensity,
    this.durationDays,
    this.schedulePrefs,
    this.progressPct = 0.0,
    this.totalTasks = 0,
    this.remainingTasks = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlanResponse.fromJson(Map<String, dynamic> json) {
    return PlanResponse(
      id: json['id'] as String,
      goalId: json['goal_id'] as String?,
      memoryId: json['memory_id'] as String?,
      userId: json['user_id'] as String?,
      title: json['title'] as String?,
      status: PlanStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PlanStatus.setup,
      ),
      priority: PlanPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => PlanPriority.medium,
      ),
      intensity: PlanIntensity.values.firstWhere(
        (e) => e.name == json['intensity'],
        orElse: () => PlanIntensity.moderate,
      ),
      durationDays: json['duration_days'] as int?,
      schedulePrefs: json['schedule_prefs'] != null
          ? Map<String, dynamic>.from(json['schedule_prefs'] as Map)
          : null,
      progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
      totalTasks: (json['total_tasks'] as num?)?.toInt() ?? 0,
      remainingTasks: (json['remaining_tasks'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'goal_id': goalId,
      'memory_id': memoryId,
      'user_id': userId,
      'title': title,
      'status': status.name,
      'priority': priority.name,
      'intensity': intensity.name,
      'duration_days': durationDays,
      'schedule_prefs': schedulePrefs,
      'progress_pct': progressPct,
      'total_tasks': totalTasks,
      'remaining_tasks': remainingTasks,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Convenience getters for plan dates stored in schedule_prefs.

  /// The date when the user adapted this plan (start_date in schedule_prefs).
  DateTime? get startDate {
    final raw = schedulePrefs?['start_date'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// The calculated ending date for the plan.
  /// Uses explicit end_date from schedule_prefs if present,
  /// otherwise computes start_date + duration_days as fallback.
  DateTime? get endDate {
    final raw = schedulePrefs?['end_date'];
    if (raw is String) return DateTime.tryParse(raw);
    // Fallback: compute from start_date + duration_days
    final start = startDate;
    if (start != null && durationDays != null && durationDays! > 0) {
      return start.add(Duration(days: durationDays! - 1));
    }
    return null;
  }
}

class PlanDetailStats {
  final int totalTasks;
  final int completedTasks;
  final int remainingTasks;
  final int totalMilestones;
  final int completedMilestones;
  final double progressPct;
  final MilestoneRef? currentMilestone;
  final MilestoneRef? nextMilestone;
  final TaskRef? nextTask;

  const PlanDetailStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.remainingTasks,
    required this.totalMilestones,
    required this.completedMilestones,
    required this.progressPct,
    this.currentMilestone,
    this.nextMilestone,
    this.nextTask,
  });

  factory PlanDetailStats.fromJson(Map<String, dynamic> json) {
    return PlanDetailStats(
      totalTasks: json['total_tasks'] as int,
      completedTasks: json['completed_tasks'] as int,
      remainingTasks: json['remaining_tasks'] as int,
      totalMilestones: json['total_milestones'] as int,
      completedMilestones: json['completed_milestones'] as int,
      progressPct: (json['progress_pct'] as num?)?.toDouble() ?? 0.0,
      currentMilestone: json['current_milestone'] != null
          ? MilestoneRef.fromJson(json['current_milestone'])
          : null,
      nextMilestone: json['next_milestone'] != null
          ? MilestoneRef.fromJson(json['next_milestone'])
          : null,
      nextTask: json['next_task'] != null
          ? TaskRef.fromJson(json['next_task'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_tasks': totalTasks,
      'completed_tasks': completedTasks,
      'remaining_tasks': remainingTasks,
      'total_milestones': totalMilestones,
      'completed_milestones': completedMilestones,
      'progress_pct': progressPct,
      'current_milestone': currentMilestone?.toJson(),
      'next_milestone': nextMilestone?.toJson(),
      'next_task': nextTask?.toJson(),
    };
  }
}

class MilestoneRef {
  final String id;
  final String title;
  final int orderIndex;

  const MilestoneRef({
    required this.id,
    required this.title,
    required this.orderIndex,
  });

  factory MilestoneRef.fromJson(Map<String, dynamic> json) {
    return MilestoneRef(
      id: json['id'] as String,
      title: json['title'] as String,
      orderIndex: json['order_index'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'title': title, 'order_index': orderIndex};
  }
}

class TaskRef {
  final String id;
  final String title;
  final String? milestoneId;

  const TaskRef({required this.id, required this.title, this.milestoneId});

  factory TaskRef.fromJson(Map<String, dynamic> json) {
    return TaskRef(
      id: json['id'] as String,
      title: json['title'] as String,
      milestoneId: json['milestone_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'title': title, 'milestone_id': milestoneId};
  }
}

class PlanDetailResponse {
  final PlanResponse plan;
  final PlanDetailStats stats;
  final List<MilestoneResponse> milestones;

  const PlanDetailResponse({
    required this.plan,
    required this.stats,
    required this.milestones,
  });

  factory PlanDetailResponse.fromJson(Map<String, dynamic> json) {
    return PlanDetailResponse(
      plan: PlanResponse.fromJson(json['plan']),
      stats: PlanDetailStats.fromJson(json['stats']),
      milestones: (json['milestones'] as List)
          .map((m) => MilestoneResponse.fromJson(m))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plan': plan.toJson(),
      'stats': stats.toJson(),
      'milestones': milestones.map((m) => m.toJson()).toList(),
    };
  }
}

class CreatePlanResponse {
  final PlanResponse plan;
  final List<MilestoneResponse> milestones;
  final int taskCount;

  const CreatePlanResponse({
    required this.plan,
    required this.milestones,
    required this.taskCount,
  });

  factory CreatePlanResponse.fromJson(Map<String, dynamic> json) {
    return CreatePlanResponse(
      plan: PlanResponse.fromJson(json['plan']),
      milestones: (json['milestones'] as List)
          .map((m) => MilestoneResponse.fromJson(m))
          .toList(),
      taskCount: json['task_count'] as int,
    );
  }
}

class PlanUpdatePayload {
  final PlanStatus? status;
  final PlanPriority? priority;
  final String? title;
  final PlanIntensity? intensity;

  const PlanUpdatePayload({
    this.status,
    this.priority,
    this.title,
    this.intensity,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (status != null) map['status'] = status!.name;
    if (priority != null) map['priority'] = priority!.name;
    if (title != null) map['title'] = title;
    if (intensity != null) map['intensity'] = intensity!.name;
    return map;
  }
}

class PlanChatAction {
  final String action;
  final String? targetId;
  final Map<String, dynamic> params;

  const PlanChatAction({
    required this.action,
    this.targetId,
    required this.params,
  });

  factory PlanChatAction.fromJson(Map<String, dynamic> json) {
    return PlanChatAction(
      action: json['action'] as String,
      targetId: json['target_id'] as String?,
      params: Map<String, dynamic>.from(json['params'] as Map),
    );
  }
}

class PlanChatResponse {
  final String reply;
  final List<PlanChatAction> actions;

  const PlanChatResponse({required this.reply, required this.actions});

  factory PlanChatResponse.fromJson(Map<String, dynamic> json) {
    return PlanChatResponse(
      reply: json['reply'] as String,
      actions: (json['actions'] as List)
          .map((a) => PlanChatAction.fromJson(a))
          .toList(),
    );
  }
}
