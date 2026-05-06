import '../models/task_models.dart';
import '../models/plan_models.dart';
import '../models/milestone_models.dart';
import '../models/daily_schedule_models.dart';
import '../models/memory_models.dart';
import '../models/chat_models.dart';
import 'api_service.dart';

final _api = ApiService();

// ── Tasks ──────────────────────────────────────────────────────────────────────

Future<List<TaskResponse>> getTodayTasks() async {
  final data = await _api.getJson('/api/adaptive/tasks/today');
  return (data as List).map((t) => TaskResponse.fromJson(t)).toList();
}

Future<List<TaskResponse>> getTodayTasksV2() async {
  final data = await _api.getJson('/api/adaptive/tasks/today/v2');
  return (data as List).map((t) => TaskResponse.fromJson(t)).toList();
}

Future<DailySchedule> getDailySchedule() async {
  final data = await _api.getJson('/api/adaptive/scheduler/daily');
  return DailySchedule.fromJson(data as Map<String, dynamic>);
}

Future<DailySchedule> pullExtraDailyTasks(int count) async {
  final data = await _api.postJson('/api/adaptive/scheduler/daily/pull-extra', {
    'count': count,
  });
  return DailySchedule.fromJson(data as Map<String, dynamic>);
}

Future<TaskResponse> updateTask(TaskUpdatePayload payload) async {
  final data = await _api.postJson(
    '/api/adaptive/tasks/update',
    payload.toJson(),
  );
  return TaskResponse.fromJson(data);
}

Future<List<TaskResponse>> markDayBusy() async {
  final data = await _api.postJson('/api/adaptive/tasks/busy', {});
  return (data as List).map((t) => TaskResponse.fromJson(t)).toList();
}

Future<TaskDetailResponse> getTaskDetail(String taskId) async {
  final data = await _api.getJson('/api/adaptive/tasks/$taskId/detail');
  return TaskDetailResponse.fromJson(data);
}

// ── Plans ──────────────────────────────────────────────────────────────────────

Future<List<PlanResponse>> listActivePlans() async {
  final data = await _api.getJson('/api/adaptive/plans');
  return (data as List).map((p) => PlanResponse.fromJson(p)).toList();
}

Future<List<PlanResponse>> listAllPlans() async {
  final data = await _api.getJson('/api/adaptive/plans/all');
  return (data as List).map((p) => PlanResponse.fromJson(p)).toList();
}

Future<PlanResponse> pausePlan(String planId) async {
  final data = await _api.postJson('/api/adaptive/plan/pause', {
    'plan_id': planId,
  });
  return PlanResponse.fromJson(data);
}

Future<PlanResponse> resumePlan(String planId) async {
  final data = await _api.postJson('/api/adaptive/plan/resume', {
    'plan_id': planId,
  });
  return PlanResponse.fromJson(data);
}

Future<PlanResponse> patchPlan(String planId, PlanUpdatePayload payload) async {
  final data = await _api.patchJson(
    '/api/adaptive/plans/$planId',
    payload.toJson(),
  );
  return PlanResponse.fromJson(data);
}

Future<PlanResponse> adaptPlan(
  String planId, {
  required int durationDays,
  required List<int> workingDays,
}) async {
  final data = await _api.postJson('/api/adaptive/plans/$planId/adapt', {
    'duration_days': durationDays,
    'working_days': workingDays,
  });
  return PlanResponse.fromJson(data);
}

Future<Map<String, dynamic>> deletePlan(String planId) async {
  final data = await _api.delete('/api/adaptive/plans/$planId');
  return data as Map<String, dynamic>;
}

Future<PlanDetailResponse> getPlanDetail(String planId) async {
  final data = await _api.getJson('/api/adaptive/plans/$planId/detail');
  return PlanDetailResponse.fromJson(data);
}

Future<PlanDetailResponse> getPlanDetailV2(String planId) async {
  final data = await _api.getJson('/api/adaptive/plans/$planId/detail/v2');
  return PlanDetailResponse.fromJson(data);
}

Future<PlanChatResponse> sendPlanChat(
  String planId,
  String message, {
  String? taskId,
}) async {
  final body = <String, dynamic>{'message': message};
  if (taskId != null) body['task_id'] = taskId;
  final data = await _api.postJson('/api/adaptive/plans/$planId/chat', body);
  return PlanChatResponse.fromJson(data);
}

Future<PlanChatResponse> sendTodayChat(String message, {String? taskId}) async {
  final body = <String, dynamic>{'message': message};
  if (taskId != null) body['task_id'] = taskId;
  final data = await _api.postJson('/api/adaptive/today/chat', body);
  return PlanChatResponse.fromJson(data);
}

// ── Milestones ─────────────────────────────────────────────────────────────────

Future<List<MilestoneResponse>> getPlanMilestones(String planId) async {
  final data = await _api.getJson('/api/adaptive/plans/$planId/milestones');
  return (data as List).map((m) => MilestoneResponse.fromJson(m)).toList();
}

