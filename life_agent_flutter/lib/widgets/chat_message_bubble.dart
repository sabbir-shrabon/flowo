import 'package:flutter/material.dart';
import '../../models/chat_models.dart';
import '../../theme/app_theme.dart';
import 'assistant_message_renderer.dart';
import 'message_actions_row.dart';
import 'plan_mcq_card.dart';
import 'inline_edit_box.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onCreatePlan;
  final void Function(String memoryId)? onGeneratePlan;
  final String? creatingPlanId;
  final VoidCallback? onViewMemory;
  /// Called when user submits their answers in the inline MCQ card.
  final void Function(Map<String, String> answers)? onMcqComplete;
  /// When true the MCQ card shows a loading spinner instead of the button.
  final bool mcqGenerating;
  final void Function(String content)? onRewrite;
  final bool isEditing;
  final VoidCallback? onEditCancel;
  final void Function(String newText)? onEditSubmit;

  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onCreatePlan,
    this.onGeneratePlan,
    this.creatingPlanId,
    this.onViewMemory,
    this.onMcqComplete,
    this.mcqGenerating = false,
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
    final isUser = message.role == 'user';
    final createdLabel = _timeLabel(message.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            _Avatar(
              label: 'LA',
              background: context.colors.accent.withValues(alpha: 0.18),
              foreground: context.colors.accent,
            ),
            const SizedBox(width: 8),
          ],
          if (isEditing && isUser) ...[
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                child: InlineEditBox(
                  initialText: message.content,
                  onCancel: onEditCancel ?? () {},
                  onSubmit: onEditSubmit ?? (_) {},
                ),
              ),
            ),
          ] else ...[
            Flexible(
              child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? context.colors.accent : context.colors.elevated,
                borderRadius: BorderRadius.circular(16),
                border: isUser
                    ? null
                    : Border.all(color: context.colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // MCQ card takes over the whole bubble when present
                  if (!isUser && message.planFieldQuestions != null)
                    PlanMcqCard(
                      questions: message.planFieldQuestions!,
                      generating: mcqGenerating,
                      onComplete: (answers) => onMcqComplete?.call(answers),
                    )
                  else if (isUser)
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    )
                  else
                    AssistantMessageRenderer(text: message.content),

                  // Metadata (assistant only)
                  if (!isUser && createdLabel != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          createdLabel,
                          style: TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (message.mentionedPlan != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: context.colors.textMuted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Based on: ${message.mentionedPlan}',
                              style: TextStyle(
                                color: context.colors.textMuted,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],

                  // Plan mention
                  if (!isUser && message.mentionedPlan != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bookmark_outline,
                            size: 14,
                            color: context.colors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              message.mentionedPlan!,
                              style: TextStyle(
                                color: context.colors.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Action badges
                  if (!isUser &&
                      message.actions != null &&
                      message.actions!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.actions!
                          .map(
                            (a) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: context.colors.border,
                                ),
                              ),
                              child: Text(
                                a.action.replaceAll('_', ' '),
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],

                  // Extracted memory + Create Plan button
                  if (!isUser &&
                      message.extractedMemory != null &&
                      message.extractedMemory!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saved to memory',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: message.extractedMemory!
                                .map(
                                  (f) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.colors.elevated,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      f.key,
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          ...message.extractedMemory!
                              .where((f) => f.id != null && f.key == 'goal')
                              .map(
                                (f) => SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed:
                                        onGeneratePlan != null && f.id != null
                                        ? () => onGeneratePlan!(f.id!)
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                    ),
                                    child: creatingPlanId == f.id
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text(
                                            'Create plan from this',
                                            style: TextStyle(fontSize: 13),
                                          ),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],

                  MessageActionsRow(
                    textToCopy: message.content,
                    isUser: isUser,
                    onRewrite: isUser && onRewrite != null
                        ? () => onRewrite!(message.content)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          ],
          if (isUser) ...[
            const SizedBox(width: 8),
            _Avatar(
              label: 'You',
              background: context.colors.accent,
              foreground: Colors.white,
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Avatar({
    required this.label,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final initials = label.trim().isEmpty
        ? '?'
        : label.trim().split(' ').first[0];
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            color: foreground,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
