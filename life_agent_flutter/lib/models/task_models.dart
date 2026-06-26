enum TaskStatus { pending, done, skipped, partial }

enum TaskDifficulty { easy, intermediate, hard }

class TaskResponse {
  final String id;
  final String planId;
  final String title;
  final String? description;
  final String? dueDate;
  final TaskStatus status;
  final String priority;
  final TaskDifficulty difficulty;
  final String? parentId;
  final int carryOverCount;
  final String? milestoneId;
  final int orderIndex;
  final int taskIndex; // 1-based global position in plan roadmap
  final int subtaskCount;
  final int completedSubtaskCount;
  final bool hasSubtasks;
  final int? durationMinutes;
  final String createdAt;
  final String updatedAt;
  final Map<String, dynamic>? detailJson;
  final String? rescheduledFrom;
  final bool struggling;
  final String? skipReason;
  final String? skippedAt;

  const TaskResponse({
    required this.id,
    required this.planId,
    required this.title,
    this.description,
    this.dueDate,
    required this.status,
    required this.priority,
    required this.difficulty,
    this.parentId,
    required this.carryOverCount,
    this.milestoneId,
    required this.orderIndex,
    this.taskIndex = 0,
    this.subtaskCount = 0,
    this.completedSubtaskCount = 0,
    this.hasSubtasks = false,
    this.durationMinutes,
    required this.createdAt,
    required this.updatedAt,
    this.detailJson,
    this.rescheduledFrom,
    this.struggling = false,
    this.skipReason,
    this.skippedAt,
  });

  factory TaskResponse.fromJson(Map<String, dynamic> json) {
    return TaskResponse(
      id: json['id'] as String,
      planId: json['plan_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      dueDate: json['due_date'] as String?,
      status: TaskStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TaskStatus.pending,
      ),
      priority: json['priority'] as String? ?? 'medium',
      difficulty: TaskDifficulty.values.firstWhere(
        (e) => e.name == json['difficulty'],
        orElse: () => TaskDifficulty.intermediate,
      ),
      parentId: json['parent_id'] as String?,
      carryOverCount: json['carry_over_count'] as int? ?? 0,
      milestoneId: json['milestone_id'] as String?,
      orderIndex: json['order_index'] as int? ?? 0,
      taskIndex: json['task_index'] as int? ?? 0,
      subtaskCount: json['subtask_count'] as int? ?? 0,
      completedSubtaskCount: json['completed_subtask_count'] as int? ?? 0,
      hasSubtasks: json['has_subtasks'] as bool? ?? false,
      durationMinutes: json['duration_minutes'] as int?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
      detailJson: json['detail_json'] != null
          ? Map<String, dynamic>.from(json['detail_json'] as Map)
          : null,
      rescheduledFrom: json['rescheduled_from'] as String?,
      struggling: json['struggling'] as bool? ?? false,
      skipReason: json['skip_reason'] as String?,
      skippedAt: json['skipped_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'plan_id': planId,
      'title': title,
      'description': description,
      'due_date': dueDate,
      'status': status.name,
      'priority': priority,
      'difficulty': difficulty.name,
      'parent_id': parentId,
      'carry_over_count': carryOverCount,
      'milestone_id': milestoneId,
      'order_index': orderIndex,
      'task_index': taskIndex,
      'subtask_count': subtaskCount,
      'completed_subtask_count': completedSubtaskCount,
      'has_subtasks': hasSubtasks,
      'duration_minutes': durationMinutes,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'detail_json': detailJson,
      'rescheduled_from': rescheduledFrom,
      'struggling': struggling,
      'skip_reason': skipReason,
      'skipped_at': skippedAt,
    };
  }
}

class SubtaskResponse {
  final String id;
  final String taskId;
  final String title;
  final bool completed;
  final int orderIndex;
  final String createdAt;
  final String updatedAt;

