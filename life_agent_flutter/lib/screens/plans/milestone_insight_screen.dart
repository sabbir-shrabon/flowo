import 'package:flutter/material.dart';
import '../../models/milestone_models.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/shimmer_loading.dart';

class MilestoneInsightScreen extends StatefulWidget {
  final String milestoneId;

  const MilestoneInsightScreen({super.key, required this.milestoneId});

  @override
  State<MilestoneInsightScreen> createState() => _MilestoneInsightScreenState();
}

class _MilestoneInsightScreenState extends State<MilestoneInsightScreen> {
  MilestoneInsightResponse? _insight;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchInsight();
  }

  Future<void> _fetchInsight() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await getMilestoneInsight(widget.milestoneId);
      if (mounted) {
        setState(() {
          _insight = data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('Milestone Insight'),
                  floating: true,
                  snap: true,
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      ShimmerLine(
                        width: 120,
                        height: 18,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(
                        3,
                        (_) => Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShimmerLine(width: 100, height: 12),
                              const SizedBox(height: 8),
                              ShimmerLine(height: 12),
                              const SizedBox(height: 4),
                              ShimmerLine(width: 200, height: 12),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ],
            )
          : _error != null
          ? CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('Milestone Insight'),
                  floating: true,
                  snap: true,
                ),
                SliverFillRemaining(
                  child: Center(
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
                          onPressed: _fetchInsight,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : _insight != null
          ? RefreshIndicator(
              onRefresh: _fetchInsight,
              color: context.colors.accent,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    title: const Text('Milestone Insight'),
                    floating: true,
                    snap: true,
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.info.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'AI-Generated Insight',
                            style: TextStyle(
                              color: context.colors.info,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Insight content
                        if (_insight!.insight.isNotEmpty)
                          ..._insight!.insight.entries.map(
                            (entry) =>
                                _buildInsightBlock(entry.key, entry.value),
                          ),

                        // Raw content
                        if (_insight!.raw != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            'Raw',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.colors.elevated,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _insight!.raw!,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 40),
                      ]),
                    ),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('Milestone Insight'),
                  floating: true,
                  snap: true,
                ),
                SliverFillRemaining(
                  child: EmptyState(
                    icon: Icons.lightbulb_outline,
                    title: 'Insight not available',
                    subtitle:
                        'No AI insight was generated for this milestone.',
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildInsightBlock(String key, dynamic value) {
    if (value == null) return const SizedBox.shrink();

    final displayKey = key.replaceAll('_', ' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayKey,
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _renderValue(value),
        ],
      ),
    );
  }

  Widget _renderValue(dynamic value) {
    if (value == null) return const SizedBox.shrink();

    if (value is String) {
      return Text(
        value,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
      );
    }

    if (value is num || value is bool) {
      return Text(
        value.toString(),
        style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
      );
    }

    if (value is List) {
      if (value.isEmpty) return const SizedBox.shrink();

      // Detect step list
      final isStepList = value.every(
        (i) =>
            i is Map && i.containsKey('step') && i.containsKey('instruction'),
      );
      if (isStepList) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.map<Widget>((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors.accent.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${item['step']}',
                        style: TextStyle(
                          color: context.colors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${item['instruction']}',
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }

      // Detect resource list
      final isResourceList = value.every(
        (i) => i is Map && i.containsKey('type') && i.containsKey('title'),
      );
      if (isResourceList) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: value.map<Widget>((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.elevated,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${item['type']}'.toUpperCase(),
                      style: TextStyle(
                        color: context.colors.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item['title']}',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (item['description'] != null)
                    Text(
                      '${item['description']}',
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        );
      }

      // Generic list
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: value.map<Widget>((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 12),
            child: Text(
              '• ${item is String ? item : item.toString()}',
              style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
            ),
          );
        }).toList(),
      );
    }

    if (value is Map) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.colors.elevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          value.toString(),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return Text(
      value.toString(),
      style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
    );
  }
}
