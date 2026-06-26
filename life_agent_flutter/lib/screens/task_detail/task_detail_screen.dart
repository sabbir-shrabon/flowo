import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/task_models.dart';
import '../../providers/navigation_provider.dart';
import '../../services/adaptive_service.dart';
import '../../services/api_service.dart';
import '../../services/connectivity_service.dart';
import '../../utils/feature_flags.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_text.dart';
import '../../utils/error_handler.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/task_guide_widget.dart';
import '../../widgets/assistant_status_pill.dart';
import '../../widgets/inline_chat_bubble.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  final String taskId;

  const TaskDetailScreen({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  TaskDetailResponse? _detail;
  bool _loading = true;
  String? _error;
  String? _acting;

  // Inline chat
  List<_ChatMsg> _chatMessages = [];
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
    final cache = ref.read(localCacheProvider);
    final hasInternet = FeatureFlags.useNewConnectivityCheck
        ? await ConnectivityService().hasInternet()
        : await ref.read(connectivityProvider.future).catchError((_) => true);

    // 1. Check cache first
    final cached = cache.getCachedTaskDetail(widget.taskId);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _detail = cached;
          _loading = false;
          _error = null;
        });
      }
      return; // Fully loaded from cache
    }

    if (!hasInternet) {
      if (mounted) {
        setState(() {
          _error = 'Need internet to load task details.';
          _loading = false;
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await getTaskDetail(widget.taskId);
      await cache.saveTaskDetail(widget.taskId, data);

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

  Future<void> _handleStatusAction(TaskStatus status) async {
    setState(() => _acting = status.name);
    try {
      final payload = TaskUpdatePayload(taskId: widget.taskId, status: status);
      final hasInternet = FeatureFlags.useNewConnectivityCheck
          ? await ConnectivityService().hasInternet()
          : await ref.read(connectivityProvider.future).catchError((_) => true);

      if (!hasInternet) {
        await ref
            .read(localCacheProvider)
            .enqueuePendingSync('task_update', payload.toJson());
        ref.read(todayRefreshProvider.notifier).state++;
        if (mounted) {
          showSuccessSnackBar(
            context,
            'Offline: Status updated and queued for sync',
          );
          Navigator.pop(context, true);
        }
        return;
      }

      await updateTask(payload);
      ref.read(todayRefreshProvider.notifier).state++;
      if (mounted) {
        showSuccessSnackBar(
          context,
          status == TaskStatus.done ? 'Task completed!' : 'Task skipped',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _acting = null);
    }
  }

  Future<void> _handleChatSend() async {
    final content = _chatController.text.trim();
    if (content.isEmpty || _chatLoading) return;

    _chatController.clear();
    setState(() {
      _chatMessages.add(
        _ChatMsg(role: 'user', content: content, createdAt: DateTime.now()),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final api = ApiService();
      final res = await api.postJson('/api/chat', {
        'message': content,
        'source': 'task_detail',
        'task_id': widget.taskId,
      });
      final replyText = normalizeReplyText(res['reply']);
      setState(() {
        _chatMessages.add(
          _ChatMsg(
            role: 'assistant',
            content: replyText,
            createdAt: DateTime.now(),
          ),
        );
        _chatLoading = false;
      });


    } catch (_) {
      setState(() {
        _chatMessages.add(
          const _ChatMsg(
            role: 'assistant',
            content: "Sorry, I couldn't process that. Please try again.",
          ),
        );
        _chatLoading = false;
      });
    } finally {
      _scrollChatToBottom();
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
        _ChatMsg(
          role: 'user',
          content: newText.trim(),
          createdAt: DateTime.now(),
        ),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final api = ApiService();
      final res = await api.postJson('/api/chat', {
        'message': newText.trim(),
        'source': 'task_detail',
        'task_id': widget.taskId,
      });
      final replyText = normalizeReplyText(res['reply']);
      setState(() {
        _chatMessages.add(
          _ChatMsg(
            role: 'assistant',
            content: replyText,
            createdAt: DateTime.now(),
          ),
        );
        _chatLoading = false;
      });
    } catch (_) {
      setState(() {
        _chatMessages.add(
          const _ChatMsg(
            role: 'assistant',
            content: "Sorry, I couldn't process that. Please try again.",
          ),
        );
        _chatLoading = false;
      });
    } finally {
      _scrollChatToBottom();
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

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return context.colors.success;
      case 'intermediate':
      case 'medium':
        return context.colors.warning;
      case 'hard':
        return context.colors.error;
      default:
        return context.colors.warning;
    }
  }

  String _difficultyLabel(String difficulty) {
    switch (difficulty) {
      case 'easy':
        return 'Easy';
      case 'intermediate':
      case 'medium':
        return 'Medium';
      case 'hard':
        return 'Hard';
      default:
        return 'Medium';
    }
  }

  Widget _centeredDesktopContent(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail?.detail;
    final difficulty = detail?.estimatedDifficulty ?? 'intermediate';
    final diffColor = _difficultyColor(difficulty);
    final diffLabel = _difficultyLabel(difficulty);

    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Task Detail'),
            leading: null,
            floating: true,
            snap: true,
            actions: [
              if (_acting == null)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'done') _handleStatusAction(TaskStatus.done);
                    if (value == 'skip') {
                      _handleStatusAction(TaskStatus.skipped);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'done',
                      child: Text('Mark Done'),
                    ),
                    const PopupMenuItem(
                      value: 'skip',
                      child: Text('Skip Task'),
                    ),
                  ],
                ),
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
            ? _centeredDesktopContent(
                ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    // Difficulty badge placeholder
                    ShimmerLine(
                      width: 60,
                      height: 24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    ShimmerLine(height: 18),
                    const SizedBox(height: 8),
                    ShimmerLine(width: 200, height: 14),
                    const SizedBox(height: 20),
                    // Guide section
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShimmerLine(width: 80, height: 14),
                          const SizedBox(height: 10),
                          ShimmerLine(height: 12),
                          const SizedBox(height: 4),
                          ShimmerLine(height: 12),
                          const SizedBox(height: 4),
                          ShimmerLine(width: 180, height: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: ShimmerLine(
                            height: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ShimmerLine(
                            height: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              )
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
            : detail != null
            ? _centeredDesktopContent(
                RefreshIndicator(
                  onRefresh: _fetchDetail,
                  color: context.colors.accent,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      // Difficulty badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: diffColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              diffLabel,
                              style: TextStyle(
                                color: diffColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_detail!.generated)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.info.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                              child: Text(
                                'AI-Generated',
                                style: TextStyle(
                                  color: context.colors.info,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Task guide widget
                      TaskGuideWidget(detail: detail),

                      const SizedBox(height: 16),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _acting != null
                                  ? null
                                  : () => _handleStatusAction(TaskStatus.done),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Done'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: context.colors.success,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _acting != null
                                  ? null
                                  : () =>
                                        _handleStatusAction(TaskStatus.skipped),
                              icon: const Icon(Icons.skip_next, size: 18),
                              label: const Text('Skip'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.error,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Chat section
                      _buildChatSection(),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              )
            : Center(
                child: Text(
                  'Task detail not available.',
                  style: TextStyle(color: context.colors.textMuted),
                ),
              ),
      ),
    );
  }

  Widget _buildChatSection() {
    final hasInternetAsyncValue = ref.watch(connectivityProvider);
    final hasInternet = hasInternetAsyncValue.value ?? true;

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
            'Ask about this task',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          // Chat messages
          if (_chatMessages.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
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
                  return InlineChatBubble(
                    isUser: isUser,
                    content: msg.content,
                    createdAt: msg.createdAt,
                    // TaskDetailScreen is not under GoRouter context here; keep it simple.
                    onViewMemory: () {},
                    onRewrite: (_) {
                      setState(() => _editingIndex = index);
                    },
                    isEditing: _editingIndex == index,
                    onEditCancel: () => setState(() => _editingIndex = null),
                    onEditSubmit: (newText) =>
                        _handleEditSubmit(index, newText),
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
                  enabled: hasInternet,
                  style: TextStyle(
                    color: hasInternet
                        ? context.colors.textPrimary
                        : context.colors.textSecondary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: hasInternet
                        ? 'Ask about this task…'
                        : 'Chat requires internet connection',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _handleChatSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: (!hasInternet || _chatLoading)
                    ? null
                    : _handleChatSend,
                icon: Icon(
                  Icons.send,
                  color: hasInternet
                      ? context.colors.accent
                      : context.colors.textSecondary,
                  size: 20,
                ),
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

class _ChatMsg {
  final String role;
  final String content;
  final DateTime? createdAt;
  const _ChatMsg({required this.role, required this.content, this.createdAt});
}