  const SubtaskResponse({
    required this.id,
    required this.taskId,
    required this.title,
    this.completed = false,
    this.orderIndex = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SubtaskResponse.fromJson(Map<String, dynamic> json) {
    return SubtaskResponse(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool? ?? false,
      orderIndex: json['order_index'] as int? ?? 0,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task_id': taskId,
      'title': title,
      'completed': completed,
      'order_index': orderIndex,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class SubtaskSuggestion {
  final String title;

  const SubtaskSuggestion({required this.title});

  factory SubtaskSuggestion.fromJson(Map<String, dynamic> json) {
    return SubtaskSuggestion(title: json['title'] as String);
  }

  Map<String, dynamic> toJson() {
    return {'title': title};
  }
}

class GenerateSubtasksResponse {
  final List<SubtaskSuggestion> suggestions;

  const GenerateSubtasksResponse({required this.suggestions});

  factory GenerateSubtasksResponse.fromJson(Map<String, dynamic> json) {
    return GenerateSubtasksResponse(
      suggestions: (json['suggestions'] as List? ?? [])
          .map((s) => SubtaskSuggestion.fromJson(Map<String, dynamic>.from(s)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'suggestions': suggestions.map((s) => s.toJson()).toList()};
  }
}

class TaskWorkspaceResult {
  final String taskId;
  final bool isCompleted;
  final int subtaskCount;
  final int completedSubtaskCount;
  final bool hasSubtasks;

  const TaskWorkspaceResult({
    required this.taskId,
    required this.isCompleted,
    required this.subtaskCount,
    required this.completedSubtaskCount,
    required this.hasSubtasks,
  });

  factory TaskWorkspaceResult.fromJson(Map<String, dynamic> json) {
    return TaskWorkspaceResult(
      taskId: json['taskId'] as String,
      isCompleted: json['isCompleted'] as bool,
      subtaskCount: json['subtaskCount'] as int,
      completedSubtaskCount: json['completedSubtaskCount'] as int,
      hasSubtasks: json['hasSubtasks'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'isCompleted': isCompleted,
      'subtaskCount': subtaskCount,
      'completedSubtaskCount': completedSubtaskCount,
      'hasSubtasks': hasSubtasks,
    };
  }
}

class TaskUpdatePayload {
  final String taskId;
  final TaskStatus status;
  final String? feedbackText;

  const TaskUpdatePayload({
    required this.taskId,
    required this.status,
    this.feedbackText,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'task_id': taskId, 'status': status.name};
    if (feedbackText != null) map['feedback_text'] = feedbackText;
    return map;
  }
}

class TaskDetailResource {
  final String type;
  final String title;
  final String description;

  const TaskDetailResource({
    required this.type,
    required this.title,
    required this.description,
  });

  factory TaskDetailResource.fromJson(Map<String, dynamic> json) {
    return TaskDetailResource(
      type: json['type'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'type': type, 'title': title, 'description': description};
  }
}

class TaskDetailHowToStep {
  final int step;
  final String instruction;

  const TaskDetailHowToStep({required this.step, required this.instruction});

  factory TaskDetailHowToStep.fromJson(Map<String, dynamic> json) {
    return TaskDetailHowToStep(
      step: json['step'] as int,
      instruction: json['instruction'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'step': step, 'instruction': instruction};
  }
}

class TaskDetailData {
  final String whatIsThis;
  final String whyItMatters;
  final List<TaskDetailHowToStep> howToDoIt;
  final List<TaskDetailResource> resources;
  final String todaysExample;
  final String expertTip;
  final String estimatedDifficulty;

  const TaskDetailData({
    required this.whatIsThis,
    required this.whyItMatters,
    required this.howToDoIt,
    required this.resources,
    required this.todaysExample,
    required this.expertTip,
    required this.estimatedDifficulty,
  });

  factory TaskDetailData.fromJson(Map<String, dynamic> json) {
    return TaskDetailData(
      whatIsThis: (json['what_is_this'] as String?) ?? '',
      whyItMatters: (json['why_it_matters'] as String?) ?? '',
      howToDoIt: (json['how_to_do_it'] as List? ?? [])
          .map((s) => TaskDetailHowToStep.fromJson(s))
          .toList(),
      resources: (json['resources'] as List? ?? [])
          .map((r) => TaskDetailResource.fromJson(r))
          .toList(),
      todaysExample: (json['todays_example'] as String?) ?? '',
      expertTip: (json['expert_tip'] as String?) ?? '',
      estimatedDifficulty:
          (json['estimated_difficulty'] as String?) ?? 'medium',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'what_is_this': whatIsThis,
      'why_it_matters': whyItMatters,
      'how_to_do_it': howToDoIt.map((e) => e.toJson()).toList(),
      'resources': resources.map((e) => e.toJson()).toList(),
      'todays_example': todaysExample,
      'expert_tip': expertTip,
      'estimated_difficulty': estimatedDifficulty,
    };
  }
}

class TaskDetailResponse {
  final String taskId;
  final TaskDetailData detail;
  final bool generated;

  const TaskDetailResponse({
    required this.taskId,
    required this.detail,
    required this.generated,
  });

  factory TaskDetailResponse.fromJson(Map<String, dynamic> json) {
    return TaskDetailResponse(
      taskId: json['task_id'] as String,
      detail: TaskDetailData.fromJson(json['detail']),
      generated: json['generated'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'task_id': taskId,
      'detail': detail.toJson(),
      'generated': generated,
    };
  }
}
