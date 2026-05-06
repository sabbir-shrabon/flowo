import 'package:flutter/material.dart';
import '../models/plan_models.dart';
import '../models/task_models.dart';
import '../theme/app_theme.dart';
import '../utils/plan_colors.dart';
import 'task_card.dart';

enum PlanHealth { onTrack, slightlyBehind, needsAttention }

PlanHealth computePlanHealth(List<TaskResponse> tasks) {
  if (tasks.isEmpty) return PlanHealth.onTrack;
  final done = tasks.where((t) => t.status == TaskStatus.done).length;
  final skipped = tasks.where((t) => t.status == TaskStatus.skipped).length;
  final ratio = done / tasks.length;
  final skipRatio = skipped / tasks.length;
  if (skipRatio > 0.4) return PlanHealth.needsAttention;
  if (ratio < 0.3 && skipRatio > 0.1) return PlanHealth.slightlyBehind;
  return PlanHealth.onTrack;
}

const _healthLabels = {
  PlanHealth.onTrack: 'On Track',
  PlanHealth.slightlyBehind: 'Slightly Behind',
  PlanHealth.needsAttention: 'Needs Attention',
};

Color _healthColor(PlanHealth health, ThemeColors colors) {
  switch (health) {
    case PlanHealth.onTrack:
      return colors.success;
    case PlanHealth.slightlyBehind:
      return colors.warning;
    case PlanHealth.needsAttention:
      return colors.error;
  }
}

class PlanSection extends StatelessWidget {
  final PlanResponse plan;
  final int planIndex;
  final List<TaskResponse> tasks;
  final String? actingTaskId;
  final void Function(String taskId) onCheckDone;
  final void Function(TaskResponse task) onTaskTap;
  final VoidCallback onPlanTap;

  const PlanSection({
    super.key,
    required this.plan,
    required this.planIndex,
    required this.tasks,
    this.actingTaskId,
    required this.onCheckDone,
    required this.onTaskTap,
    required this.onPlanTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = getPlanColor(planIndex);
    final health = computePlanHealth(tasks);
    final c = context.colors;
    final healthColor = _healthColor(health, c);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plan header
          InkWell(
            onTap: onPlanTap,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.title ?? 'Untitled Plan',
                      style: TextStyle(
                        color: color,
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
                      color: healthColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _healthLabels[health]!,
                      style: TextStyle(
                        color: healthColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Task list
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Nothing scheduled today',
                style: TextStyle(color: c.textMuted, fontSize: 13),
              ),
            )
          else
            ...tasks.map(
              (task) => Column(
                children: [
                  if (task != tasks.first)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(height: 1, color: c.border),
                    ),
                  TaskCard(
                    task: task,
                    isActing: actingTaskId == task.id,
                    onCheckDone: () => onCheckDone(task.id),
                    onTap: () => onTaskTap(task),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
