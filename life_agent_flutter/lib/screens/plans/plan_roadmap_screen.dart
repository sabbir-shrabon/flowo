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
import '../../widgets/task_detail_card.dart';

class PlanRoadmapScreen extends ConsumerStatefulWidget {
  final String planId;

  const PlanRoadmapScreen({super.key, required this.planId});

  @override
  ConsumerState<PlanRoadmapScreen> createState() => _PlanRoadmapScreenState();
}

class _PlanRoadmapScreenState extends ConsumerState<PlanRoadmapScreen> {
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

  bool _chatExpanded = false; // sidebar expanded (desktop/tablet)
  bool _mobileChatExpanded = false; // bottom sheet expanded (mobile)

  // Selected task detail state
  TaskDetailResponse? _selectedTaskDetail;
  bool _taskDetailLoading = false;
  String? _selectedTaskId;
  String? _selectedTaskTitle; // task name shown in chat header

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
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _actingTaskId = null);
    }
  }

  Future<void> _handleTaskTap(TaskResponse task) async {
    setState(() {
      _selectedTaskId = task.id;
      _selectedTaskTitle = task.title;
      _selectedTaskDetail = null;
      _taskDetailLoading = true;
      _chatExpanded = true;
      _mobileChatExpanded = true;
    });
    _scrollChatToBottom();
    try {
      final detail = await getTaskDetail(task.id);
      if (mounted) {
        setState(() {
          _selectedTaskDetail = detail;
          _taskDetailLoading = false;
        });
        _scrollChatToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _taskDetailLoading = false;
        });
      }
    }
  }

  void _clearSelectedTask() {
    setState(() {
      _selectedTaskDetail = null;
      _selectedTaskId = null;
      _selectedTaskTitle = null;
      _taskDetailLoading = false;
    });
  }

  Future<void> _handleSkipTask(TaskResponse task) async {
    setState(() => _actingTaskId = task.id);
    try {
      await updateTask(
        TaskUpdatePayload(taskId: task.id, status: TaskStatus.skipped),
      );
      await _fetchDetail();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
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
      final res = await sendPlanChat(
        widget.planId,
        content,
        taskId: _selectedTaskId,
      );
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
      final res = await sendPlanChat(
        widget.planId,
        newText.trim(),
        taskId: _selectedTaskId,
      );
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

  @override
  Widget build(BuildContext context) {
    final plan = _detail?.plan;
    final stats = _detail?.stats;
    final milestones = _detail?.milestones ?? [];

    final width = MediaQuery.of(context).size.width;
    final isWideScreen = width >= 600;

    final contentBody = _loading
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
                Text(_error!, style: TextStyle(color: context.colors.error)),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _buildHeader(plan, stats),
                const SizedBox(height: 16),
                _buildProgressBar(stats),
                const SizedBox(height: 20),
                _buildRoadmap(milestones),
                SizedBox(height: isWideScreen ? 16 : 80),
              ],
            ),
          )
        : const SizedBox.shrink();

    final mainContent = NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        SliverAppBar(
          title: Text(
            plan?.title ?? 'Plan Roadmap',
            overflow: TextOverflow.ellipsis,
          ),
          floating: true,
          snap: true,
          actions: [
            if (isWideScreen)
              TextButton.icon(
                onPressed: () => setState(() => _chatExpanded = !_chatExpanded),
                icon: Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: context.colors.accent,
                ),
                label: Text(
                  'Plan Chat',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                ),
              ),
            if (!isWideScreen)
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => ref.read(sidebarOpenProvider.notifier).state =
                    !ref.read(sidebarOpenProvider),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ],
      body: contentBody,
    );

    if (isWideScreen) {
      return Scaffold(
        body: Stack(
          children: [mainContent, if (_chatExpanded) _buildSidebarChat()],
        ),
      );
    }

    // Mobile: Stack with bottom chat bar
    return Scaffold(
      body: Stack(children: [mainContent, _buildMobileChatBar()]),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader(PlanResponse plan, PlanDetailStats stats) {
    final statusColor = _statusColor(plan.status);
    final totalTasks = stats.totalTasks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
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
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (plan.durationDays != null)
              Text(
                '${plan.durationDays} days',
                style: TextStyle(color: context.colors.textMuted, fontSize: 12),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          plan.title ?? 'Untitled Plan',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${stats.totalMilestones} steps · $totalTasks tasks',
          style: TextStyle(color: context.colors.textMuted, fontSize: 13),
        ),
      ],
    );
  }

  // ── Progress bar ────────────────────────────────────────────
  Widget _buildProgressBar(PlanDetailStats stats) {
    final pct = stats.progressPct / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: context.colors.elevated,
            color: context.colors.accent,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                '${stats.completedTasks}/${stats.totalTasks} tasks done',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              '${stats.progressPct.toStringAsFixed(0)}%',
              style: TextStyle(
                color: context.colors.accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Roadmap (timeline with milestones + trackable tasks) ─────
  Widget _buildRoadmap(List<MilestoneResponse> milestones) {
    if (milestones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            'No milestones yet',
            style: TextStyle(color: context.colors.textMuted, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: milestones.asMap().entries.map((entry) {
        final i = entry.key;
        final ms = entry.value;
        return _RoadmapMilestoneNode(
          milestone: ms,
          index: i,
          isLast: i == milestones.length - 1,
          actingTaskId: _actingTaskId,
          onToggleTask: _handleToggleTask,
          onSkipTask: _handleSkipTask,
          onTaskTap: _handleTaskTap,
          onTapMilestone: () =>
              context.push('/plans/${widget.planId}/milestones/${ms.id}'),
        );
      }).toList(),
    );
  }

  // ── Chat panel (reusable content: messages + input) ──────────
  Widget _buildChatPanel({bool compact = false}) {
    final hasTask = _selectedTaskId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          hasTask ? (_selectedTaskTitle ?? 'Task Chat') : 'Plan Chat',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hasTask
              ? 'Ask how to complete this task, get tips, or explore resources.'
              : 'Ask to reframe milestones, add tasks, skip tasks, or get advice.',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: compact ? 11 : 12,
          ),
        ),
        const SizedBox(height: 8),

        // Single scrollable area for task detail + chat messages
        Expanded(
          child: ListView(
            controller: _chatScrollController,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              // Task detail card
              if (_selectedTaskId != null)
                _taskDetailLoading
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.colors.elevated,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShimmerLine(width: 80, height: 14),
                            const SizedBox(height: 8),
                            ShimmerLine(height: 12),
                            const SizedBox(height: 4),
                            ShimmerLine(height: 12),
                            const SizedBox(height: 4),
                            ShimmerLine(width: 180, height: 12),
                          ],
                        ),
                      )
                    : _selectedTaskDetail != null
                    ? TaskDetailCard(
                        detail: _selectedTaskDetail!.detail,
                        compact: compact,
                        onClose: _clearSelectedTask,
                      )
                    : const SizedBox.shrink(),

              // Chat messages
              ..._chatMessages.asMap().entries.map((entry) {
                final index = entry.key;
                final msg = entry.value;
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
                      onEditCancel: () => setState(() => _editingIndex = null),
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
              }),

              // Loading / saving indicator
              if (_chatLoading)
                const AssistantStatusPill(status: AssistantStatus.thinking),
            ],
          ),
        ),

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
                decoration: InputDecoration(
                  hintText: _selectedTaskId != null
                      ? 'Ask about this task…'
                      : 'Ask about this plan…',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
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
    );
  }

  // ── Sidebar chat (desktop/tablet) ────────────────────────────
  Widget _buildSidebarChat() {
    final chatWidth = MediaQuery.of(context).size.width / 4;
    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: chatWidth,
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(
            left: BorderSide(color: context.colors.border, width: 1),
          ),
        ),
        child: Column(
          children: [
            // Collapse handle
            GestureDetector(
              onTap: () => setState(() => _chatExpanded = false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.keyboard_arrow_right,
                      color: context.colors.textMuted,
                      size: 18,
                    ),
                    const Spacer(),
                    Text(
                      'Chat',
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildChatPanel(compact: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mobile chat bar (Notion-style) ────────────────────────────
  Widget _buildMobileChatBar() {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedHeight = screenHeight / 2;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (_mobileChatExpanded && details.delta.dy > 0) {
            // Swiping down while expanded → collapse
            setState(() => _mobileChatExpanded = false);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          height: _mobileChatExpanded ? expandedHeight : 48,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border(
              top: BorderSide(color: context.colors.border, width: 1),
            ),
          ),
          child: _mobileChatExpanded
              ? OverflowBox(
                  minHeight: expandedHeight,
                  maxHeight: expandedHeight,
                  alignment: Alignment.topCenter,
                  child: Column(
                    children: [
                      // Drag handle + collapse toggle
                      GestureDetector(
                        onTap: () =>
                            setState(() => _mobileChatExpanded = false),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Plan Chat',
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down,
                                color: context.colors.textMuted,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Chat content
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: _buildChatPanel(compact: true),
                        ),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: () => setState(() => _mobileChatExpanded = true),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    height: 48,
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: context.colors.textSecondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Plan Chat',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.keyboard_arrow_up,
                          color: context.colors.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Roadmap milestone node with trackable tasks
// ─────────────────────────────────────────────────────────────
class _RoadmapMilestoneNode extends StatefulWidget {
  final MilestoneResponse milestone;
  final int index;
  final bool isLast;
  final String? actingTaskId;
  final ValueChanged<TaskResponse> onToggleTask;
  final ValueChanged<TaskResponse> onSkipTask;
  final ValueChanged<TaskResponse>? onTaskTap;
  final VoidCallback onTapMilestone;

  const _RoadmapMilestoneNode({
    required this.milestone,
    required this.index,
    required this.isLast,
    this.actingTaskId,
    required this.onToggleTask,
    required this.onSkipTask,
    this.onTaskTap,
    required this.onTapMilestone,
  });

  @override
  State<_RoadmapMilestoneNode> createState() => _RoadmapMilestoneNodeState();
}

class _RoadmapMilestoneNodeState extends State<_RoadmapMilestoneNode>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  static const _stepColors = [
    Color(0xFF3DD6B5),
    Color(0xFF5B9CF6),
    Color(0xFFE8A843),
    Color(0xFFE8605A),
    Color(0xFF9B8FE8),
    Color(0xFF7B7A94),
  ];

  @override
  void initState() {
    super.initState();
    // Auto-expand active milestone
    _expanded = widget.milestone.status == MilestoneStatus.active;
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _expanded ? 1 : 0,
    );
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  Color get _color {
    final ms = widget.milestone;
    if (ms.status == MilestoneStatus.completed) return const Color(0xFF7c3aed);
    if (ms.status == MilestoneStatus.locked) return const Color(0xFF7B7A94);
    return _stepColors[widget.index % _stepColors.length];
  }

  String get _statusLabel {
    switch (widget.milestone.status) {
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
    final ms = widget.milestone;
    final doneCount = ms.tasks.where((t) => t.status == TaskStatus.done).length;
    final totalCount = ms.tasks.length;
    final isLocked = ms.status == MilestoneStatus.locked;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Circle node
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _color.withValues(alpha: 0.15),
                    border: Border.all(color: _color, width: 2),
                  ),
                  child: Center(
                    child: isLocked
                        ? Icon(Icons.lock, size: 12, color: _color)
                        : Text(
                            '${widget.index + 1}',
                            style: TextStyle(
                              color: _color,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
                // Connector line
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: context.colors.border,
                    ),
                  ),
                if (widget.isLast) const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step header (tappable)
                GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Step ${widget.index + 1}',
                                    style: TextStyle(
                                      color: _color,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _color.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _statusLabel,
                                      style: TextStyle(
                                        color: _color,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ms.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isLocked
                                      ? context.colors.textMuted
                                      : context.colors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$doneCount/$totalCount tasks done'
                                '${ms.suggestedDays != null ? ' · ${ms.suggestedDays} days' : ''}',
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: context.colors.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                // Expanded tasks with tracking
                SizeTransition(
                  sizeFactor: _expandAnim,
                  child: Column(
                    children: [
                      if (ms.outcome != null && ms.outcome!.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _color.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _color.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.flag, size: 14, color: _color),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  ms.outcome!,
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      ...ms.tasks.asMap().entries.map((e) {
                        final task = e.value;
                        final isDone = task.status == TaskStatus.done;
                        final isSkipped = task.status == TaskStatus.skipped;
                        final isActing = widget.actingTaskId == task.id;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: isActing
                                    ? Padding(
                                        padding: const EdgeInsets.all(3),
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: context.colors.accent,
                                        ),
                                      )
                                    : GestureDetector(
                                        onTap: isLocked
                                            ? null
                                            : () => widget.onToggleTask(task),
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
                                                  : _color.withValues(
                                                      alpha: 0.4,
                                                    ),
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
                                                  color:
                                                      context.colors.textMuted,
                                                )
                                              : null,
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              // Task title + metadata
                              Expanded(
                                child: GestureDetector(
                                  onTap: widget.onTaskTap != null
                                      ? () => widget.onTaskTap!(task)
                                      : null,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        task.title,
                                        style: TextStyle(
                                          color: isDone || isSkipped
                                              ? context.colors.textMuted
                                              : widget.onTaskTap != null
                                              ? context.colors.accent
                                              : context.colors.textPrimary,
                                          fontSize: 13,
                                          height: 1.4,
                                          decoration: isDone
                                              ? TextDecoration.lineThrough
                                              : null,
                                        ),
                                      ),
                                      if (task.dueDate != null ||
                                          task.durationMinutes != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Row(
                                            children: [
                                              if (task.durationMinutes != null)
                                                Flexible(
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 5,
                                                          vertical: 1,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: context
                                                          .colors
                                                          .elevated,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            3,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      '${task.durationMinutes}m',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: context
                                                            .colors
                                                            .textSecondary,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (task.dueDate != null) ...[
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    task.dueDate!,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: context
                                                          .colors
                                                          .textMuted,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Skip button for pending tasks
                              if (!isDone &&
                                  !isSkipped &&
                                  !isLocked &&
                                  !isActing)
                                GestureDetector(
                                  onTap: () => widget.onSkipTask(task),
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      Icons.skip_next,
                                      size: 16,
                                      color: context.colors.textMuted
                                          .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                      // View milestone insight link
                      if (!isLocked)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 8),
                          child: GestureDetector(
                            onTap: widget.onTapMilestone,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.insights, size: 14, color: _color),
                                const SizedBox(width: 4),
                                Text(
                                  'View insight',
                                  style: TextStyle(
                                    color: _color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
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
