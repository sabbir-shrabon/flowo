import 'task_models.dart';

enum MilestoneStatus { locked, active, completed }

class MilestoneResponse {
  final String id;
  final String planId;
  final String userId;
  final String title;
  final String? description;
  final int orderIndex;
  final MilestoneStatus status;
  final int? suggestedDays;
  final String? outcome;
  final List<TaskResponse> tasks;
  final String createdAt;
  final String updatedAt;

  const MilestoneResponse({
    required this.id,
    required this.planId,
    required this.userId,
    required this.title,
    this.description,
    required this.orderIndex,
    required this.status,
    this.suggestedDays,
    this.outcome,
    required this.tasks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MilestoneResponse.fromJson(Map<String, dynamic> json) {
    return MilestoneResponse(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      orderIndex: json['order_index'] as int,
      status: MilestoneStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => MilestoneStatus.locked,
      ),
      suggestedDays: json['suggested_days'] as int?,
      outcome: json['outcome'] as String?,
      tasks: (json['tasks'] as List)
          .map((t) => TaskResponse.fromJson(t))
          .toList(),
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plan_id': planId,
      'user_id': userId,
      'title': title,
      'description': description,
      'order_index': orderIndex,
      'status': status.name,
      'suggested_days': suggestedDays,
      'outcome': outcome,
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class MilestoneInsightResponse {
  final String milestoneId;
  final Map<String, dynamic> insight;
  final String? raw;
  final bool generated;

  const MilestoneInsightResponse({
    required this.milestoneId,
    required this.insight,
    this.raw,
    required this.generated,
  });

  factory MilestoneInsightResponse.fromJson(Map<String, dynamic> json) {
    return MilestoneInsightResponse(
      milestoneId: json['milestone_id'] as String,
      insight: Map<String, dynamic>.from(json['insight'] as Map),
      raw: json['raw'] as String?,
      generated: json['generated'] as bool,
    );
  }
}

class CheckMilestoneCompletionResponse {
  final bool completed;
  final MilestoneResponse? milestone;
  final MilestoneResponse? nextMilestone;

  const CheckMilestoneCompletionResponse({
    required this.completed,
    this.milestone,
    this.nextMilestone,
  });

  factory CheckMilestoneCompletionResponse.fromJson(Map<String, dynamic> json) {
    return CheckMilestoneCompletionResponse(
      completed: json['completed'] as bool,
      milestone: json['milestone'] != null
          ? MilestoneResponse.fromJson(json['milestone'])
          : null,
      nextMilestone: json['next_milestone'] != null
          ? MilestoneResponse.fromJson(json['next_milestone'])
          : null,
    );
  }
}
