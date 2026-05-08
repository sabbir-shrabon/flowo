import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/daily_schedule_models.dart';
import '../../models/plan_models.dart';
import '../../models/task_models.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../utils/feature_flags.dart';
import '../../widgets/animations.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/assistant_status_pill.dart';
import '../../widgets/inline_chat_bubble.dart';
import '../../widgets/task_detail_card.dart';
import '../../services/connectivity_service.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  DailySchedule _schedule = DailySchedule.empty();
  List<TaskResponse> _tasks = [];
  bool _loading = true;
  String? _error;
  String? _actingTaskId;
  bool _showCompletion = false;
  bool _viewingOffline = false;
  bool _pullingExtraTasks = false;
  // True while a plan-adapt/update-triggered refresh is in progress.
  bool _adaptRefreshing = false;

  // Chat state
  List<_TodayChatMsg> _chatMessages = [];
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
  String? _selectedTaskTitle;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final authStatus = ref.read(authProvider.select((s) => s.status));
    final user = ref.read(authProvider).user;
    if (authStatus != AuthStatus.authenticated || user == null) {
      if (mounted) {
        setState(() {
          _schedule = DailySchedule.empty();
          _tasks = [];
          _loading = false;
          _viewingOffline = false;
        });
      }
      return;
    }

    final userId = user.id;
    final cache = ref.read(localCacheProvider);
    final hasInternet = FeatureFlags.useNewConnectivityCheck
        ? await ConnectivityService().hasInternet()
        : await ref.read(connectivityProvider.future).catchError((_) => true);

    // THE ONE RULE: Check working day index against cache FIRST.
    // If index matches cache, return cache immediately.
    // If index differs, clear cache and fetch fresh.
    final cachedSchedule = cache.getCachedDailySchedule(userId);

    // If offline and we have cache, use it
    if (!hasInternet) {
      if (cachedSchedule != null) {
        if (mounted) {
          setState(() {
            _schedule = cachedSchedule;
            _tasks = cachedSchedule.tasks;
            _loading = false;
            _viewingOffline = true;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'No cached data available offline';
            _viewingOffline = false;
          });
        }
      }
      return;
    }

    // Fetch fresh schedule to get current working day indices
    try {
      final freshSchedule = await getDailySchedule();

      // Check if working day indices match cache
      final workingDayMatches = _workingDayIndicesMatch(
        cachedSchedule,
        freshSchedule.plansWorkingDay,
      );

      // If working day matches and we have cache, use cache (the one rule)
      if (workingDayMatches && cachedSchedule != null) {
        // Merge done tasks from cache into the cached schedule
        final today = DateTime.now();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        if (cachedSchedule.date == todayStr) {
          if (mounted) {
            setState(() {
              _schedule = cachedSchedule;
              _tasks = cachedSchedule.tasks;
              _loading = false;
              _viewingOffline = false;
            });
          }
          return; // Cache is valid, stop here
        }
      }

      // Working day changed or no cache — clear and use fresh data
      if (cachedSchedule != null && !workingDayMatches) {
        cache.clearDailySchedule(userId);
      }

      // Keep done tasks visible for the entire calendar day.
      // The backend's /scheduler/daily only returns pending/upcoming tasks,
      // so we merge back any done tasks that were in today's cached snapshot
      // but are missing from the fresh response.
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      List<TaskResponse> mergedTasks = freshSchedule.tasks;
      if (cachedSchedule != null &&
          cachedSchedule.date == todayStr &&
          workingDayMatches) {
        final freshIds = {for (final t in freshSchedule.tasks) t.id};
        final doneTodayFromCache = cachedSchedule.tasks
            .where(
              (t) => t.status == TaskStatus.done && !freshIds.contains(t.id),
            )
            .toList();
        if (doneTodayFromCache.isNotEmpty) {
          mergedTasks = [...freshSchedule.tasks, ...doneTodayFromCache];
        }
      }

      // Persist the merged view so cache also holds done tasks for the day
      final mergedSchedule = DailySchedule(
        date: freshSchedule.date,
        tasks: mergedTasks,
        totalAvailable: freshSchedule.totalAvailable,
        selectedCount: freshSchedule.selectedCount,
        maxTasksPerDay: freshSchedule.maxTasksPerDay,
        selectedTaskIds: [
          ...freshSchedule.selectedTaskIds,
          ...mergedTasks
              .where(
                (t) =>
                    t.status == TaskStatus.done &&
                    !freshSchedule.selectedTaskIds.contains(t.id),
              )
              .map((t) => t.id),
        ],
        plansMetadata: freshSchedule.plansMetadata,
        milestonesMetadata: freshSchedule.milestonesMetadata,
        metadata: freshSchedule.metadata,
        plansWorkingDay: freshSchedule.plansWorkingDay,
      );
      await cache.saveDailySchedule(userId, mergedSchedule);

      if (mounted) {
        setState(() {
          _schedule = mergedSchedule;
          _tasks = mergedTasks;
          _loading = false;
          _viewingOffline = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _viewingOffline = cachedSchedule != null;
          if (_tasks.isEmpty) {
            _error = friendlyErrorMessage(e);
          }
          _loading = false;
        });
      }
    }
  }

  /// Check if cached working day indices match the fresh indices.
  /// This is the key to detecting day transitions.
  bool _workingDayIndicesMatch(
    DailySchedule? cached,
    Map<String, int> freshWorkingDay,
  ) {
    if (cached == null) return false;
    if (cached.plansWorkingDay.isEmpty && freshWorkingDay.isEmpty) return true;
    if (cached.plansWorkingDay.length != freshWorkingDay.length) return false;

    for (final entry in freshWorkingDay.entries) {
      final cachedValue = cached.plansWorkingDay[entry.key];
      if (cachedValue != entry.value) return false;
    }
    return true;
  }

  /// Hard refresh: forces a network fetch by clearing the stale cache,
  /// but preserves today's done tasks so they stay visible all day.
  Future<void> _hardRefresh() async {
    final user = ref.read(authProvider).user;

    // 1. Snapshot today's done tasks from in-memory state BEFORE clearing
    //    anything — they won't come back from the backend.
    final doneTodaySnapshot = _tasks
        .where((t) => t.status == TaskStatus.done)
        .toList();

    // 2. Clear the cache so _fetchData skips stale data and hits the network
    if (user != null) {
      ref.read(localCacheProvider).clearDailySchedule(user.id);
    }

    // 3. Show loading state immediately
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _tasks = [];
        _schedule = DailySchedule.empty();
        _viewingOffline = false;
      });
    }

    // 4. Full network fetch (cache is empty so no stale data is served first)
    await _fetchData();

    // 5. Re-merge done tasks that the backend dropped from the fresh response
    if (mounted && doneTodaySnapshot.isNotEmpty) {
      final freshIds = {for (final t in _tasks) t.id};
      final missingDone = doneTodaySnapshot
          .where((t) => !freshIds.contains(t.id))
          .toList();
      if (missingDone.isNotEmpty) {
        final merged = [..._tasks, ...missingDone];
        final mergedSchedule = DailySchedule(
          date: _schedule.date,
          tasks: merged,
          totalAvailable: _schedule.totalAvailable,
          selectedCount: _schedule.selectedCount,
          maxTasksPerDay: _schedule.maxTasksPerDay,
          selectedTaskIds: [
            ..._schedule.selectedTaskIds,
            ...missingDone
                .where((t) => !_schedule.selectedTaskIds.contains(t.id))
                .map((t) => t.id),
          ],
          plansMetadata: _schedule.plansMetadata,
          milestonesMetadata: _schedule.milestonesMetadata,
          metadata: _schedule.metadata,
          plansWorkingDay: _schedule.plansWorkingDay,
        );
        if (user != null) {
          await ref
              .read(localCacheProvider)
              .saveDailySchedule(user.id, mergedSchedule);
        }
        setState(() {
          _tasks = merged;
          _schedule = mergedSchedule;
        });
      }
    }
  }

  Future<void> _handleCheckDone(String taskId) async {
    setState(() => _actingTaskId = taskId);

    final original = _tasks.where((t) => t.id == taskId).firstOrNull;
    final newTasks = _tasks
        .map(
          (t) => t.id == taskId ? _copyTaskWithStatus(t, TaskStatus.done) : t,
        )
        .toList();

    final updatedSchedule = DailySchedule(
      date: _schedule.date,
      tasks: newTasks,
      totalAvailable: _schedule.totalAvailable,
      selectedCount: _schedule.selectedCount,
      maxTasksPerDay: _schedule.maxTasksPerDay,
      selectedTaskIds: _schedule.selectedTaskIds,
      plansMetadata: _schedule.plansMetadata,
      milestonesMetadata: _schedule.milestonesMetadata,
      metadata: _schedule.metadata,
      plansWorkingDay: _schedule.plansWorkingDay,
    );

    setState(() {
      _tasks = newTasks;
      _schedule = updatedSchedule;
    });

    final user = ref.read(authProvider).user;
    if (user != null) {
      ref.read(localCacheProvider).saveDailySchedule(user.id, updatedSchedule);
    }

    try {
      final payload = TaskUpdatePayload(
        taskId: taskId,
        status: TaskStatus.done,
      );
      final hasInternet = FeatureFlags.useNewConnectivityCheck
          ? await ConnectivityService().hasInternet()
          : await ref.read(connectivityProvider.future).catchError((_) => true);

      if (!hasInternet) {
        await ref
            .read(localCacheProvider)
            .enqueuePendingSync('task_update', payload.toJson());
        if (mounted) {
          setState(() => _showCompletion = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Offline: Will sync when online',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: context.colors.accent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      await updateTask(payload);
      if (mounted) {
        setState(() => _showCompletion = true);
      }
    } catch (e) {
      if (mounted) {
        final revertedTasks = _tasks
            .map(
              (t) => t.id == taskId
                  ? _copyTaskWithStatus(
                      t,
                      original?.status ?? TaskStatus.pending,
                    )
                  : t,
            )
            .toList();

        final revertedSchedule = DailySchedule(
          date: _schedule.date,
          tasks: revertedTasks,
          totalAvailable: _schedule.totalAvailable,
          selectedCount: _schedule.selectedCount,
          maxTasksPerDay: _schedule.maxTasksPerDay,
          selectedTaskIds: _schedule.selectedTaskIds,
          plansMetadata: _schedule.plansMetadata,
          milestonesMetadata: _schedule.milestonesMetadata,
          metadata: _schedule.metadata,
          plansWorkingDay: _schedule.plansWorkingDay,
        );

        setState(() {
          _tasks = revertedTasks;
          _schedule = revertedSchedule;
        });

        if (user != null) {
          ref
              .read(localCacheProvider)
              .saveDailySchedule(user.id, revertedSchedule);
        }
        showErrorSnackBar(context, e, onRetry: () => _handleCheckDone(taskId));
      }
    } finally {
      if (mounted) setState(() => _actingTaskId = null);
    }
  }

  Future<void> _handleUncheck(String taskId) async {
    setState(() => _actingTaskId = taskId);

    final original = _tasks.where((t) => t.id == taskId).firstOrNull;

    final newTasks = _tasks
        .map(
          (t) =>
              t.id == taskId ? _copyTaskWithStatus(t, TaskStatus.pending) : t,
        )
        .toList();

    final updatedSchedule = DailySchedule(
      date: _schedule.date,
      tasks: newTasks,
      totalAvailable: _schedule.totalAvailable,
      selectedCount: _schedule.selectedCount,
      maxTasksPerDay: _schedule.maxTasksPerDay,
      selectedTaskIds: _schedule.selectedTaskIds,
      plansMetadata: _schedule.plansMetadata,
      milestonesMetadata: _schedule.milestonesMetadata,
      metadata: _schedule.metadata,
      plansWorkingDay: _schedule.plansWorkingDay,
    );

    setState(() {
      _tasks = newTasks;
      _schedule = updatedSchedule;
    });

    final user = ref.read(authProvider).user;
    if (user != null) {
      ref.read(localCacheProvider).saveDailySchedule(user.id, updatedSchedule);
    }

    try {
      final payload = TaskUpdatePayload(
        taskId: taskId,
        status: TaskStatus.pending,
      );
      final hasInternet = FeatureFlags.useNewConnectivityCheck
          ? await ConnectivityService().hasInternet()
          : await ref.read(connectivityProvider.future).catchError((_) => true);

      if (!hasInternet) {
        await ref
            .read(localCacheProvider)
            .enqueuePendingSync('task_update', payload.toJson());
        return;
      }

      await updateTask(payload);
    } catch (e) {
      if (mounted) {
        final revertedTasks = _tasks
            .map(
              (t) => t.id == taskId
                  ? _copyTaskWithStatus(t, original?.status ?? TaskStatus.done)
                  : t,
            )
            .toList();

        final revertedSchedule = DailySchedule(
          date: _schedule.date,
          tasks: revertedTasks,
          totalAvailable: _schedule.totalAvailable,
          selectedCount: _schedule.selectedCount,
          maxTasksPerDay: _schedule.maxTasksPerDay,
          selectedTaskIds: _schedule.selectedTaskIds,
          plansMetadata: _schedule.plansMetadata,
          milestonesMetadata: _schedule.milestonesMetadata,
          metadata: _schedule.metadata,
          plansWorkingDay: _schedule.plansWorkingDay,
        );

        setState(() {
          _tasks = revertedTasks;
          _schedule = revertedSchedule;
        });

        if (user != null) {
          ref
              .read(localCacheProvider)
              .saveDailySchedule(user.id, revertedSchedule);
        }
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _actingTaskId = null);
    }
  }

  Future<void> _showPullExtraDialog() async {
    final count = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('How many more tasks?'),
          content: const Text('Choose a small extra batch for today.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(1),
              child: const Text('1'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(2),
              child: const Text('2'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(3),
              child: const Text('Max 3'),
            ),
          ],
        );
      },
    );
    if (count == null) return;
    await _handlePullExtra(count);
  }

  Future<void> _handlePullExtra(int count) async {
    setState(() => _pullingExtraTasks = true);
    try {
      final hasInternet = FeatureFlags.useNewConnectivityCheck
          ? await ConnectivityService().hasInternet()
          : await ref.read(connectivityProvider.future).catchError((_) => true);
      if (!hasInternet) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Connect to the internet to pull more tasks',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: context.colors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final freshSchedule = await pullExtraDailyTasks(count);
      final user = ref.read(authProvider).user;
      if (user != null) {
        await ref
            .read(localCacheProvider)
            .saveDailySchedule(user.id, freshSchedule);
      }
      if (mounted) {
        setState(() {
          _schedule = freshSchedule;
          _tasks = freshSchedule.tasks;
          _viewingOffline = false;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _pullingExtraTasks = false);
    }
  }

  TaskResponse _copyTaskWithStatus(TaskResponse t, TaskStatus status) {
    return TaskResponse(
      id: t.id,
      planId: t.planId,
      title: t.title,
      description: t.description,
      dueDate: t.dueDate,
      status: status,
      priority: t.priority,
      difficulty: t.difficulty,
      parentId: t.parentId,
      carryOverCount: t.carryOverCount,
      milestoneId: t.milestoneId,
      orderIndex: t.orderIndex,
      durationMinutes: t.durationMinutes,
      createdAt: t.createdAt,
      updatedAt: t.updatedAt,
      detailJson: t.detailJson,
      rescheduledFrom: t.rescheduledFrom,
      struggling: t.struggling,
      skipReason: t.skipReason,
      skippedAt: t.skippedAt,
    );
  }

  Future<void> _handleChatTaskTap(TaskResponse task) async {
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

  Future<void> _handleSendChat() async {
    final content = _chatController.text.trim();
    if (content.isEmpty || _chatLoading) return;

    _chatController.clear();
    setState(() {
      _chatMessages.add(
        _TodayChatMsg(
          role: 'user',
          content: content,
          createdAt: DateTime.now(),
        ),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final res = await sendTodayChat(content, taskId: _selectedTaskId);
      setState(() {
        _chatMessages.add(
          _TodayChatMsg(
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
        await _fetchData();
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(
          _TodayChatMsg(role: 'assistant', content: 'Error: $e'),
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
        _TodayChatMsg(
          role: 'user',
          content: newText.trim(),
          createdAt: DateTime.now(),
        ),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    try {
      final res = await sendTodayChat(newText.trim(), taskId: _selectedTaskId);
      setState(() {
        _chatMessages.add(
          _TodayChatMsg(
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
        await _fetchData();
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(
          _TodayChatMsg(role: 'assistant', content: 'Error: $e'),
        );
        _chatLoading = false;
      });
    }
  }

  String _getUserFirstName() {
    final user = ref.read(authProvider).user;
    if (user == null) return 'there';

    // Try to get name from user metadata
    final metadata = user.userMetadata;
    if (metadata != null) {
      final name = metadata['name'] ?? metadata['full_name'];
      if (name != null && name is String && name.isNotEmpty) {
        return name.split(' ').first;
      }
    }

    // Fallback to email username
    final email = user.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return 'there';
  }

  String _formatTimeRemaining() {
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
    final diff = endOfDay.difference(now);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;

    if (hours > 0) {
      return '$hours hr $minutes min left today';
    }
    return '$minutes min left today';
  }

  /// Full hard refresh triggered when a plan is adapted/updated.
  /// Shows a loading spinner immediately and clears stale data.
  Future<void> _fetchDataAfterAdapt() async {
    if (mounted) {
      setState(() {
        _adaptRefreshing = true;
        _loading = true;
        _error = null;
      });
    }
    await _fetchData();
    if (mounted) {
      setState(() => _adaptRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(todayRefreshProvider, (_, _) => _fetchData());

    // When a plan is adapted/updated from any screen, do a hard refresh
    // and immediately show the loading spinner so the user sees progress.
    ref.listen<int>(
      todayAdaptRefreshProvider,
      (_, _) => _fetchDataAfterAdapt(),
    );

    ref.listen(authProvider.select((s) => s.status), (prev, next) {
      if (prev != AuthStatus.authenticated &&
          next == AuthStatus.authenticated) {
        _fetchData();
      }
    });

    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, MMMM d').format(now);
    final timeRemaining = _formatTimeRemaining();
    final firstName = _getUserFirstName();

    final visibleTasks = _tasks
        .where(
          (t) =>
              t.status == TaskStatus.pending ||
              t.status == TaskStatus.partial ||
              t.status == TaskStatus.done,
        )
        .toList();
    final completedCount = _tasks
        .where((t) => t.status == TaskStatus.done)
        .length;
    final hasPendingOrPartial = _tasks.any(
      (t) => t.status == TaskStatus.pending || t.status == TaskStatus.partial,
    );
    final dayComplete = _tasks.isNotEmpty && !hasPendingOrPartial;

    // Group visible tasks by plan ID. Completed tasks stay in the locked
    // backend batch, but disappear from Today so the list can shrink.
    final orderByTaskId = <String, int>{
      for (int i = 0; i < _schedule.selectedTaskIds.length; i++)
        _schedule.selectedTaskIds[i]: i,
    };
    final tasksByPlan = <String, List<TaskResponse>>{};
    for (final task in visibleTasks) {
      tasksByPlan.putIfAbsent(task.planId, () => []).add(task);
    }

    int firstTaskOrder(String planId) {
      final planTasks = tasksByPlan[planId] ?? const <TaskResponse>[];
      if (planTasks.isEmpty) return 1 << 30;
      return planTasks
          .map((task) => orderByTaskId[task.id] ?? visibleTasks.indexOf(task))
          .reduce((a, b) => a < b ? a : b);
    }

    // Preserve the backend schedule order across plan groups.
    final sortedPlanIds = tasksByPlan.keys.toList()
      ..sort((a, b) {
        final bySchedule = firstTaskOrder(a).compareTo(firstTaskOrder(b));
        if (bySchedule != 0) return bySchedule;
        final titleA = _schedule.plansMetadata[a]?.title ?? '';
        final titleB = _schedule.plansMetadata[b]?.title ?? '';
        return titleA.compareTo(titleB);
      });

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Stack(
        children: [
          Column(
            children: [
              // FIXED HEADER: Date and time remaining
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                decoration: BoxDecoration(
                  color: context.colors.background,
                  border: Border(
                    bottom: BorderSide(color: context.colors.border, width: 1),
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateStr,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeRemaining,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (MediaQuery.of(context).size.width >= 600)
                            TextButton.icon(
                              onPressed: () => setState(
                                () => _chatExpanded = !_chatExpanded,
                              ),
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
                          if (MediaQuery.of(context).size.width >= 600)
                            const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loading ? null : _hardRefresh,
                            tooltip: 'Hard refresh — clears cache & reloads',
                            color: context.colors.textSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 12),
                          if (_tasks.isNotEmpty)
                            Flexible(
                              child: Text(
                                '$completedCount/${_tasks.length} done',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (MediaQuery.of(context).size.width < 1200) ...[
                            if (_tasks.isNotEmpty) const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.more_vert),
                              onPressed: () {
                                ref.read(sidebarOpenProvider.notifier).state =
                                    !ref.read(sidebarOpenProvider);
                              },
                              color: context.colors.textSecondary,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // SCROLLABLE CONTENT: Greeting + Tasks
              // Adapt-refresh banner — visible while plan-triggered reload is running
              if (_adaptRefreshing)
                Material(
                  color: context.colors.accent,
                  child: InkWell(
                    onTap: _fetchDataAfterAdapt,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Updating your schedule…',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            'Reload',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _hardRefresh,
                  color: context.colors.accent,
                  child: _loading
                      ? _buildLoadingState()
                      : _error != null
                      ? _buildErrorState()
                      : _tasks.isEmpty
                      ? _buildEmptyState(firstName)
                      : _buildTaskList(
                          sortedPlanIds,
                          orderByTaskId,
                          visibleTasks,
                          dayComplete,
                          firstName,
                        ),
                ),
              ),
            ],
          ),

          // Completion animation overlay
          if (_showCompletion)
            Positioned.fill(
              child: RepaintBoundary(
                child: Center(
                  child: TaskCompletionAnimation(
                    onDone: () {
                      if (mounted) setState(() => _showCompletion = false);
                    },
                  ),
                ),
              ),
            ),

          // Sidebar chat (desktop/tablet)
          if (MediaQuery.of(context).size.width >= 600 && _chatExpanded)
            _buildSidebarChat(),

          // Mobile chat bar (narrow screens)
          if (MediaQuery.of(context).size.width < 600) _buildMobileChatBar(),
        ],
      ),
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
          hasTask ? (_selectedTaskTitle ?? 'Task Chat') : 'Today Chat',
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
              : 'Ask about your schedule, get advice, or manage tasks.',
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
                      : 'Ask about today…',
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
                                  'Today Chat',
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
                          'Today Chat',
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

  Widget _buildLoadingState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        ShimmerLine(height: 24, width: 150),
        const SizedBox(height: 24),
        ShimmerLine(height: 20, width: 200),
        const SizedBox(height: 16),
        ShimmerLine(height: 56),
        const SizedBox(height: 8),
        ShimmerLine(height: 56),
        const SizedBox(height: 8),
        ShimmerLine(height: 56),
      ],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.cloud_off, size: 48, color: context.colors.textMuted),
        const SizedBox(height: 16),
        Text(
          'Could not load your tasks',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _error ?? 'Something went wrong',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton(
            onPressed: _hardRefresh,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String firstName) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.wb_sunny_outlined,
          size: 64,
          color: context.colors.accent.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 24),
        Text(
          'Hey $firstName!',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          "Nothing scheduled for today.\nEnjoy your day or go to Chat to create a plan.",
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 15,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Center(
          child: FilledButton.icon(
            onPressed: () => context.go('/chat'),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Go to Chat'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDayCompleteState(String firstName) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 56),
        _buildDayCompleteContent(firstName),
      ],
    );
  }

  Widget _buildDayCompleteContent(String firstName) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 68,
          color: context.colors.accent,
        ),
        const SizedBox(height: 22),
        Text(
          'Day complete, $firstName.',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'You finished today\'s locked batch.',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 15,
            height: 1.45,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        Center(
          child: FilledButton.icon(
            onPressed: _pullingExtraTasks ? null : _showPullExtraDialog,
            icon: _pullingExtraTasks
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.surface,
                    ),
                  )
                : const Icon(Icons.add_task),
            label: const Text('I have more time. Give me another.'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.accent,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskList(
    List<String> sortedPlanIds,
    Map<String, int> orderByTaskId,
    List<TaskResponse> visibleTasks,
    bool dayComplete,
    String firstName,
  ) {
    final hasInternetAsyncValue = ref.watch(connectivityProvider);
    final hasInternet = hasInternetAsyncValue.value ?? true;

    return CustomScrollView(
      slivers: [
        if (!hasInternet || _viewingOffline)
          SliverToBoxAdapter(
            child: Container(
              color: context.colors.error.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: context.colors.error),
                  const SizedBox(width: 8),
                  Text(
                    'Viewing offline schedule',
                    style: TextStyle(
                      color: context.colors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Greeting
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'Hey ${_getUserFirstName()}!',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ),

        // Tasks grouped by plan
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final planId = sortedPlanIds[index];
              final plan = _schedule.plansMetadata[planId];
              final tasks =
                  visibleTasks.where((t) => t.planId == planId).toList()..sort(
                    (a, b) => (orderByTaskId[a.id] ?? 1 << 30).compareTo(
                      orderByTaskId[b.id] ?? 1 << 30,
                    ),
                  );

              return _PlanTaskGroup(
                planTitle: plan?.title ?? 'Tasks',
                milestonesMetadata: _schedule.milestonesMetadata,
                tasks: tasks,
                orderByTaskId: orderByTaskId,
                actingTaskId: _actingTaskId,
                onCheckDone: _handleCheckDone,
                onUncheck: _handleUncheck,
                onTaskTap: _handleChatTaskTap,
              );
            }, childCount: sortedPlanIds.length),
          ),
        ),

        if (dayComplete)
          SliverToBoxAdapter(child: _buildDayCompleteContent(firstName)),

        // Bottom padding
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

// ── Task Group Widget ─────────────────────────────────────────────────────────

class _PlanTaskGroup extends StatelessWidget {
  final String planTitle;
  final Map<String, MilestoneSummary> milestonesMetadata;
  final List<TaskResponse> tasks;
  final Map<String, int> orderByTaskId;
  final String? actingTaskId;
  final void Function(String) onCheckDone;
  final void Function(String) onUncheck;
  final void Function(TaskResponse) onTaskTap;

  const _PlanTaskGroup({
    required this.planTitle,
    required this.milestonesMetadata,
    required this.tasks,
    required this.orderByTaskId,
    required this.actingTaskId,
    required this.onCheckDone,
    required this.onUncheck,
    required this.onTaskTap,
  });

  @override
  Widget build(BuildContext context) {
    final tasksByMilestone = <String, List<TaskResponse>>{};
    for (final task in tasks) {
      final key = task.milestoneId ?? '';
      tasksByMilestone.putIfAbsent(key, () => []).add(task);
    }

    final sortedMilestoneIds = tasksByMilestone.keys.toList();
    sortedMilestoneIds.sort((a, b) {
      final orderA =
          milestonesMetadata[a]?.orderIndex ?? (a.isEmpty ? 1 << 30 : 1 << 29);
      final orderB =
          milestonesMetadata[b]?.orderIndex ?? (b.isEmpty ? 1 << 30 : 1 << 29);
      if (orderA != orderB) return orderA.compareTo(orderB);
      final titleA = milestonesMetadata[a]?.title ?? '';
      final titleB = milestonesMetadata[b]?.title ?? '';
      return titleA.compareTo(titleB);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plan name as muted label
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
          child: Text(
            planTitle,
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),

        // Task list grouped by milestone metadata from the daily schedule.
        ...sortedMilestoneIds.expand((milestoneId) {
          final milestone = milestonesMetadata[milestoneId];
          final milestoneTasks = tasksByMilestone[milestoneId]!
            ..sort((a, b) {
              final bySchedule = (orderByTaskId[a.id] ?? 1 << 30).compareTo(
                orderByTaskId[b.id] ?? 1 << 30,
              );
              if (bySchedule != 0) return bySchedule;
              return a.orderIndex.compareTo(b.orderIndex);
            });

          return [
            if (milestone != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 0, 4),
                child: Text(
                  milestone.title,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...milestoneTasks.map(
              (task) => _TaskRow(
                task: task,
                isActing: actingTaskId == task.id,
                onCheck: () {
                  if (task.status == TaskStatus.done) {
                    onUncheck(task.id);
                  } else {
                    onCheckDone(task.id);
                  }
                },
                onTap: () => onTaskTap(task),
              ),
            ),
          ];
        }),
      ],
    );
  }
}

// ── Task Row Widget ───────────────────────────────────────────────────────────

class _TaskRow extends StatelessWidget {
  final TaskResponse task;
  final bool isActing;
  final VoidCallback onCheck;
  final VoidCallback onTap;

  const _TaskRow({
    required this.task,
    required this.isActing,
    required this.onCheck,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.done;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 40,
              height: 40,
              child: isActing
                  ? Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.accent,
                        ),
                      ),
                    )
                  : Checkbox(
                      value: isDone,
                      onChanged: (_) => onCheck(),
                      activeColor: context.colors.accent,
                      side: BorderSide(
                        color: context.colors.borderStrong,
                        width: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
            ),

            const SizedBox(width: 8),

            // Task title
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isDone
                      ? context.colors.textMuted
                      : context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  decorationColor: context.colors.textMuted,
                  decorationThickness: 2,
                ),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isDone ? 0.6 : 1.0,
                  child: Text(task.title),
                ),
              ),
            ),

            // Duration (if available)
            if (task.durationMinutes != null) ...[
              Flexible(
                child: Text(
                  '${task.durationMinutes} min',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Arrow
            Icon(
              Icons.chevron_right,
              color: context.colors.textMuted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayChatMsg {
  final String role;
  final String content;
  final List<PlanChatAction>? actions;
  final DateTime? createdAt;

  _TodayChatMsg({
    required this.role,
    required this.content,
    this.actions,
    this.createdAt,
  });
}
