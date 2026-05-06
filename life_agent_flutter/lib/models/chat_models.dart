class ChatMessage {
  final String id;
  final String role; // "user" | "assistant"
  final String content;
  final DateTime? createdAt;
  final List<ExtractedMemory>? extractedMemory;
  final List<ChatAction>? actions;
  final String? mentionedPlan;
  /// When non-null, this bubble renders an inline MCQ card instead of plain text.
  final List<PlanFieldQuestion>? planFieldQuestions;
  /// Pre-extracted field values carried alongside the MCQ questions.
  final ExtractedPlanFields? extractedPlanFields;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.extractedMemory,
    this.actions,
    this.mentionedPlan,
    this.planFieldQuestions,
    this.extractedPlanFields,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      extractedMemory: json['extracted_memory'] != null
          ? (json['extracted_memory'] as List)
                .map((m) => ExtractedMemory.fromJson(m))
                .toList()
          : null,
      actions: json['actions'] != null
          ? (json['actions'] as List)
                .map((a) => ChatAction.fromJson(a))
                .toList()
          : null,
      mentionedPlan: json['mentioned_plan'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (extractedMemory != null)
        'extracted_memory': extractedMemory!.map((m) => m.toJson()).toList(),
      if (actions != null) 'actions': actions!.map((a) => a.toJson()).toList(),
      if (mentionedPlan != null) 'mentioned_plan': mentionedPlan,
    };
  }
}

// ── Plan Field MCQ Models ──────────────────────────────────────────────────────

/// Describes one field that must be answered (maps to a wizard question).
class PlanFieldQuestion {
  final String field; // e.g. "learning_goal"
  final String question; // Human-readable question
  final List<String>? chips; // Chip options (null = free text)
  final String? textHint;

  const PlanFieldQuestion({
    required this.field,
    required this.question,
    this.chips,
    this.textHint,
  });
}

/// Holds the 5 wizard field values (some may be null if not yet answered).
class ExtractedPlanFields {
  final String? learningGoal;
  final String? focusArea;
  final String? skillLevel;
  final String? focusOrAvoid;
  final String? extraContext;

  const ExtractedPlanFields({
    this.learningGoal,
    this.focusArea,
    this.skillLevel,
    this.focusOrAvoid,
    this.extraContext,
  });

  ExtractedPlanFields copyWith({
    String? learningGoal,
    String? focusArea,
    String? skillLevel,
    String? focusOrAvoid,
    String? extraContext,
  }) {
    return ExtractedPlanFields(
      learningGoal: learningGoal ?? this.learningGoal,
      focusArea: focusArea ?? this.focusArea,
      skillLevel: skillLevel ?? this.skillLevel,
      focusOrAvoid: focusOrAvoid ?? this.focusOrAvoid,
      extraContext: extraContext ?? this.extraContext,
    );
  }

  Map<String, String> toApiJson() => {
    'learning_goal': learningGoal ?? '',
    'focus_area': focusArea ?? '',
    'skill_level': skillLevel ?? '',
    'focus_or_avoid': focusOrAvoid ?? '',
    'extra_context': extraContext ?? '',
  };
}

/// Phase-1 response from /plans/extract-from-chat.
class ExtractFromChatResponse {
  final ExtractedPlanFields extracted;
  final List<PlanFieldQuestion> missingFields;
  final bool ready;

  const ExtractFromChatResponse({
    required this.extracted,
    required this.missingFields,
    required this.ready,
  });

