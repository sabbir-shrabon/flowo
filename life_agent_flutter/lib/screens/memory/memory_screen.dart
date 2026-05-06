import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../providers/navigation_provider.dart';
import '../../models/memory_models.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/shimmer_loading.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  List<MemoryResponse> _memories = [];
  bool _loading = true;
  String? _error;
  String? _deletingId;
  bool _showDetails = false;

  @override
  void initState() {
    super.initState();
    _fetchMemory();
  }

  Future<void> _fetchMemory() async {
    // Skip API calls when unauthenticated — show empty state instead
    final authStatus = ref.read(authProvider.select((s) => s.status));
    if (authStatus != AuthStatus.authenticated) {
      if (mounted) {
        setState(() {
          _memories = [];
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
      final data = await listMemory();
      if (!mounted) return;
      setState(() {
        _memories = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _confirmDelete(MemoryResponse m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: Text(
          'Delete memory?',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          'This removes it from what the assistant can recall later.',
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

    if (confirmed == true) {
      await _deleteMemory(m.id);
    }
  }

  Future<void> _deleteMemory(String id) async {
    setState(() => _deletingId = id);
    try {
      await deleteMemory(id);
      if (!mounted) return;
      setState(() {
        _memories = _memories.where((m) => m.id != id).toList();
      });
      if (!mounted) return;
      showSuccessSnackBar(context, 'Memory deleted');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _deletingId = null);
    }
  }

  String _keyLabel(MemoryKey k) {
    switch (k) {
      case MemoryKey.goal:
        return 'Goal';
      case MemoryKey.constraint:
        return 'Constraint';
      case MemoryKey.preference:
        return 'Preference';
      case MemoryKey.context:
        return 'Context';
      case MemoryKey.milestone:
        return 'Milestone';
    }
  }

  IconData _keyIcon(MemoryKey k) {
    switch (k) {
      case MemoryKey.goal:
        return Icons.flag_outlined;
      case MemoryKey.constraint:
        return Icons.block_outlined;
      case MemoryKey.preference:
        return Icons.tune_outlined;
      case MemoryKey.context:
        return Icons.notes_outlined;
      case MemoryKey.milestone:
        return Icons.emoji_events_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh data when auth state changes (e.g. after sign-in)
    ref.listen(authProvider.select((s) => s.status), (prev, next) {
      if (prev != AuthStatus.authenticated &&
          next == AuthStatus.authenticated) {
        _fetchMemory();
      }
    });

    final width = MediaQuery.of(context).size.width;
    final isLargeDesktop = width >= 1200;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text('Memory'),
            leading: null,
            floating: true,
            snap: true,
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loading ? null : _fetchMemory,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'About',
                onPressed: () => setState(() => _showDetails = !_showDetails),
                icon: Icon(_showDetails ? Icons.info : Icons.info_outline),
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
            ? ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                children: List.generate(
                  6,
                  (_) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerLine(width: 120, height: 12),
                        const SizedBox(height: 8),
                        ShimmerLine(height: 14),
                        const SizedBox(height: 6),
                        ShimmerLine(width: 200, height: 12),
                      ],
                    ),
                  ),
                ),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 48,
                        color: context.colors.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: context.colors.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchMemory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchMemory,
                color: context.colors.accent,
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  children: [
                    if (_showDetails)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: context.colors.accent.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: context.colors.accent.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'What is memory?',
                              style: TextStyle(
                                color: context.colors.accent,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Memory is what the assistant saves to stay consistent over time (goals, preferences, constraints). You can delete items any time.',
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_memories.isEmpty)
                      EmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: 'No memory yet',
                        subtitle:
                            'As you chat and create plans, the assistant will save useful context here.',
                        actionLabel: 'Go to Chat',
                        onAction: () => Navigator.pop(context),
                      )
                    else
                      ..._memories.map((m) {
                        final isDeleting = _deletingId == m.id;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: context.colors.elevated,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _keyIcon(m.key),
                                  color: context.colors.accent,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.colors.accent
                                                .withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            _keyLabel(m.key),
                                            style: TextStyle(
                                              color: context.colors.accent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            m.source,
                                            style: TextStyle(
                                              color: context.colors.textMuted,
                                              fontSize: 11,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      m.value,
                                      style: TextStyle(
                                        color: context.colors.textPrimary,
                                        fontSize: 13,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: IconButton(
                                  onPressed: isDeleting
                                      ? null
                                      : () => _confirmDelete(m),
                                  icon: isDeleting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Icon(
                                          Icons.delete_outline,
                                          color: context.colors.error,
                                          size: 20,
                                        ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: context.colors.error
                                        .withValues(alpha: 0.12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
      ),
    );
  }
}
