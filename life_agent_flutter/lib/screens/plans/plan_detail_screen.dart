import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/plan_models.dart';
import '../../models/milestone_models.dart';
import '../../models/task_models.dart';
import '../../providers/navigation_provider.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../utils/feature_flags.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/assistant_status_pill.dart';
import '../../widgets/inline_chat_bubble.dart';

class PlanDetailScreen extends ConsumerStatefulWidget {
  final String planId;

  const PlanDetailScreen({super.key, required this.planId});

  @override
  ConsumerState<PlanDetailScreen> createState() => _PlanDetailScreenState();
}

class _PlanDetailScreenState extends ConsumerState<PlanDetailScreen> {
  PlanDetailResponse? _detail;
  bool _loading = true;
  String? _error;
  String? _actingTaskId;

  // Chat state
  List<_PlanChatMsg> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _chatLoading = false;
  int? _editingIndex;
  final ScrollController _chatScrollController = ScrollController();


  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await (FeatureFlags.useV2Endpoints
          ? getPlanDetailV2(widget.planId)
          : getPlanDetail(widget.planId));
      if (mounted) {
        setState(() {
          _detail = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleToggleTask(TaskResponse task) async {
    final newStatus = task.status == TaskStatus.done
        ? TaskStatus.pending
        : TaskStatus.done;
    setState(() => _actingTaskId = task.id);
    try {
      await updateTask(TaskUpdatePayload(taskId: task.id, status: newStatus));
      await _fetchDetail();
      ref.read(todayRefreshProvider.notifier).state++;
      // Check milestone completion when marking done
      if (newStatus == TaskStatus.done && task.milestoneId != null) {
        try {
          final checkRes = await checkMilestoneCompletion(task.milestoneId!);
          if (checkRes.completed && checkRes.nextMilestone != null) {
            await _fetchDetail();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Milestone complete! ${checkRes.nextMilestone!.title} unlocked.',
                  ),
                ),
              );
            }
          }
        } catch (_) {
          // Best-effort
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _actingTaskId = null);
    }
  }