Future<MilestoneInsightResponse> getMilestoneInsight(String milestoneId) async {
  final data = await _api.getJson(
    '/api/adaptive/milestones/$milestoneId/insight',
  );
  return MilestoneInsightResponse.fromJson(data);
}

Future<CheckMilestoneCompletionResponse> checkMilestoneCompletion(
  String milestoneId,
) async {
  final data = await _api.getJson(
    '/api/adaptive/milestones/$milestoneId/check-completion',
  );
  return CheckMilestoneCompletionResponse.fromJson(data);
}

// ── Memory ─────────────────────────────────────────────────────────────────────

Future<List<MemoryResponse>> listMemory() async {
  final data = await _api.getJson('/api/adaptive/memory');
  return (data as List).map((m) => MemoryResponse.fromJson(m)).toList();
}

Future<void> deleteMemory(String memoryId) async {
  await _api.delete('/api/adaptive/memory/$memoryId');
}

Future<ExtractMemoryResponse> extractMemory(
  ExtractMemoryPayload payload,
) async {
  final data = await _api.postJson(
    '/api/adaptive/extract-memory',
    payload.toJson(),
  );
  return ExtractMemoryResponse.fromJson(data);
}

Future<ExtractMemoryResponse> extractMemoryFromChat(String conversation) async {
  final data = await _api.postJson('/api/adaptive/extract-memory', {
    'conversation': conversation,
  });
  return ExtractMemoryResponse.fromJson(data);
}

// ── Plan Generation from Chat (two-phase) ─────────────────────────────────

/// Phase 1 — sends only the user's own messages; returns extracted fields +
/// which required fields are still missing.
Future<ExtractFromChatResponse> extractFieldsFromChat(
  List<String> userMessages,
) async {
  final data = await _api.postJson('/api/adaptive/plans/extract-from-chat', {
    'user_messages': userMessages,
  });
  return ExtractFromChatResponse.fromJson(data as Map<String, dynamic>);
}

/// Phase 2 — sends all 5 wizard fields (fully filled) and creates the plan.
Future<GenerateFromChatResponse> generatePlanFromChat(
  GenerateFromChatPayload payload,
) async {
  final data = await _api.postJson(
    '/api/adaptive/plans/generate-from-chat',
    payload.toJson(),
  );
  return GenerateFromChatResponse.fromJson(data);
}

// ── Plan Generation ────────────────────────────────────────────────────────────

Future<CreatePlanResponse> generatePlan(String memoryId) async {
  final data = await _api.postJson('/api/adaptive/create-plan', {
    'memory_id': memoryId,
  });
  return CreatePlanResponse.fromJson(data);
}

Future<CreatePlanResponse> generatePlanFromMemory(String memoryId) async {
  final data = await _api.postJson('/api/adaptive/plans/generate', {
    'memory_id': memoryId,
  });
  return CreatePlanResponse.fromJson(data);
}

Future<CreatePlanResponse> generatePlanFromAnswers({
  required String learningGoal,
  required String focusArea,
  required String skillLevel,
  String focusOrAvoid = '',
  String extraContext = '',
}) async {
  final data = await _api
      .postJson('/api/adaptive/plans/generate-from-answers', {
        'learning_goal': learningGoal,
        'focus_area': focusArea,
        'skill_level': skillLevel,
        'focus_or_avoid': focusOrAvoid,
        'extra_context': extraContext,
      });
  return CreatePlanResponse.fromJson(data);
}

// ── Chat ───────────────────────────────────────────────────────────────────────

Future<Map<String, dynamic>> sendMessage(
  String content,
  SessionContext sessionContext, {
  String? conversationId,
  List<Map<String, String>>? history,
  String source = 'chat',
}) async {
  final body = <String, dynamic>{
    'message': content,
    'source': source,
    'session_context': sessionContext.toJson(),
  };
  if (conversationId != null) body['conversation_id'] = conversationId;
  if (history != null) body['history'] = history;
  final data = await _api.postJson('/api/chat', body);
  return data as Map<String, dynamic>;
}

// ── Conversations ──────────────────────────────────────────────────────────────

Future<List<ConversationSummary>> listConversations() async {
  final data = await _api.getJson('/api/conversations');
  return (data as List).map((c) => ConversationSummary.fromJson(c)).toList();
}

Future<ConversationDetail> getConversation(String id) async {
  final data = await _api.getJson('/api/conversations/$id');
  return ConversationDetail.fromJson(data);
}

Future<ConversationSummary> createConversation({String? title}) async {
  final body = <String, dynamic>{};
  if (title != null) body['title'] = title;
  final data = await _api.postJson('/api/conversations', body);
  return ConversationSummary.fromJson(data);
}

Future<ConversationSummary> renameConversation(String id, String title) async {
  final data = await _api.patchJson('/api/conversations/$id', {'title': title});
  return ConversationSummary.fromJson(data);
}

Future<void> deleteConversation(String id) async {
  await _api.delete('/api/conversations/$id');
}
