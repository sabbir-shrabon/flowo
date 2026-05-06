import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AssistantStatus { idle, thinking }

class AssistantStatusPill extends StatelessWidget {
  final AssistantStatus status;
  const AssistantStatusPill({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == AssistantStatus.idle) return const SizedBox.shrink();

    final label = switch (status) {
      AssistantStatus.thinking => 'Thinking',

      AssistantStatus.idle => '',
    };

    final icon = switch (status) {
      AssistantStatus.thinking => Icons.auto_awesome_outlined,

      AssistantStatus.idle => Icons.circle,
    };

    final color = context.colors.textMuted;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: context.colors.elevated,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

