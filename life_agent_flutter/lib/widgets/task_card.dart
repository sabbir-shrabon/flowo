import 'package:flutter/material.dart';
import '../models/task_models.dart';
import '../theme/app_theme.dart';

class TaskCard extends StatelessWidget {
  final TaskResponse task;
  final bool isActing;
  final VoidCallback onCheckDone;
  final VoidCallback onTap;

  const TaskCard({
    super.key,
    required this.task,
    required this.isActing,
    required this.onCheckDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = task.status == TaskStatus.done;
    final isSkipped = task.status == TaskStatus.skipped;
    final isRescheduled = task.carryOverCount > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 24,
              height: 24,
              child: isActing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.accent,
                      ),
                    )
                  : GestureDetector(
                      onTap: isDone ? null : onCheckDone,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? context.colors.accent
                              : Colors.transparent,
                          border: Border.all(
                            color: isDone
                                ? context.colors.accent
                                : context.colors.border,
                            width: 2,
                          ),
                        ),
                        child: isDone
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
            ),
            const SizedBox(width: 12),

            // Title + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: TextStyle(
                      color: isDone
                          ? context.colors.textMuted
                          : isSkipped
                          ? context.colors.textMuted
                          : context.colors.textPrimary,
                      fontSize: 14,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (isRescheduled && !isSkipped) ...[
                    const SizedBox(height: 2),
                    Text(
                      'rescheduled',
                      style: TextStyle(
                        color: context.colors.warning.withValues(alpha: 0.8),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Duration
            if (task.durationMinutes != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.elevated,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${task.durationMinutes} min',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],

            // Difficulty badge
            const SizedBox(width: 6),
            Flexible(child: _difficultyBadge(task.difficulty, context.colors)),
          ],
        ),
      ),
    );
  }

  Widget _difficultyBadge(TaskDifficulty difficulty, ThemeColors colors) {
    Color color;
    switch (difficulty) {
      case TaskDifficulty.easy:
        color = colors.success;
      case TaskDifficulty.intermediate:
        color = colors.warning;
      case TaskDifficulty.hard:
        color = colors.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        difficulty.name[0].toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
