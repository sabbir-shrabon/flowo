import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A single shimmer line placeholder.
class ShimmerLine extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerLine({
    super.key,
    this.width = double.infinity,
    this.height = 14,
    this.borderRadius,
  });

  @override
  State<ShimmerLine> createState() => _ShimmerLineState();
}

class _ShimmerLineState extends State<ShimmerLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shimmerProgress = _controller.value;
        // Gradient sweeps from left to right
        final startAlignment = Alignment(-1.0 + 2.0 * shimmerProgress, 0);
        final endAlignment = Alignment(-1.0 + 2.0 * shimmerProgress + 0.4, 0);

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius:
                widget.borderRadius ?? BorderRadius.circular(widget.height / 2),
            gradient: LinearGradient(
              begin: startAlignment,
              end: endAlignment,
              colors: [
                context.colors.elevated,
                context.colors.border,
                context.colors.elevated,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for a task card row.
class TaskCardSkeleton extends StatelessWidget {
  const TaskCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          // Checkbox placeholder
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.elevated,
              border: Border.all(color: context.colors.border),
            ),
          ),
          const SizedBox(width: 12),
          // Title + subtitle lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLine(width: MediaQuery.of(context).size.width * 0.5),
                const SizedBox(height: 6),
                ShimmerLine(
                  width: MediaQuery.of(context).size.width * 0.3,
                  height: 10,
                ),
              ],
            ),
          ),
          // Duration badge
          ShimmerLine(
            width: 36,
            height: 16,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a plan section header + task rows.
class PlanSectionSkeleton extends StatelessWidget {
  final int taskCount;
  const PlanSectionSkeleton({super.key, this.taskCount = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Plan header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: context.colors.elevated,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              ShimmerLine(width: 120, height: 16),
              const Spacer(),
              ShimmerLine(
                width: 50,
                height: 18,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ),
        ),
        // Task rows
        ...List.generate(taskCount, (_) => const TaskCardSkeleton()),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Skeleton for a plan card in the Plans screen.
class PlanCardSkeleton extends StatelessWidget {
  const PlanCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShimmerLine(width: 140, height: 16),
              const Spacer(),
              ShimmerLine(
                width: 50,
                height: 18,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ShimmerLine(width: 200, height: 12),
          const SizedBox(height: 10),
          Row(
            children: [
              ShimmerLine(
                width: 60,
                height: 28,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 8),
              ShimmerLine(
                width: 60,
                height: 28,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for plan detail screen.
class PlanDetailSkeleton extends StatelessWidget {
  const PlanDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Overview header
        Container(
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
                  ShimmerLine(width: 160, height: 18),
                  const Spacer(),
                  ShimmerLine(
                    width: 60,
                    height: 20,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: List.generate(
                  4,
                  (_) => Expanded(
                    child: Column(
                      children: [
                        ShimmerLine(
                          width: 40,
                          height: 18,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        const SizedBox(height: 4),
                        ShimmerLine(
                          width: 60,
                          height: 10,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Progress section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerLine(width: 80, height: 16),
              const SizedBox(height: 12),
              ShimmerLine(height: 8, borderRadius: BorderRadius.circular(4)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Milestones section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShimmerLine(width: 100, height: 16),
              const SizedBox(height: 12),
              ...List.generate(
                3,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.colors.elevated,
                          border: Border.all(color: context.colors.border),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: ShimmerLine(height: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Empty state widget with icon, title, and optional subtitle + action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.elevated,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: context.colors.textMuted),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
