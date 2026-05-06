import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/chat_models.dart';
import '../models/plan_models.dart';
import '../providers/auth_provider.dart';
import '../providers/navigation_provider.dart';
import '../widgets/auth_modal.dart';
import '../services/adaptive_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/adapt_with_plan_popup.dart';
import '../widgets/plan_settings_dialog.dart';
import '../widgets/app_settings_dialog.dart';

/// Caches active plans so the drawer doesn't flash empty while reloading on mobile
final activePlansCacheProvider = StateProvider<List<PlanResponse>>((ref) => []);

class AppDrawer extends ConsumerStatefulWidget {
  final bool isPermanent;
  const AppDrawer({super.key, this.isPermanent = false});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  List<ConversationSummary> _conversations = [];
  List<PlanResponse> _plans = [];
  bool _historyOpen = false;      // lazy: collapsed by default
  bool _activePlansOpen = true;   // expanded by default
  bool _plansMenuOpen = true;     // expanded by default
  bool _conversationsLoaded = false; // track if conversations fetched
  String? _contextMenuConvId;
  String? _contextMenuPlanId;
  String? _renamingConvId;
  String? _renamingPlanId;
  final _renameController = TextEditingController();
  final _planRenameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load from cache immediately to prevent delay on mobile drawer open
    _plans = ref.read(activePlansCacheProvider);
    _fetchData();
  }

  @override
  void dispose() {
    _renameController.dispose();
    _planRenameController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    // Skip API calls when unauthenticated
    final authStatus = ref.read(authProvider.select((s) => s.status));
    if (authStatus != AuthStatus.authenticated) {
      if (mounted) {
        setState(() {
          _plans = [];
        });
      }
      return;
    }
    try {
      // Always load plans; conversations loaded lazily when history expanded
      final plans = await listActivePlans();
      ref.read(activePlansCacheProvider.notifier).state = plans;
      if (mounted) {
        setState(() {
          _plans = plans;
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchConversations() async {
    if (_conversationsLoaded) return;
    try {
      final convs = await listConversations();
      if (mounted) {
        setState(() {
          _conversations = convs.where((c) => c.archived != true).toList();
          _conversationsLoaded = true;
        });
      }
    } catch (_) {}
  }

  void _navigateAndClose(String location) {
    if (!widget.isPermanent) {
      Navigator.pop(context);
    }
    context.go(location);
  }

  // ── Conversation helpers ──────────────────────────────────────────────────

  void _handleConversationTap(String convId) {
    if (_renamingConvId != null) return;
    _closeContextMenus();
    ref.read(conversationToLoadProvider.notifier).state = convId;
    if (!widget.isPermanent) {
      Navigator.pop(context);
    }
    context.go('/chat');
  }

  void _handleRenameConv(String convId) {
    _closeContextMenus();
    final conv = _conversations.where((c) => c.id == convId).firstOrNull;
    if (conv == null) return;
    setState(() {
      _renamingConvId = convId;
      _renameController.text = conv.title;
    });
  }

  Future<void> _submitRenameConv(String convId) async {
    final newTitle = _renameController.text.trim();
    if (newTitle.isEmpty) {
      setState(() {
        _renamingConvId = null;
      });
      return;
    }
    try {
      await renameConversation(convId, newTitle);
      setState(() {
        _conversations = _conversations
            .map(
              (c) => c.id == convId
                  ? ConversationSummary(
                      id: c.id,
                      title: newTitle,
                      preview: c.preview,
                      messageCount: c.messageCount,
                      archived: c.archived,
                      updatedAt: c.updatedAt,
                    )
                  : c,
            )
            .toList();
      });
    } catch (_) {}
    setState(() {
      _renamingConvId = null;
    });
  }

  Future<void> _handleDeleteConv(String convId) async {
    _closeContextMenus();
    try {
      await deleteConversation(convId);
      setState(() {
        _conversations = _conversations.where((c) => c.id != convId).toList();
      });
      ref.read(conversationsRefreshProvider.notifier).state++;
    } catch (_) {}
  }

  Future<void> _handleArchiveConv(String convId) async {
    _closeContextMenus();
    try {
      final api = ApiService();
      await api.patchJson('/api/conversations/$convId', {'archived': true});
      setState(() {
        _conversations = _conversations.where((c) => c.id != convId).toList();
      });
    } catch (_) {}
  }

  // ── Plan helpers ──────────────────────────────────────────────────────────

  void _handlePlanTap(String planId) {
    if (_contextMenuPlanId != null) return;
    _closeContextMenus();
    if (!widget.isPermanent) {
      Navigator.pop(context);
    }
    context.push('/plans/$planId');
  }

  Future<void> _submitRenamePlan(String planId) async {
    final newTitle = _planRenameController.text.trim();
    if (newTitle.isEmpty) {
      setState(() {
        _renamingPlanId = null;
      });
      return;
    }
    try {
      await patchPlan(planId, PlanUpdatePayload(title: newTitle));
      setState(() {
        _plans = _plans
            .map(
              (p) => p.id == planId
                  ? PlanResponse(
                      id: p.id,
                      goalId: p.goalId,
                      memoryId: p.memoryId,
                      userId: p.userId,
                      title: newTitle,
                      status: p.status,
                      priority: p.priority,
                      intensity: p.intensity,
                      durationDays: p.durationDays,
                      schedulePrefs: p.schedulePrefs,
                      progressPct: p.progressPct,
                      createdAt: p.createdAt,
                      updatedAt: p.updatedAt,
                    )
                  : p,
            )
            .toList();
      });
      ref.read(activePlansCacheProvider.notifier).state = _plans;
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (_) {}
    setState(() {
      _renamingPlanId = null;
    });
  }

  Future<void> _handleDeletePlan(String planId) async {
    _closeContextMenus();
    try {
      await deletePlan(planId);
      setState(() {
        _plans = _plans.where((p) => p.id != planId).toList();
      });
      ref.read(activePlansCacheProvider.notifier).state = _plans;
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (_) {}
  }

  Future<void> _handlePausePlan(String planId) async {
    _closeContextMenus();
    try {
      await pausePlan(planId);
      await _fetchData();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (_) {}
  }

  Future<void> _handleResumePlan(String planId) async {
    _closeContextMenus();
    try {
      await resumePlan(planId);
      await _fetchData();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (_) {}
  }

  Future<void> _adaptPlanWithResult(
    PlanResponse plan,
    AdaptPlanResult result,
  ) async {
    try {
      await adaptPlan(
        plan.id,
        durationDays: result.durationDays,
        workingDays: result.workingDays,
      );
      await _fetchData();
      // Hard refresh today screen (shows loading spinner) and navigate there
      ref.read(todayAdaptRefreshProvider.notifier).state++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Plan adapted! Tasks scheduled over ${result.durationDays} days.',
              style: TextStyle(color: context.colors.background),
            ),
            backgroundColor: context.colors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Navigate to today screen to show updated schedule instantly
        _navigateAndClose('/today');
      }
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _openPlanSettings(PlanResponse plan) {
    _closeContextMenus();
    return showPlanSettingsDialog(
      context,
      plan: plan,
      onRename: (title) async {
        await patchPlan(plan.id, PlanUpdatePayload(title: title));
        await _fetchData();
        ref.read(todayRefreshProvider.notifier).state++;
      },
      onPause: plan.status == PlanStatus.active
          ? () async => _handlePausePlan(plan.id)
          : null,
      onResume: plan.status == PlanStatus.paused
          ? () async => _handleResumePlan(plan.id)
          : null,
      onDelete: () async => _handleDeletePlan(plan.id),
      onAdapt: (result) => _adaptPlanWithResult(plan, result),
    );
  }

  void _closeContextMenus() {
    setState(() {
      _contextMenuConvId = null;
      _contextMenuPlanId = null;
    });
  }

  // ── Group conversations by date ───────────────────────────────────────────

  List<_ConversationGroup> _groupConversations() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = [
      _ConversationGroup(label: 'Today', items: []),
      _ConversationGroup(label: 'Yesterday', items: []),
      _ConversationGroup(label: 'Previous 7 days', items: []),
      _ConversationGroup(label: 'Older', items: []),
    ];

    for (final conv in _conversations) {
      final updated = conv.updatedAt != null
          ? DateTime.tryParse(conv.updatedAt!) ?? now
          : now;
      final dateOnly = DateTime(updated.year, updated.month, updated.day);
      if (dateOnly.isAtSameMomentAs(today) || dateOnly.isAfter(today)) {
        groups[0].items.add(conv);
      } else if (dateOnly.isAtSameMomentAs(yesterday) ||
          dateOnly.isAfter(yesterday)) {
        groups[1].items.add(conv);
      } else if (dateOnly.isAfter(weekAgo) ||
          dateOnly.isAtSameMomentAs(weekAgo)) {
        groups[2].items.add(conv);
      } else {
        groups[3].items.add(conv);
      }
    }

    return groups.where((g) => g.items.isNotEmpty).toList();
  }

  Color _planColor(int index) {
    const colors = [
      Color(0xFF3DD6B5),
      Color(0xFF5B9CF6),
      Color(0xFFE8A843),
      Color(0xFFE8605A),
      Color(0xFF7B7A94),
      Color(0xFF9B8FE8),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isUnauthenticated = authState.status == AuthStatus.unauthenticated;
    final userEmail = authState.user?.email ?? '';
    final currentLocation = GoRouterState.of(context).matchedLocation;

    // Refresh data when auth state changes
    ref.listen(authProvider.select((s) => s.status), (prev, next) {
      if (prev != AuthStatus.authenticated &&
          next == AuthStatus.authenticated) {
        _fetchData();
      }
    });

    final drawerContent = Column(
      children: [
        // Brand header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
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
                      'Life Agent',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'by getplan.to',
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () {
                  if (widget.isPermanent) {
                    ref.read(sidebarOpenProvider.notifier).state = false;
                  } else {
                    Navigator.pop(context);
                  }
                },
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Navigation items
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 8,
                  ),
                  child: Column(
                    children: [
                      _navItem(
                        icon: Icons.today,
                        label: 'Today',
                        active: currentLocation == '/today',
                        onTap: () => _navigateAndClose('/today'),
                      ),
                      Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          initiallyExpanded: true,
                          maintainState: true,
                          onExpansionChanged: (open) {
                            setState(() => _plansMenuOpen = open);
                          },
                          leading: Icon(
                            Icons.inventory_2_outlined,
                            size: 20,
                            color: currentLocation.startsWith('/plans')
                                ? context.colors.accent
                                : context.colors.textSecondary,
                          ),
                          title: Text(
                            'Plans',
                            style: TextStyle(
                              color: currentLocation.startsWith('/plans')
                                  ? context.colors.textPrimary
                                  : context.colors.textSecondary,
                              fontSize: 14,
                              fontWeight: currentLocation.startsWith('/plans')
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: Icon(
                            _plansMenuOpen
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: context.colors.textMuted,
                          ),
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          childrenPadding: const EdgeInsets.only(left: 12),
                          shape: const RoundedRectangleBorder(),
                          collapsedShape: const RoundedRectangleBorder(),
                          children: [
                            _navItem(
                              icon: Icons.list_alt,
                              label: 'My Plans',
                              active:
                                  currentLocation == '/plans' &&
                                  GoRouterState.of(
                                        context,
                                      ).uri.queryParameters['tab'] !=
                                      'generate',
                              onTap: () =>
                                  _navigateAndClose('/plans?tab=my_plans'),
                              isSubItem: true,
                            ),
                            _navItem(
                              icon: Icons.auto_awesome_outlined,
                              label: 'Generate with AI',
                              active:
                                  currentLocation == '/plans' &&
                                  GoRouterState.of(
                                        context,
                                      ).uri.queryParameters['tab'] ==
                                      'generate',
                              onTap: () =>
                                  _navigateAndClose('/plans?tab=generate'),
                              isSubItem: true,
                            ),
                          ],
                        ),
                      ),
                      _navItem(
                        icon: Icons.chat,
                        label: 'Chat',
                        active: currentLocation == '/chat',
                        onTap: () {
                          ref.read(conversationToLoadProvider.notifier).state =
                              null;
                          if (!widget.isPermanent) {
                            Navigator.pop(context);
                          }
                          context.go('/chat');
                        },
                      ),
                    ],
                  ),
                ),

                Divider(color: context.colors.border, height: 1),

                // Active plans (collapsible — mirrors the History toggle)
                if (_plans.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: Icon(
                          Icons.inventory_2_outlined,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        title: Text(
                          'Active plans',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          _activePlansOpen
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        onTap: () =>
                            setState(() => _activePlansOpen = !_activePlansOpen),
                      ),

                      if (_activePlansOpen)
                        ..._plans.asMap().entries.map((entry) {
                          final i = entry.key;
                          final plan = entry.value;
                          final isRenaming = _renamingPlanId == plan.id;

                          return Column(
                            children: [
                              if (isRenaming)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 2,
                                  ),
                                  child: TextField(
                                    controller: _planRenameController,
                                    style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 13,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                    ),
                                    autofocus: true,
                                    onSubmitted: (_) =>
                                        _submitRenamePlan(plan.id),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                )
                              else
                                ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  leading: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: _planColor(i),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  title: Text(
                                    plan.title ?? 'Untitled',
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Plan settings',
                                      icon: Icon(
                                        Icons.settings_outlined,
                                        size: 16,
                                        color: context.colors.textMuted,
                                      ),
                                      onPressed: () => _openPlanSettings(plan),
                                    ),
                                  ),
                                  onTap: () => _handlePlanTap(plan.id),
                                ),
                            ],
                          );
                        }),

                      Divider(color: context.colors.border, height: 1),
                    ],
                  ),

                // History section (only when authenticated)
                if (!isUnauthenticated)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // History toggle
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: Icon(
                          Icons.history,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        title: Text(
                          'History',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: Icon(
                          _historyOpen ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                          color: context.colors.textMuted,
                        ),
                        onTap: () {
                          setState(() => _historyOpen = !_historyOpen);
                          if (_historyOpen) _fetchConversations();
                        },
                      ),

                      if (_historyOpen) ...[
                        if (_conversations.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Text(
                              'No conversations yet',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ..._groupConversations().expand(
                          (group) => [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                              child: Text(
                                group.label,
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ...group.items.map((conv) {
                              final isRenaming = _renamingConvId == conv.id;
                              final showMenu = _contextMenuConvId == conv.id;

                              return Column(
                                children: [
                                  if (isRenaming)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 2,
                                      ),
                                      child: TextField(
                                        controller: _renameController,
                                        style: TextStyle(
                                          color: context.colors.textPrimary,
                                          fontSize: 13,
                                        ),
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        autofocus: true,
                                        onSubmitted: (_) =>
                                            _submitRenameConv(conv.id),
                                      ),
                                    )
                                  else
                                    ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                      title: Text(
                                        conv.title,
                                        style: TextStyle(
                                          color: context.colors.textSecondary,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: Icon(
                                            Icons.more_horiz,
                                            size: 16,
                                            color: context.colors.textMuted,
                                          ),
                                          onPressed: () {
                                            _closeContextMenus();
                                            setState(
                                              () =>
                                                  _contextMenuConvId = conv.id,
                                            );
                                          },
                                        ),
                                      ),
                                      onTap: () =>
                                          _handleConversationTap(conv.id),
                                    ),
                                  if (showMenu)
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.colors.elevated,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: context.colors.border,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          _menuItem(
                                            'Rename',
                                            () => _handleRenameConv(conv.id),
                                          ),
                                          _menuItem(
                                            'Archive',
                                            () => _handleArchiveConv(conv.id),
                                          ),
                                          _menuItem(
                                            'Delete',
                                            () => _handleDeleteConv(conv.id),
                                            destructive: true,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ],
                    ],
                  ),



                // Footer: User section or Sign-in prompt
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: context.colors.border),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: isUnauthenticated
                      ? ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: context.colors.accent.withValues(
                              alpha: 0.15,
                            ),
                            child: Icon(
                              Icons.person_outline,
                              size: 18,
                              color: context.colors.accent,
                            ),
                          ),
                          title: Text(
                            'Sign in',
                            style: TextStyle(
                              color: context.colors.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'Save your progress & plans',
                            style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: context.colors.accent,
                          ),
                          onTap: () => showAuthModal(context),
                        )
                      : ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: context.colors.accent,
                            child: Text(
                              userEmail.isNotEmpty
                                  ? userEmail[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text(
                            userEmail,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            'Free Plan',
                            style: TextStyle(
                              color: context.colors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Settings',
                            icon: Icon(
                              Icons.settings_outlined,
                              size: 18,
                              color: context.colors.textMuted,
                            ),
                            onPressed: () {
                              if (!widget.isPermanent) {
                                Navigator.pop(context);
                              }
                              showAppSettingsDialog(context);
                            },
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.isPermanent) {
      return Container(color: context.colors.surface, child: drawerContent);
    }

    return Drawer(
      backgroundColor: context.colors.surface,
      child: drawerContent,
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool isSubItem = false,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: isSubItem ? 16 : 12),
      leading: Icon(
        icon,
        size: 20,
        color: active ? context.colors.accent : context.colors.textSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: active
              ? context.colors.textPrimary
              : context.colors.textSecondary,
          fontSize: 14,
          fontWeight: active ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: active,
      selectedTileColor: context.colors.accent.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }

  Widget _menuItem(
    String label,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    return InkWell(
      onTap: () {
        _closeContextMenus();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: destructive
                ? context.colors.error
                : context.colors.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ConversationGroup {
  final String label;
  final List<ConversationSummary> items;
  _ConversationGroup({required this.label, required this.items});
}
