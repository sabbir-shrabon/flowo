import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/plan_models.dart';
import '../../models/task_models.dart';
import '../../providers/navigation_provider.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/assistant_message_renderer.dart';
import '../../widgets/inline_chat_bubble.dart';
import '../../widgets/shimmer_loading.dart';

enum _ReviewMode { append, replace }

class TaskWorkspaceScreen extends ConsumerStatefulWidget {
  final TaskResponse task;
  final String? planTitle;
  final String? milestoneTitle;

  const TaskWorkspaceScreen({
    super.key,
    required this.task,
    this.planTitle,
    this.milestoneTitle,
  });

  @override
  ConsumerState<TaskWorkspaceScreen> createState() =>
      _TaskWorkspaceScreenState();
}

class _TaskWorkspaceScreenState extends ConsumerState<TaskWorkspaceScreen> {
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  TaskDetailResponse? _detail;
  List<SubtaskResponse> _subtasks = [];
  List<_ReviewSubtask> _reviewItems = [];
  _ReviewMode _reviewMode = _ReviewMode.append;
  final List<_TaskChatMsg> _chatMessages = [];

  bool _loadingDetail = true;
  bool _loadingSubtasks = true;
  bool _adding = false;
  bool _generating = false;
  bool _savingReview = false;
  bool _chatLoading = false;
  bool _mobileChatExpanded = false;
  final Set<String> _togglingSubtaskIds = {};
  String? _detailError;
  String? _subtaskError;
  String? _reviewError;
  int? _reviewSavedCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  bool get _loading => _loadingDetail || _loadingSubtasks;
  bool get _inReview => _reviewItems.isNotEmpty || _reviewError != null;

  int get _completedCount => _subtasks.where((s) => s.completed).length;

  List<SubtaskResponse> get _orderedSubtasks {
    final copy = [..._subtasks];
    copy.sort((a, b) {
      final byDone = (a.completed ? 1 : 0).compareTo(b.completed ? 1 : 0);
      if (byDone != 0) return byDone;
      return a.orderIndex.compareTo(b.orderIndex);
    });
    return copy;
  }

  TaskWorkspaceResult _result() {
    final completed = _subtasks.where((s) => s.completed).length;
    return TaskWorkspaceResult(
      taskId: widget.task.id,
      isCompleted:
          widget.task.status == TaskStatus.done ||
          (_subtasks.isNotEmpty && completed == _subtasks.length),
      subtaskCount: _subtasks.length,
      completedSubtaskCount: completed,
      hasSubtasks: _subtasks.isNotEmpty,
    );
  }

