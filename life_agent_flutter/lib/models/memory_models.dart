import 'plan_models.dart' show PlanResponse;
import 'milestone_models.dart' show MilestoneResponse;
import 'chat_models.dart' show ExtractedPlanFields;

enum MemoryKey { goal, constraint, preference, context, milestone }

class MemoryResponse {
  final String id;
  final String userId;
  final MemoryKey key;
  final String value;
  final String source;
  final String? goalId;
  final String createdAt;
  final String updatedAt;

  const MemoryResponse({
    required this.id,
    required this.userId,
    required this.key,
    required this.value,
    required this.source,
    this.goalId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MemoryResponse.fromJson(Map<String, dynamic> json) {
    return MemoryResponse(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      key: MemoryKey.values.firstWhere(
        (e) => e.name == json['key'],
        orElse: () => MemoryKey.context,
      ),
      value: json['value'] as String,
      source: json['source'] as String,
      goalId: json['goal_id'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

class ExtractMemoryPayload {
  final String conversation;

  const ExtractMemoryPayload({required this.conversation});

  Map<String, dynamic> toJson() => {'conversation': conversation};
}

class ExtractMemoryResponse {
  final List<ExtractedField> extracted;
  final int count;

  const ExtractMemoryResponse({required this.extracted, required this.count});

  factory ExtractMemoryResponse.fromJson(Map<String, dynamic> json) {
    return ExtractMemoryResponse(
      extracted: (json['extracted'] as List)
          .map((e) => ExtractedField.fromJson(e))
          .toList(),
      count: json['count'] as int,
    );
  }
}

class ExtractedField {
  final String key;
  final String value;
  final String? id;

  const ExtractedField({required this.key, required this.value, this.id});

  factory ExtractedField.fromJson(Map<String, dynamic> json) {
    return ExtractedField(
      key: json['key'] as String,
      value: json['value'] as String,
      id: json['id'] as String?,
    );
  }
}

class MissingField {
  final String field;
  final String question;

  const MissingField({required this.field, required this.question});

  factory MissingField.fromJson(Map<String, dynamic> json) {
    return MissingField(
      field: json['field'] as String,
      question: json['question'] as String,
    );
  }
}

class GenerateFromChatPayload {
  final String learningGoal;
  final String focusArea;
  final String skillLevel;
  final String focusOrAvoid;
  final String extraContext;

  const GenerateFromChatPayload({
    required this.learningGoal,
    required this.focusArea,
    required this.skillLevel,
    this.focusOrAvoid = '',
    this.extraContext = '',
  });

  factory GenerateFromChatPayload.fromFields(
    ExtractedPlanFields extracted,
    Map<String, String> userAnswers,
  ) {
    return GenerateFromChatPayload(
      learningGoal:
          userAnswers['learning_goal'] ?? extracted.learningGoal ?? '',
      focusArea: userAnswers['focus_area'] ?? extracted.focusArea ?? '',
      skillLevel: userAnswers['skill_level'] ?? extracted.skillLevel ?? '',
      focusOrAvoid:
          userAnswers['focus_or_avoid'] ?? extracted.focusOrAvoid ?? '',
      extraContext:
          userAnswers['extra_context'] ?? extracted.extraContext ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'learning_goal': learningGoal,
    'focus_area': focusArea,
    'skill_level': skillLevel,
    'focus_or_avoid': focusOrAvoid,
    'extra_context': extraContext,
  };
}

class GenerateFromChatResponse {
  final bool ready;
  final List<MissingField> missingFields;
  final String message;
  final PlanResponse? plan;
  final List<MilestoneResponse> milestones;
  final int taskCount;

  const GenerateFromChatResponse({
    required this.ready,
    this.missingFields = const [],
    this.message = '',
    this.plan,
    this.milestones = const [],
    this.taskCount = 0,
  });

  factory GenerateFromChatResponse.fromJson(Map<String, dynamic> json) {
    return GenerateFromChatResponse(
      ready: json['ready'] as bool,
      missingFields:
          (json['missing_fields'] as List?)
              ?.map((f) => MissingField.fromJson(f))
              .toList() ??
          [],
      message: json['message'] as String? ?? '',
      plan: json['plan'] != null
          ? PlanResponse.fromJson(json['plan'] as Map<String, dynamic>)
          : null,
      milestones:
          (json['milestones'] as List?)
              ?.map((m) => MilestoneResponse.fromJson(m))
              .toList() ??
          [],
      taskCount: json['task_count'] as int? ?? 0,
    );
  }
}