  factory ExtractFromChatResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['extracted'] as Map<String, dynamic>? ?? {};
    final extracted = ExtractedPlanFields(
      learningGoal: raw['learning_goal'] as String?,
      focusArea: raw['focus_area'] as String?,
      skillLevel: raw['skill_level'] as String?,
      focusOrAvoid: raw['focus_or_avoid'] as String?,
      extraContext: raw['extra_context'] as String?,
    );
    final missingRaw = json['missing_fields'] as List? ?? [];
    final missingFields = missingRaw.map((m) {
      final map = m as Map<String, dynamic>;
      final field = map['field'] as String;
      return PlanFieldQuestion(
        field: field,
        question: map['question'] as String,
        chips: _chipsForField(field),
        textHint: _hintForField(field),
      );
    }).toList();
    return ExtractFromChatResponse(
      extracted: extracted,
      missingFields: missingFields,
      ready: json['ready'] as bool? ?? false,
    );
  }

  static List<String>? _chipsForField(String field) {
    switch (field) {
      case 'learning_goal':
        return [
          'Get a Job',
          'Grow in my current role',
          'Build Projects / Side Hustles',
          'Strengthen Fundamentals',
          'Explore a New Field',
        ];
      case 'skill_level':
        return [
          'Beginner (just starting out)',
          'Intermediate (some hands-on experience)',
          'Advanced (comfortable, want to go deeper)',
        ];
      default:
        return null;
    }
  }

  static String? _hintForField(String field) {
    switch (field) {
      case 'focus_area':
        return 'e.g. I know intermediate Python and want to focus on ML engineering';
      case 'focus_or_avoid':
        return 'Optional — e.g. focus on vanilla JS, avoid frameworks';
      case 'extra_context':
        return 'Optional — any additional background about your goals';
      default:
        return null;
    }
  }
}

class ExtractedMemory {
  final String key;
  final String value;
  final String? id;

  const ExtractedMemory({required this.key, required this.value, this.id});

  factory ExtractedMemory.fromJson(Map<String, dynamic> json) {
    return ExtractedMemory(
      key: json['key'] as String,
      value: json['value'] as String,
      id: json['id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    if (id != null) 'id': id,
  };
}

class ChatAction {
  final String action;
  final String? targetId;
  final Map<String, dynamic>? params;

  const ChatAction({required this.action, this.targetId, this.params});

  factory ChatAction.fromJson(Map<String, dynamic> json) {
    return ChatAction(
      action: json['action'] as String,
      targetId: json['target_id'] as String?,
      params: json['params'] != null
          ? Map<String, dynamic>.from(json['params'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'action': action,
    if (targetId != null) 'target_id': targetId,
    if (params != null) 'params': params,
  };
}

class SessionContext {
  final String activeTab; // "today" | "chat"
  final String? openPlanId;
  final String? openMilestoneId;
  final String? openTaskId;

  const SessionContext({
    required this.activeTab,
    this.openPlanId,
    this.openMilestoneId,
    this.openTaskId,
  });

  Map<String, dynamic> toJson() => {
    'active_tab': activeTab,
    if (openPlanId != null) 'open_plan_id': openPlanId,
    if (openMilestoneId != null) 'open_milestone_id': openMilestoneId,
    if (openTaskId != null) 'open_task_id': openTaskId,
  };
}

class ConversationSummary {
  final String id;
  final String title;
  final String? preview;
  final int? messageCount;
  final bool? archived;
  final String? updatedAt;
  final String? createdAt;

  const ConversationSummary({
    required this.id,
    required this.title,
    this.preview,
    this.messageCount,
    this.archived,
    this.updatedAt,
    this.createdAt,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      preview: json['preview'] as String?,
      messageCount: json['message_count'] as int?,
      archived: json['archived'] as bool?,
      updatedAt: json['updated_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

class ConversationDetail {
  final String id;
  final String title;
  final List<ChatMessage> messages;

  const ConversationDetail({
    required this.id,
    required this.title,
    required this.messages,
  });

  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    return ConversationDetail(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List).map((m) {
        final map = m as Map<String, dynamic>;
        // Backend ConversationMessage has: id, role, content, isPlan, originalUserMsg, convertedToRoadmap, created_at
        // Convert to ChatMessage format
        return ChatMessage(
          id: map['id'] as String? ?? '',
          role: map['role'] as String? ?? 'assistant',
          content: map['content'] as String? ?? '',
          createdAt: map['created_at'] != null
              ? DateTime.tryParse(map['created_at'] as String)
              : null,
        );
      }).toList(),
    );
  }
}