  Future<void> _load() async {
    setState(() {
      _loadingDetail = true;
      _loadingSubtasks = true;
      _detailError = null;
      _subtaskError = null;
    });

    final detailFuture = getTaskDetail(widget.task.id);
    final subtaskFuture = getSubtasks(widget.task.id);

    try {
      final detail = await detailFuture;
      if (mounted) setState(() => _detail = detail);
    } catch (e) {
      if (mounted) setState(() => _detailError = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }

    try {
      final subtasks = await subtaskFuture;
      if (mounted) setState(() => _subtasks = subtasks);
    } catch (e) {
      if (mounted) setState(() => _subtaskError = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingSubtasks = false);
    }
  }

  Future<void> _retrySubtasks() async {
    setState(() {
      _loadingSubtasks = true;
      _subtaskError = null;
    });
    try {
      final subtasks = await getSubtasks(widget.task.id);
      if (mounted) setState(() => _subtasks = subtasks);
    } catch (e) {
      if (mounted) setState(() => _subtaskError = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loadingSubtasks = false);
    }
  }

  Future<void> _addSubtask() async {
    final title = _addController.text.trim();
    if (title.isEmpty || _adding) return;
    setState(() => _adding = true);
    try {
      final subtask = await createSubtask(widget.task.id, title);
      if (!mounted) return;
      setState(() {
        _subtasks = [..._subtasks, subtask];
        _addController.clear();
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, onRetry: _addSubtask);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggleSubtask(SubtaskResponse subtask) async {
    if (_togglingSubtaskIds.contains(subtask.id)) return;
    final previous = [..._subtasks];
    final nextCompleted = !subtask.completed;
    setState(() {
      _togglingSubtaskIds.add(subtask.id);
      _subtasks = _subtasks
          .map(
            (s) => s.id == subtask.id
                ? _copySubtask(s, completed: nextCompleted)
                : s,
          )
          .toList();
    });

    try {
      final updated = await patchSubtask(subtask.id, completed: nextCompleted);
      if (!mounted) return;
      setState(() {
        _subtasks = _subtasks
            .map((s) => s.id == updated.id ? updated : s)
            .toList();
      });
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (!mounted) return;
      setState(() => _subtasks = previous);
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _togglingSubtaskIds.remove(subtask.id));
      }
    }
  }

  Future<void> _confirmDelete(SubtaskResponse subtask) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete step?'),
        content: Text(subtask.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final previous = [..._subtasks];
    setState(
      () => _subtasks = _subtasks.where((s) => s.id != subtask.id).toList(),
    );
    try {
      await deleteSubtask(subtask.id);
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (!mounted) return;
      setState(() => _subtasks = previous);
      showErrorSnackBar(context, e);
    }
  }

  Future<void> _startGenerate() async {
    if (_generating) return;
    var mode = _ReviewMode.append;
    if (_subtasks.isNotEmpty) {
      final choice = await showDialog<_ReviewMode>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace existing steps?'),
          content: const Text(
            'You can replace the checklist or add AI steps below it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_ReviewMode.append),
              child: const Text('Add below existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_ReviewMode.replace),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      mode = choice;
    }

    setState(() {
      _generating = true;
      _reviewError = null;
      _reviewSavedCount = null;
    });
    try {
      final response = await generateSubtasks(widget.task.id);
      if (!mounted) return;
      setState(() {
        _reviewMode = mode;
        _reviewItems = response.suggestions
            .map((s) => _ReviewSubtask(title: s.title))
            .toList();
      });
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e, onRetry: _startGenerate);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _saveReview() async {
    if (_savingReview || _reviewItems.isEmpty) return;
    setState(() {
      _savingReview = true;
      _reviewError = null;
      _reviewSavedCount = 0;
    });

    final saved = <SubtaskResponse>[];
    try {
      if (_reviewMode == _ReviewMode.replace) {
        for (final subtask in [..._subtasks]) {
          await deleteSubtask(subtask.id);
        }
      }
      for (final item in _reviewItems) {
        final title = item.title.trim();
        if (title.isEmpty) continue;
        final created = await createSubtask(widget.task.id, title);
        saved.add(created);
        if (mounted) setState(() => _reviewSavedCount = saved.length);
      }
      final fresh = await getSubtasks(widget.task.id);
      if (!mounted) return;
      setState(() {
        _subtasks = fresh;
        _reviewItems = [];
        _reviewError = null;
        _reviewSavedCount = null;
      });
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _reviewError = friendlyErrorMessage(e);
        if (_reviewMode == _ReviewMode.replace && saved.isNotEmpty) {
          _subtasks = saved;
        } else if (saved.isNotEmpty) {
          _subtasks = [..._subtasks, ...saved];
        }
      });
    } finally {
      if (mounted) setState(() => _savingReview = false);
    }
  }

  void _discardReview() {
    setState(() {
      _reviewItems = [];
      _reviewError = null;
      _reviewSavedCount = null;
    });
  }

  Future<void> _renameReviewItem(int index) async {
    final controller = TextEditingController(text: _reviewItems[index].title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename step'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 199,
          decoration: const InputDecoration(hintText: 'Step title'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    setState(() {
      _reviewItems[index] = _ReviewSubtask(title: title.trim());
    });
  }

  void _moveReviewItem(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _reviewItems.length) return;
    setState(() {
      final item = _reviewItems.removeAt(index);
      _reviewItems.insert(nextIndex, item);
    });
  }

  Future<void> _sendChat() async {
    final content = _chatController.text.trim();
    if (content.isEmpty || _chatLoading) return;
    _chatController.clear();
    setState(() {
      _chatMessages.add(_TaskChatMsg(role: 'user', content: content));
      _chatLoading = true;
    });
    _scrollChatToBottom();

    final subtaskContext = _orderedSubtasks
        .map((s) => '${s.completed ? "[done]" : "[todo]"} ${s.title}')
        .join('\n');
    final scopedMessage =
        'Task: ${widget.task.title}\n'
        'Plan: ${widget.planTitle ?? widget.task.planId}\n'
        'Milestone: ${widget.milestoneTitle ?? "Not provided"}\n'
        'Current subtasks:\n${subtaskContext.isEmpty ? "None" : subtaskContext}\n\n'
        'User question: $content';

    try {
      final response = await sendPlanChat(
        widget.task.planId,
        scopedMessage,
        taskId: widget.task.id,
      );
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          _TaskChatMsg(
            role: 'assistant',
            content: response.reply,
            actions: response.actions.isNotEmpty ? response.actions : null,
          ),
        );
        _chatLoading = false;
      });
      _scrollChatToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chatMessages.add(
          _TaskChatMsg(role: 'assistant', content: 'Error: $e'),
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _centeredDesktopContent(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: child,
      ),
    );
  }

  Widget _buildWorkspaceChatPanel({bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Plan Chat',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: compact ? 14 : 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Ask about this task or the steps below.',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: compact ? 11 : 12,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(
            controller: _chatScrollController,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              if (_detail != null)
                _CollapsibleGuide(detail: _detail!.detail)
              else if (_loadingDetail)
                _GuideSkeleton()
              else if (_detailError != null)
                Text(
                  _detailError!,
                  style: TextStyle(color: context.colors.error),
                ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.colors.elevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_chatMessages.isEmpty)
                      Text(
                        'Ask about this task or the steps below.',
                        style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ..._chatMessages.map(
                      (m) => InlineChatBubble(
                        isUser: m.role == 'user',
                        content: m.content,
                      ),
                    ),
                    if (_chatLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: context.colors.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thinking...',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ask about this task',
                  isDense: true,
                ),
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _chatLoading ? null : _sendChat,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomPlanChat() {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final expandedHeight =
        (screenHeight -
                mediaQuery.padding.top -
                mediaQuery.padding.bottom -
                kToolbarHeight -
                24)
            .clamp(320.0, screenHeight * 0.85)
            .toDouble();

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        if (_mobileChatExpanded && details.delta.dy > 0) {
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
            ? Column(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _mobileChatExpanded = false),
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
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _buildWorkspaceChatPanel(compact: true),
                    ),
                  ),
                ],
              )
            : GestureDetector(
                onTap: () => setState(() => _mobileChatExpanded = true),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_result());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_result()),
          ),
          title: Text(
            widget.planTitle ?? 'Task Workspace',
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: _loading
                  ? _centeredDesktopContent(const _WorkspaceSkeleton())
                  : _centeredDesktopContent(
                      RefreshIndicator(
                        onRefresh: _load,
                        color: context.colors.accent,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 18),
                            if (_subtaskError != null) _buildSubtaskError(),
                            if (_inReview)
                              _buildReviewState()
                            else
                              _buildChecklist(),
                          ],
                        ),
                      ),
                    ),
            ),
            _buildBottomPlanChat(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return InkWell(
      onTap: () => setState(() => _mobileChatExpanded = true),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.milestoneTitle != null)
                    Text(
                      widget.milestoneTitle!,
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    widget.task.title,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 24,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap to open guide in Plan Chat',
                    style: TextStyle(
                      color: context.colors.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chat_bubble_outline, color: context.colors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtaskError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.colors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _subtaskError!,
              style: TextStyle(color: context.colors.error, fontSize: 13),
            ),
          ),
          TextButton(onPressed: _retrySubtasks, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildChecklist() {
    final ordered = _orderedSubtasks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ordered.isNotEmpty) _buildProgress(),
        if (ordered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 54),
            child: Center(
              child: Text(
                'No steps yet',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else
          _buildSubtaskRows(ordered),
        const SizedBox(height: 16),
        _buildAddInput(),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _generating ? null : _startGenerate,
            icon: _generating
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.accent,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_generating ? 'Generating...' : 'AI generate steps'),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress() {
    final total = _subtasks.length;
    final value = total == 0 ? 0.0 : _completedCount / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_completedCount of $total steps done',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  color: context.colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 4,
              backgroundColor: context.colors.elevated,
              color: context.colors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtaskRows(List<SubtaskResponse> ordered) {
    final firstCheckedIndex = ordered.indexWhere((s) => s.completed);
    return Column(
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i == firstCheckedIndex && firstCheckedIndex > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Divider(color: context.colors.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: context.colors.border)),
                ],
              ),
            ),
          Dismissible(
            key: ValueKey(ordered[i].id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) async {
              await _confirmDelete(ordered[i]);
              return false;
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 18),
              color: context.colors.error,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Semantics(
                label: ordered[i].completed
                    ? 'Mark ${ordered[i].title} incomplete'
                    : 'Mark ${ordered[i].title} complete',
                child: Checkbox(
                  value: ordered[i].completed,
                  onChanged: _togglingSubtaskIds.contains(ordered[i].id)
                      ? null
                      : (_) => _toggleSubtask(ordered[i]),
                  activeColor: context.colors.accent,
                ),
              ),
              title: Text(
                ordered[i].title,
                style: TextStyle(
                  color: ordered[i].completed
                      ? context.colors.textMuted
                      : context.colors.textPrimary,
                  decoration: ordered[i].completed
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                color: context.colors.textMuted,
                onPressed: () => _confirmDelete(ordered[i]),
              ),
              onLongPress: () => _confirmDelete(ordered[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAddInput() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _addController,
            maxLength: 199,
            decoration: const InputDecoration(
              hintText: 'Add a step',
              counterText: '',
              isDense: true,
            ),
            onSubmitted: (_) => _addSubtask(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: _adding ? null : _addSubtask,
          icon: _adding
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildReviewState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: context.colors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _reviewMode == _ReviewMode.replace
                    ? 'Review replacement steps'
                    : 'Review AI steps',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_reviewError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.colors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Saved ${_reviewSavedCount ?? 0} before stopping. $_reviewError',
              style: TextStyle(color: context.colors.error, fontSize: 13),
            ),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _reviewItems.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _reviewItems.removeAt(oldIndex);
              _reviewItems.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final item = _reviewItems[index];
            return ListTile(
              key: ValueKey(item.id),
              contentPadding: EdgeInsets.zero,
              leading: IconButton(
                icon: const Icon(Icons.delete_outline),
                color: context.colors.textMuted,
                onPressed: () => setState(() => _reviewItems.removeAt(index)),
              ),
              title: InkWell(
                onTap: () => _renameReviewItem(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(item.title),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: index == 0
                        ? null
                        : () => _moveReviewItem(index, -1),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: index == _reviewItems.length - 1
                        ? null
                        : () => _moveReviewItem(index, 1),
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _savingReview ? null : _discardReview,
                child: const Text('Discard'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _savingReview ? null : _saveReview,
                child: Text(
                  _savingReview
                      ? 'Saving ${_reviewSavedCount ?? 0}/${_reviewItems.length}'
                      : 'Save all',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

SubtaskResponse _copySubtask(SubtaskResponse subtask, {bool? completed}) {
  return SubtaskResponse(
    id: subtask.id,
    taskId: subtask.taskId,
    title: subtask.title,
    completed: completed ?? subtask.completed,
    orderIndex: subtask.orderIndex,
    createdAt: subtask.createdAt,
    updatedAt: subtask.updatedAt,
  );
}

class _ReviewSubtask {
  final String id = UniqueKey().toString();
  final String title;

  _ReviewSubtask({required this.title});
}

class _TaskChatMsg {
  final String role;
  final String content;
  final List<PlanChatAction>? actions;

  _TaskChatMsg({required this.role, required this.content, this.actions});
}

class _CollapsibleGuide extends StatefulWidget {
  final TaskDetailData detail;

  const _CollapsibleGuide({required this.detail});

  @override
  State<_CollapsibleGuide> createState() => _CollapsibleGuideState();
}

class _CollapsibleGuideState extends State<_CollapsibleGuide> {
  bool _expanded = false;

  String _content() {
    final detail = widget.detail;
    final sb = StringBuffer();
    if (detail.whatIsThis.isNotEmpty) sb.writeln(detail.whatIsThis);
    if (detail.whyItMatters.isNotEmpty) {
      sb.writeln();
      sb.writeln(detail.whyItMatters);
    }
    if (detail.howToDoIt.isNotEmpty) {
      sb.writeln();
      sb.writeln('How to do it:');
      for (final step in detail.howToDoIt) {
        sb.writeln('${step.step}. ${step.instruction}');
      }
    }
    if (detail.resources.isNotEmpty) {
      sb.writeln();
      sb.writeln('Resources:');
      for (final resource in detail.resources) {
        sb.writeln(
          '- ${resource.title}${resource.description.isNotEmpty ? ': ${resource.description}' : ''}',
        );
      }
    }
    if (detail.expertTip.isNotEmpty) {
      sb.writeln();
      sb.writeln('Tip: ${detail.expertTip}');
    }
    return sb.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task Guide',
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            secondChild: AssistantMessageRenderer(text: content),
          ),
          if (content.length > 160)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? 'Show less' : 'Read more'),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceSkeleton extends StatelessWidget {
  const _WorkspaceSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ShimmerLine(width: 220, height: 28),
        SizedBox(height: 24),
        ShimmerLine(height: 14),
        SizedBox(height: 12),
        ShimmerLine(height: 52),
        SizedBox(height: 8),
        ShimmerLine(height: 52),
        SizedBox(height: 8),
        ShimmerLine(height: 52),
      ],
    );
  }
}

class _GuideSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.elevated,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerLine(width: 120, height: 14),
          SizedBox(height: 8),
          ShimmerLine(height: 12),
          SizedBox(height: 4),
          ShimmerLine(height: 12),
        ],
      ),
    );
  }
}
