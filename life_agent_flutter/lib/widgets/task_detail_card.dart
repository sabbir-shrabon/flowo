import 'package:flutter/material.dart';
import '../models/task_models.dart';
import '../theme/app_theme.dart';
import 'assistant_message_renderer.dart';

class TaskDetailCard extends StatelessWidget {
  final TaskDetailData detail;
  final bool compact;
  final VoidCallback onClose;

  const TaskDetailCard({
    super.key,
    required this.detail,
    this.compact = false,
    required this.onClose,
  });

  /// Build the full detail as a formatted markdown string so it renders
  /// exactly like an assistant message — paragraphs, numbered steps, bullets.
  String _buildContent() {
    final sb = StringBuffer();

    // ── What is this + why it matters ─────────────────────────
    if (detail.whatIsThis.isNotEmpty) {
      sb.writeln(detail.whatIsThis);
    }
    if (detail.whyItMatters.isNotEmpty) {
      sb.writeln();
      sb.writeln(detail.whyItMatters);
    }

    // ── How to do it ──────────────────────────────────────────
    if (detail.howToDoIt.isNotEmpty) {
      sb.writeln();
      sb.writeln('How to do it:');
      for (final step in detail.howToDoIt) {
        sb.writeln('${step.step}. ${step.instruction}');
      }
    }

    // ── Resources ─────────────────────────────────────────────
    if (detail.resources.isNotEmpty) {
      sb.writeln();
      sb.writeln('Resources:');
      for (final r in detail.resources) {
        final type = r.type.isNotEmpty
            ? r.type[0].toUpperCase() + r.type.substring(1)
            : 'Link';
        if (r.description.isNotEmpty) {
          sb.writeln('- $type: ${r.title} — ${r.description}');
        } else {
          sb.writeln('- $type: ${r.title}');
        }
      }
    }

    // ── Expert tip ────────────────────────────────────────────
    if (detail.expertTip.isNotEmpty) {
      sb.writeln();
      sb.writeln('💡 Tip: ${detail.expertTip}');
    }

    return sb.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: context.colors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minimal header row: label + close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '📋 Task Guide',
                  style: TextStyle(
                    color: context.colors.accent,
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: Icon(
                  Icons.close_rounded,
                  size: compact ? 14 : 16,
                  color: context.colors.textMuted,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),

          // Message-style flowing content
          AssistantMessageRenderer(text: content),
        ],
      ),
    );
  }
}