  Future<void> _handleSendChat() async {
    final content = _chatController.text.trim();
    if (content.isEmpty || _chatLoading) return;

    _chatController.clear();
    setState(() {
      _chatMessages.add(
        _PlanChatMsg(role: 'user', content: content, createdAt: DateTime.now()),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final res = await sendPlanChat(widget.planId, content);
      setState(() {
        _chatMessages.add(
          _PlanChatMsg(
            role: 'assistant',
            content: res.reply,
            actions: res.actions.isNotEmpty ? res.actions : null,
            createdAt: DateTime.now(),
          ),
        );
        _chatLoading = false;
      });
      _scrollChatToBottom();

      if (res.actions.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _fetchDetail();
        ref.read(todayRefreshProvider.notifier).state++;
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(
          _PlanChatMsg(role: 'assistant', content: 'Error: $e'),
        );
        _chatLoading = false;
      });
    }
  }

  Future<void> _handleEditSubmit(int index, String newText) async {
    if (newText.trim().isEmpty) {
      setState(() => _editingIndex = null);
      return;
    }

    setState(() {
      _editingIndex = null;
      _chatMessages = _chatMessages.sublist(0, index);
      _chatMessages.add(
        _PlanChatMsg(
          role: 'user',
          content: newText.trim(),
          createdAt: DateTime.now(),
        ),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final res = await sendPlanChat(widget.planId, newText.trim());
      setState(() {
        _chatMessages.add(
          _PlanChatMsg(
            role: 'assistant',
            content: res.reply,
            actions: res.actions.isNotEmpty ? res.actions : null,
            createdAt: DateTime.now(),
          ),
        );
        _chatLoading = false;
      });
      _scrollChatToBottom();

      if (res.actions.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
        await _fetchDetail();
        ref.read(todayRefreshProvider.notifier).state++;
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(
          _PlanChatMsg(role: 'assistant', content: 'Error: $e'),
        );
        _chatLoading = false;
      });
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Color _statusColor(PlanStatus status) {
    switch (status) {
      case PlanStatus.setup:
        return context.colors.warning;
      case PlanStatus.active:
        return context.colors.success;
      case PlanStatus.paused:
        return context.colors.error;
      case PlanStatus.completed:
        return const Color(0xFF7c3aed);
    }
  }

  String _statusLabel(PlanStatus status) {
    switch (status) {
      case PlanStatus.setup:
        return 'Setup';
      case PlanStatus.active:
        return 'Active';
      case PlanStatus.paused:
        return 'Paused';
      case PlanStatus.completed:
        return 'Completed';
    }
  }

  Color _milestoneStatusColor(MilestoneStatus status) {
    switch (status) {
      case MilestoneStatus.completed:
        return const Color(0xFF7c3aed);
      case MilestoneStatus.active:
        return context.colors.info;
      case MilestoneStatus.locked:
        return context.colors.textMuted;
    }
  }

  String _milestoneStatusLabel(MilestoneStatus status) {
    switch (status) {
      case MilestoneStatus.completed:
        return 'Completed';
      case MilestoneStatus.active:
        return 'Active';
      case MilestoneStatus.locked:
        return 'Locked';
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _detail?.plan;
    final stats = _detail?.stats;
    final milestones = _detail?.milestones ?? [];

    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(plan?.title ?? 'Plan Detail'),
            leading: null, // Allow default back button
            floating: true,
            snap: true,
            actions: [
              if (!isLargeDesktop)
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () =>
                      ref.read(sidebarOpenProvider.notifier).state = !ref.read(
                        sidebarOpenProvider,
                      ),
                ),
              const SizedBox(width: 8),
            ],
          ),
        ],
        body: _loading
            ? const PlanDetailSkeleton()
            : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 48,
                      color: context.colors.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: context.colors.error),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchDetail,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : plan != null && stats != null
            ? RefreshIndicator(
                onRefresh: _fetchDetail,
                color: context.colors.accent,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    _buildOverviewHeader(plan, stats),
                    const SizedBox(height: 16),
                    _buildProgressSection(stats),
                    const SizedBox(height: 16),
                    _buildMilestonesSection(milestones),
                    const SizedBox(height: 16),
                    _buildTasksSection(milestones, stats),
                    const SizedBox(height: 16),
                    _buildChatSection(),
                    const SizedBox(height: 80),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildOverviewHeader(PlanResponse plan, PlanDetailStats stats) {
    final statusColor = _statusColor(plan.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.title ?? 'Untitled Plan',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel(plan.status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statCard('${stats.progressPct.toStringAsFixed(0)}%', 'Progress'),
              _statCard('${stats.completedTasks}', 'Done'),
              _statCard('${stats.remainingTasks}', 'Remaining'),
              _statCard('${stats.totalMilestones}', 'Milestones'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(PlanDetailStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progress',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.progressPct / 100,
              backgroundColor: context.colors.elevated,
              color: context.colors.accent,
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${stats.completedTasks} of ${stats.totalTasks} tasks complete',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                '${stats.completedMilestones} of ${stats.totalMilestones} milestones done',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.currentMilestone != null ||
              stats.nextMilestone != null ||
              stats.nextTask != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (stats.currentMilestone != null)
                  _nextCard(
                    'Current Milestone',
                    stats.currentMilestone!.title,
                    context.colors.info,
                  ),
                if (stats.nextMilestone != null)
                  _nextCard(
                    'Next Milestone',
                    stats.nextMilestone!.title,
                    context.colors.textSecondary,
                  ),
                if (stats.nextTask != null)
                  _nextCard(
                    'Next Task',
                    stats.nextTask!.title,
                    context.colors.accent,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _nextCard(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestonesSection(List<MilestoneResponse> milestones) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Milestones',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (milestones.isEmpty)
            Text(
              'No milestones',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13),
            )
          else
            ...milestones.map((ms) {
              final msColor = _milestoneStatusColor(ms.status);
              final msDone = ms.tasks
                  .where((t) => t.status == TaskStatus.done)
                  .length;
              final msTotal = ms.tasks.length;
              final msPct = msTotal > 0
                  ? ((msDone / msTotal) * 100).round()
                  : 0;

              return InkWell(
                onTap: () =>
                    context.push('/plans/${widget.planId}/milestones/${ms.id}'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ms.status == MilestoneStatus.active
                        ? msColor.withValues(alpha: 0.06)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ms.status == MilestoneStatus.active
                          ? msColor.withValues(alpha: 0.2)
                          : context.colors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: msColor.withValues(alpha: 0.15),
                          border: Border.all(color: msColor, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            '${ms.orderIndex}',
                            style: TextStyle(
                              color: msColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ms.title,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: msColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _milestoneStatusLabel(ms.status),
                                    style: TextStyle(
                                      color: msColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '$msDone/$msTotal tasks',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$msPct%',
                                  style: TextStyle(
                                    color: msColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            if (msTotal > 0) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: msPct / 100,
                                  backgroundColor: context.colors.elevated,
                                  color: msColor,
                                  minHeight: 4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        color: context.colors.textMuted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTasksSection(
    List<MilestoneResponse> milestones,
    PlanDetailStats stats,
  ) {
    final allTasks = milestones.expand((ms) => ms.tasks).toList();
    final pendingTasks = allTasks
        .where(
          (t) =>
              t.status == TaskStatus.pending || t.status == TaskStatus.partial,
        )
        .toList();
    final completedTasks = allTasks
        .where((t) => t.status == TaskStatus.done)
        .toList();
    final skippedTasks = allTasks
        .where((t) => t.status == TaskStatus.skipped)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tasks',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),

          // Next task prominent
          if (stats.nextTask != null)
            InkWell(
              onTap: () => context.push('/today/task/${stats.nextTask!.id}'),
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: context.colors.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'NEXT UP',
                      style: TextStyle(
                        color: context.colors.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        stats.nextTask!.title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward,
                      color: context.colors.accent,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),

          // Pending tasks
          if (pendingTasks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Remaining (${pendingTasks.length})',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...pendingTasks.map((task) => _taskRow(task, isPending: true)),
          ],

          // Completed tasks
          if (completedTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Completed (${completedTasks.length})',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...completedTasks.map((task) => _taskRow(task, isPending: false)),
          ],

          // Skipped tasks
          if (skippedTasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Skipped (${skippedTasks.length})',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            ...skippedTasks.map(
              (task) => _taskRow(task, isPending: false, isSkipped: true),
            ),
          ],
        ],
      ),
    );
  }

  Widget _taskRow(
    TaskResponse task, {
    bool isPending = false,
    bool isSkipped = false,
  }) {
    final isDone = task.status == TaskStatus.done;
    final isActing = _actingTaskId == task.id;

    return InkWell(
      onTap: () => context.push('/today/task/${task.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: isActing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accent,
                      ),
                    )
                  : GestureDetector(
                      onTap: isPending ? () => _handleToggleTask(task) : null,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? context.colors.accent
                              : Colors.transparent,
                          border: Border.all(
                            color: isDone
                                ? context.colors.accent
                                : isSkipped
                                ? context.colors.textMuted
                                : context.colors.border,
                            width: 2,
                          ),
                        ),
                        child: isDone
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : isSkipped
                            ? Icon(
                                Icons.block,
                                size: 12,
                                color: context.colors.textMuted,
                              )
                            : null,
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                task.title,
                style: TextStyle(
                  color: isDone || isSkipped
                      ? context.colors.textMuted
                      : context.colors.textPrimary,
                  fontSize: 13,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (task.durationMinutes != null)
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.elevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${task.durationMinutes}m',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Plan Chat',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Ask to reframe milestones, add tasks, skip tasks, or get advice.',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),

          // Chat messages
          if (_chatMessages.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                controller: _chatScrollController,
                shrinkWrap: true,
                itemCount: _chatMessages.length + (_chatLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _chatMessages.length) {
                    return const AssistantStatusPill(
                      status: AssistantStatus.thinking,
                    );
                  }
                  final msg = _chatMessages[index];
                  final isUser = msg.role == 'user';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InlineChatBubble(
                        isUser: isUser,
                        content: msg.content,
                        createdAt: msg.createdAt,
                        onViewMemory: () => context.push('/memory'),
                        onRewrite: (_) {
                          setState(() => _editingIndex = index);
                        },
                        isEditing: _editingIndex == index,
                        onEditCancel: () =>
                            setState(() => _editingIndex = null),
                        onEditSubmit: (newText) =>
                            _handleEditSubmit(index, newText),
                      ),
                      if (!isUser &&
                          msg.actions != null &&
                          msg.actions!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            spacing: 6,
                            children: msg.actions!
                                .map(
                                  (a) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.colors.accent.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      a.action.replaceAll('_', ' '),
                                      style: TextStyle(
                                        color: context.colors.accent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

          const SizedBox(height: 8),

          // Chat input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Ask about this plan…',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _handleSendChat(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _chatLoading ? null : _handleSendChat,
                icon: Icon(Icons.send, color: context.colors.accent, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: context.colors.accent.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanChatMsg {
  final String role;
  final String content;
  final List<PlanChatAction>? actions;
  final DateTime? createdAt;

  _PlanChatMsg({
    required this.role,
    required this.content,
    this.actions,
    this.createdAt,
  });
}
