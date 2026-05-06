import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/plan_models.dart';
import '../../providers/navigation_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/adaptive_service.dart';
import '../../services/connectivity_service.dart';
import '../../utils/feature_flags.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../utils/plan_colors.dart';
import '../../widgets/adapt_with_plan_popup.dart';
import '../../widgets/shimmer_loading.dart';
import '../../widgets/plan_settings_dialog.dart';
import 'ai_plan_wizard.dart';

enum _ViewMode { grid, list }

class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({super.key});

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  List<PlanResponse> _plans = [];
  bool _loading = true;
  String? _error;
  bool _showAll = false;
  String? _actingPlanId;
  _ViewMode _viewMode = _ViewMode.grid;

  @override
  void initState() {
    super.initState();
    _fetchPlans();
  }

  @override
  void dispose() => super.dispose();

  Future<void> _fetchPlans() async {
    // Skip API calls when unauthenticated — show empty state instead
    final authStatus = ref.read(authProvider.select((s) => s.status));
    final user = ref.read(authProvider).user;
    if (authStatus != AuthStatus.authenticated || user == null) {
      if (mounted) {
        setState(() {
          _plans = [];
          _loading = false;
        });
      }
      return;
    }

    final userId = user.id;
    final cache = ref.read(localCacheProvider);
    final hasInternet = FeatureFlags.useNewConnectivityCheck
        ? await ConnectivityService().hasInternet()
        : await ref.read(connectivityProvider.future).catchError((_) => true);

    // Load from cache first for instant UI
    if (!_showAll) {
      final cachedPlans = cache.getCachedPlans(userId);
      if (cachedPlans != null && cachedPlans.isNotEmpty) {
        if (mounted) {
          setState(() {
            _plans = cachedPlans.map((p) => p.plan).toList();
            _loading = false;
          });
        }
      }
    } else {
      final cachedAllPlans = cache.getCachedAllPlans(userId);
      if (cachedAllPlans != null && cachedAllPlans.isNotEmpty) {
        if (mounted) {
          setState(() {
            _plans = cachedAllPlans;
            _loading = false;
          });
        }
      }
    }

    if (!hasInternet) return;

    try {
      final data = _showAll ? await listAllPlans() : await listActivePlans();

      // Save to cache for next time
      if (_showAll) {
        await cache.saveAllPlans(userId, data);
      }

      if (mounted) {
        setState(() {
          _plans = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_plans.isEmpty) {
            _error = friendlyErrorMessage(e);
          }
          _loading = false;
        });
      }
    }
  }

  Future<void> _handlePause(String planId) async {
    setState(() => _actingPlanId = planId);
    try {
      await pausePlan(planId);
      await _fetchPlans();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _actingPlanId = null);
    }
  }

  Future<void> _handleResume(String planId) async {
    setState(() => _actingPlanId = planId);
    try {
      await resumePlan(planId);
      await _fetchPlans();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _actingPlanId = null);
    }
  }

  Future<void> _handleDelete(String planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(
          'Delete Plan?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actingPlanId = planId);
    try {
      await deletePlan(planId);
      await _fetchPlans();
      ref.read(todayRefreshProvider.notifier).state++;
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    } finally {
      if (mounted) setState(() => _actingPlanId = null);
    }
  }

  Future<void> _handleAdapt(PlanResponse plan, AdaptPlanResult result) async {
    setState(() => _actingPlanId = plan.id);
    try {
      await adaptPlan(
        plan.id,
        durationDays: result.durationDays,
        workingDays: result.workingDays,
      );
      await _fetchPlans();
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
        context.go('/today');
      }
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e);
      rethrow;
    } finally {
      if (mounted) setState(() => _actingPlanId = null);
    }
  }

  Future<void> _openPlanSettings(PlanResponse plan) {
    return showPlanSettingsDialog(
      context,
      plan: plan,
      onRename: (title) async {
        setState(() => _actingPlanId = plan.id);
        try {
          await patchPlan(plan.id, PlanUpdatePayload(title: title));
          await _fetchPlans();
        } catch (e) {
          if (mounted) showErrorSnackBar(context, e);
          rethrow;
        } finally {
          if (mounted) setState(() => _actingPlanId = null);
        }
      },
      onPause: plan.status == PlanStatus.active
          ? () async => _handlePause(plan.id)
          : null,
      onResume: plan.status == PlanStatus.paused
          ? () async => _handleResume(plan.id)
          : null,
      onDelete: plan.status != PlanStatus.completed
          ? () async => _handleDelete(plan.id)
          : null,
      onAdapt: (result) => _handleAdapt(plan, result),
    );
  }

  Color _statusColor(PlanStatus status) {
    final c = context.colors;
    switch (status) {
      case PlanStatus.setup:
        return c.warning;
      case PlanStatus.active:
        return c.success;
      case PlanStatus.paused:
        return c.error;
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
    // Refresh data when auth state changes (e.g. after sign-in)
    ref.listen(authProvider.select((s) => s.status), (prev, next) {
      if (prev != AuthStatus.authenticated &&
          next == AuthStatus.authenticated) {
        _fetchPlans();
      }
    });

    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    final isGenerate = tab == 'generate';

    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;

    final hasInternetAsyncValue = ref.watch(connectivityProvider);
    final hasInternet = hasInternetAsyncValue.value ?? true;

    Widget body;
    if (isGenerate) {
      if (!hasInternet) {
        body = Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off,
                size: 64,
                color: context.colors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Generate requires an internet connection',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        );
      } else {
        body = const AiPlanWizard();
      }
    } else {
      body = _buildMyPlans();
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(isGenerate ? 'Generate Plan' : 'My Plans'),
            leading: null,
            floating: true,
            snap: true,
            actions: [
              if (!isGenerate) ...[
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _fetchPlans,
                  tooltip: 'Refresh plans',
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() => _showAll = !_showAll);
                          _fetchPlans();
                        },
                  child: Text(
                    _showAll ? 'Active Only' : 'Show All',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _viewModeToggle(),
              ],
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
        body: body,
      ),
    );
  }

  Widget _viewModeToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(Icons.grid_view, _ViewMode.grid),
          _toggleBtn(Icons.view_list, _ViewMode.list),
        ],
      ),
    );
  }

  Widget _toggleBtn(IconData icon, _ViewMode mode) {
    final selected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 18,
          color: selected ? context.colors.accent : context.colors.textMuted,
        ),
      ),
    );
  }

  Widget _buildMyPlans() {
    if (_loading) {
      return _viewMode == _ViewMode.grid
          ? _buildGridSkeleton()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: List.generate(4, (_) => const PlanCardSkeleton()),
            );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: context.colors.textMuted),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: context.colors.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchPlans, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_plans.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No plans yet',
        subtitle:
            'Use "Generate with AI" to create a personalised learning roadmap.',
        actionLabel: 'Generate a Plan',
        onAction: () => context.go('/plans?tab=generate'),
      );
    }

    final hasInternetAsyncValue = ref.watch(connectivityProvider);
    final hasInternet = hasInternetAsyncValue.value ?? true;

    return RefreshIndicator(
      onRefresh: _fetchPlans,
      color: context.colors.accent,
      child: Column(
        children: [
          if (!hasInternet)
            Container(
              color: context.colors.error.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 16, color: context.colors.error),
                  const SizedBox(width: 8),
                  Text(
                    'Offline — showing cached plans',
                    style: TextStyle(
                      color: context.colors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _viewMode == _ViewMode.grid
                ? _buildGridView()
                : _buildListView(),
          ),
        ],
      ),
    );
  }

  Widget _buildGridSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: 4,
      itemBuilder: (_, _) => const PlanCardSkeleton(),
    );
  }

  Widget _buildGridView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxGridWidth = 720.0;
        final horizontalPad = constraints.maxWidth > maxGridWidth
            ? (constraints.maxWidth - maxGridWidth) / 2
            : 16.0;
        return GridView.builder(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: _plans.length,
          itemBuilder: (context, index) {
            final plan = _plans[index];
            final planColor = getPlanColor(index);
            final isActing = _actingPlanId == plan.id;
            return _PlanGridCard(
              plan: plan,
              planColor: planColor,
              statusColor: _statusColor(plan.status),
              statusLabel: _statusLabel(plan.status),
              isActing: isActing,
              onTap: () => context.push('/plans/${plan.id}'),
              onSettings: () => _openPlanSettings(plan),
            );
          },
        );
      },
    );
  }

  Widget _buildListView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxListWidth = 720.0;
        final horizontalPad = constraints.maxWidth > maxListWidth
            ? (constraints.maxWidth - maxListWidth) / 2
            : 16.0;
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: horizontalPad, vertical: 8),
          itemCount: _plans.length,
          itemBuilder: (context, index) {
            final plan = _plans[index];
            final planColor = getPlanColor(index);
            final statusColor = _statusColor(plan.status);
            final isActing = _actingPlanId == plan.id;
            return _PlanListCard(
              plan: plan,
              planColor: planColor,
              statusColor: statusColor,
              statusLabel: _statusLabel(plan.status),
              isActing: isActing,
              onTap: () => context.push('/plans/${plan.id}'),
              onSettings: () => _openPlanSettings(plan),
            );
          },
        );
      },
    );
  }
}

