import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'assistant_message_renderer.dart';
import 'message_actions_row.dart';
import 'inline_edit_box.dart';

class InlineChatBubble extends StatelessWidget {
  final bool isUser;
  final String content;
  final DateTime? createdAt;
  final VoidCallback? onViewMemory;
  final void Function(String content)? onRewrite;
  final bool isEditing;
  final VoidCallback? onEditCancel;
  final void Function(String)? onEditSubmit;

  const InlineChatBubble({
    super.key,
    required this.isUser,
    required this.content,
    this.createdAt,
    this.onViewMemory,
    this.onRewrite,
    this.isEditing = false,
    this.onEditCancel,
    this.onEditSubmit,
  });

  String? _timeLabel(DateTime? dt) {
    if (dt == null) return null;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ap = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    if (isEditing && isUser) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: InlineEditBox(
          initialText: content,
          onCancel: onEditCancel ?? () {},
          onSubmit: onEditSubmit ?? (_) {},
        ),
      );
    }

    final createdLabel = _timeLabel(createdAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isUser
            ? context.colors.accent.withValues(alpha: 0.1)
            : context.colors.elevated,
        borderRadius: BorderRadius.circular(10),
        border: isUser ? null : Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isUser
              ? Text(
                  content,
                  style: TextStyle(
                    color: context.colors.accent,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : AssistantMessageRenderer(text: content),
          if (!isUser) ...[
            if (createdLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                createdLabel,
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
          MessageActionsRow(
            textToCopy: content,
            isUser: isUser,
            onRewrite: isUser && onRewrite != null
                ? () => onRewrite!(content)
                : null,
          ),
        ],
      ),
    );
  }
}

