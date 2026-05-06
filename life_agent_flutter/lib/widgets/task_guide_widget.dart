import 'package:flutter/material.dart';
import '../models/task_models.dart';
import '../theme/app_theme.dart';

const _resourceTypeLabels = {
  'video': 'VIDEO',
  'article': 'ARTICLE',
  'app': 'APP',
  'book': 'BOOK',
};

class TaskGuideWidget extends StatelessWidget {
  final TaskDetailData detail;

  const TaskGuideWidget({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // What is this
        _section(
          context: context,
          title: 'WHAT IS THIS',
          child: Text(
            detail.whatIsThis,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
          ),
        ),

        // Why it matters
        if (detail.whyItMatters.isNotEmpty)
          _section(
            context: context,
            title: 'WHY TODAY',
            child: Text(
              detail.whyItMatters,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
            ),
          ),

        // How to do it
        if (detail.howToDoIt.isNotEmpty)
          _section(
            context: context,
            title: 'HOW TO DO IT',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: detail.howToDoIt.map((step) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.colors.accent.withValues(alpha: 0.15),
                        ),
                        child: Center(
                          child: Text(
                            '${step.step}',
                            style: TextStyle(
                              color: context.colors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          step.instruction,
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
            ),
          ),

        // Resources
        if (detail.resources.isNotEmpty)
          _section(
            context: context,
            title: 'RESOURCES',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: detail.resources.map((r) {
                final typeLabel =
                    _resourceTypeLabels[r.type] ?? r.type.toUpperCase();
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
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
                          typeLabel,
                          style: TextStyle(
                            color: context.colors.accent,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (r.description.isNotEmpty)
                        Text(
                          r.description,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        // Today's example
        if (detail.todaysExample.isNotEmpty)
          _section(
            context: context,
            title: "TODAY'S EXAMPLE",
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                detail.todaysExample,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
          ),

        // Expert tip
        if (detail.expertTip.isNotEmpty)
          _section(
            context: context,
            title: 'EXPERT TIP',
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: context.colors.warning,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    detail.expertTip,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _section({
    required String title,
    required Widget child,
    required BuildContext context,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.colors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
