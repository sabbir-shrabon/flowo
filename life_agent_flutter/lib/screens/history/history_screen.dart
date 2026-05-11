import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/history_models.dart';
import '../../providers/auth_provider.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';

/// History Screen - displays all completed tasks organized by plan and date.
/// Read-only view of task completion history.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<HistoryPlanGroup> _groupedHistory = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Expanded state for plan groups
  final Set<String> _expandedPlans = {};

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory() async {
    final authStatus = ref.read(authProvider.select((s) => s.status));
    if (authStatus != AuthStatus.authenticated) {
      if (mounted) {
        setState(() {
          _groupedHistory = [];
          _loading = false;
        });
      }
      return;
    }

    try {
      final response = await getTaskHistory(
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        limit: 200,
      );
      if (mounted) {
        setState(() {
          _groupedHistory = groupHistoryForDisplay(response.history);
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Failed to load history';
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
    _fetchHistory();
  }

  void _togglePlanExpanded(String planId) {
    setState(() {
      if (_expandedPlans.contains(planId)) {
        _expandedPlans.remove(planId);
      } else {
        _expandedPlans.add(planId);
      }
    });
  }

  String _formatTime(String timestamp) {
    final dt = DateTime.tryParse(timestamp);
    if (dt == null) return '';
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'History',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(bottom: BorderSide(color: context.colors.border)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search completed tasks...',
                hintStyle: TextStyle(color: context.colors.textMuted),
                prefixIcon: Icon(
                  Icons.search,
                  color: context.colors.textMuted,
                  size: 20,
                ),
                filled: true,
                fillColor: context.colors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.colors.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
          ),

          // History list
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: context.colors.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.colors.error),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _fetchHistory,
              child: Text(
                'Retry',
                style: TextStyle(color: context.colors.accent),
              ),
            ),
          ],
        ),
      );
    }

    if (_groupedHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: context.colors.textMuted),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching tasks found'
                  : 'No completed tasks yet',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Tasks you complete will appear here',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: _fetchHistory,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _groupedHistory.length,
        itemBuilder: (context, index) {
          final planGroup = _groupedHistory[index];
          return _buildPlanGroup(planGroup);
        },
      ),
    );
  }

  Widget _buildPlanGroup(HistoryPlanGroup planGroup) {
    final isExpanded = _expandedPlans.contains(planGroup.planId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plan header
        InkWell(
          onTap: () => _togglePlanExpanded(planGroup.planId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Plan color indicator
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _getPlanColor(planGroup.planId),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // Plan name
                Expanded(
                  child: Text(
                    planGroup.planName,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Completed indicator
                if (planGroup.planCompleted) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 14,
                          color: context.colors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Completed',
                          style: TextStyle(
                            color: context.colors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // Task count
                Text(
                  '${planGroup.dateGroups.fold(0, (sum, dg) => sum + dg.entries.length)} tasks',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                // Expand icon
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: context.colors.textMuted,
                ),
              ],
            ),
          ),
        ),

        // Date groups and entries (if expanded)
        if (isExpanded)
          ...planGroup.dateGroups.map(
            (dateGroup) => _buildDateGroup(dateGroup),
          ),

        // Divider between plans
        Divider(color: context.colors.border, height: 1),
      ],
    );
  }

  Widget _buildDateGroup(HistoryDateGroup dateGroup) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date label
        Padding(
          padding: const EdgeInsets.fromLTRB(38, 12, 16, 8),
          child: Text(
            dateGroup.dateLabel,
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Task entries
        ...dateGroup.entries.map((entry) => _buildHistoryEntry(entry)),
      ],
    );
  }

  Widget _buildHistoryEntry(TaskHistoryResponse entry) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left indent for date group
          const SizedBox(width: 38),

          // Completion indicator
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: context.colors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.success, width: 1.5),
            ),
            child: Icon(Icons.check, size: 12, color: context.colors.success),
          ),
          const SizedBox(width: 12),

          // Task details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task name
                Text(
                  entry.taskName,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 14,
                  ),
                ),

                // Milestone name (if any)
                if (entry.milestoneName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.milestoneName!,
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],

                // Time and working day
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatTime(entry.completedAt),
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    if (entry.workingDayIndex != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.accentBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Day ${entry.workingDayIndex}',
                          style: TextStyle(
                            color: context.colors.accent,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getPlanColor(String planId) {
    // Generate a consistent color based on plan ID
    final hash = planId.hashCode;
    const colors = [
      Color(0xFF3DD6B5),
      Color(0xFF5B9CF6),
      Color(0xFFE8A843),
      Color(0xFFE8605A),
      Color(0xFF7B7A94),
      Color(0xFF9B8FE8),
    ];
    return colors[hash.abs() % colors.length];
  }
}