// ── Progress Circle ────────────────────────────────────────────────────────────

class _ProgressCircle extends StatelessWidget {
  final double progress;
  final double size;
  final Color color;

  const _ProgressCircle({
    required this.progress,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress.clamp(0.0, 100.0) / 100.0;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ProgressPainter(
          progress: pct,
          trackColor: context.colors.border,
          progressColor: color,
          strokeWidth: 3,
        ),
        child: Center(
          child: Text(
            '${progress.round()}%',
            style: TextStyle(
              fontSize: size * 0.26,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  _ProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = this.strokeWidth;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Track
    paint.color = trackColor;
    canvas.drawArc(
      rect.deflate(strokeWidth / 2),
      0,
      3.14159265 * 2,
      false,
      paint,
    );

    // Progress arc
    if (progress > 0) {
      paint.color = progressColor;
      canvas.drawArc(
        rect.deflate(strokeWidth / 2),
        -3.14159265 / 2,
        3.14159265 * 2 * progress,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}

// ── Grid Card ──────────────────────────────────────────────────────────────────

class _PlanGridCard extends StatelessWidget {
  final PlanResponse plan;
  final Color planColor;
  final Color statusColor;
  final String statusLabel;
  final bool isActing;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  const _PlanGridCard({
    required this.plan,
    required this.planColor,
    required this.statusColor,
    required this.statusLabel,
    required this.isActing,
    required this.onTap,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // Top accent bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: planColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            plan.title ?? 'Untitled Plan',
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Status chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${plan.priority.name} • ${plan.intensity.name}',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
              // Progress circle bottom-left
              Positioned(
                left: 14,
                bottom: 10,
                child: _ProgressCircle(
                  progress: plan.progressPct,
                  size: 36,
                  color: planColor,
                ),
              ),
              // Options menu bottom-right
              Positioned(
                right: 4,
                bottom: 4,
                child: isActing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Plan settings',
                        onPressed: onSettings,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: context.colors.textSecondary,
                          size: 20,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── List Card ──────────────────────────────────────────────────────────────────

class _PlanListCard extends StatelessWidget {
  final PlanResponse plan;
  final Color planColor;
  final Color statusColor;
  final String statusLabel;
  final bool isActing;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  const _PlanListCard({
    required this.plan,
    required this.planColor,
    required this.statusColor,
    required this.statusLabel,
    required this.isActing,
    required this.onTap,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 14,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: planColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              plan.title ?? 'Untitled Plan',
                              style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          'Priority: ${plan.priority.name} • Intensity: ${plan.intensity.name}',
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Progress circle on the right
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProgressCircle(
                  progress: plan.progressPct,
                  size: 42,
                  color: planColor,
                ),
              ),
              // Options menu on the far right
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: isActing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Plan settings',
                        onPressed: onSettings,
                        icon: Icon(
                          Icons.settings_outlined,
                          color: context.colors.textSecondary,
                          size: 20,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
