import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../theme/app_theme.dart';

/// Renders inline inside a chat bubble when "Save as Plan" needs more info.
///
/// [questions]    — only the missing fields returned from Phase-1 extract.
/// [onComplete]   — called with {field: answer} map when user taps "Build My Plan".
/// [generating]   — when true, replaces the button with a spinner.
class PlanMcqCard extends StatefulWidget {
  final List<PlanFieldQuestion> questions;
  final void Function(Map<String, String> answers) onComplete;
  final bool generating;

  const PlanMcqCard({
    super.key,
    required this.questions,
    required this.onComplete,
    this.generating = false,
  });

  @override
  State<PlanMcqCard> createState() => _PlanMcqCardState();
}

class _PlanMcqCardState extends State<PlanMcqCard> {
  late final Map<String, String> _answers;
  late final Map<String, TextEditingController> _textControllers;

  // Required fields that must have an answer before we enable the button
  static const _required = {'learning_goal', 'focus_area', 'skill_level'};

  @override
  void initState() {
    super.initState();
    _answers = {};
    _textControllers = {};
    for (final q in widget.questions) {
      if (q.chips == null) {
        // text-based field
        _textControllers[q.field] = TextEditingController();
        _textControllers[q.field]!.addListener(() {
          setState(() => _answers[q.field] = _textControllers[q.field]!.text.trim());
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit {
    for (final q in widget.questions) {
      if (_required.contains(q.field)) {
        final ans = _answers[q.field];
        if (ans == null || ans.trim().isEmpty) return false;
      }
    }
    return true;
  }

  void _submit() {
    if (!_canSubmit || widget.generating) return;
    widget.onComplete(Map.from(_answers));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.colors.accent.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            decoration: BoxDecoration(
              color: context.colors.accent.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: context.colors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: context.colors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A few quick details',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Answer below to build your roadmap',
                        style: TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Questions ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...widget.questions.asMap().entries.map((entry) {
                  final i = entry.key;
                  final q = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 20),
                    child: _buildQuestion(q),
                  );
                }),

                const SizedBox(height: 20),

                // ── Build button ─────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: AnimatedOpacity(
                    opacity: _canSubmit ? 1.0 : 0.45,
                    duration: const Duration(milliseconds: 200),
                    child: ElevatedButton.icon(
                      onPressed: _canSubmit && !widget.generating ? _submit : null,
                      icon: widget.generating
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.rocket_launch_rounded, size: 16),
                      label: Text(
                        widget.generating ? 'Building your plan…' : 'Build My Plan →',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            context.colors.accent.withValues(alpha: 0.3),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(PlanFieldQuestion q) {
    final isRequired = _required.contains(q.field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question label
        Row(
          children: [
            Expanded(
              child: Text(
                q.question,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
            if (!isRequired)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.elevated,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Optional',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Chips or text field
        if (q.chips != null)
          _buildChips(q)
        else
          _buildTextField(q),
      ],
    );
  }

  Widget _buildChips(PlanFieldQuestion q) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: q.chips!.map((chip) {
        final selected = _answers[q.field] == chip;
        return GestureDetector(
          onTap: () => setState(() => _answers[q.field] = chip),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? context.colors.accent.withValues(alpha: 0.12)
                  : context.colors.elevated,
              border: Border.all(
                color: selected ? context.colors.accent : context.colors.border,
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              chip,
              style: TextStyle(
                color: selected
                    ? context.colors.accent
                    : context.colors.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(PlanFieldQuestion q) {
    final isRequired = _required.contains(q.field);
    return TextField(
      controller: _textControllers[q.field],
      maxLines: q.field == 'focus_area' ? 3 : 2,
      minLines: 2,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: q.textHint ?? 'Type your answer…',
        hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
        filled: true,
        fillColor: context.colors.elevated,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: context.colors.accent),
        ),
        suffixText: isRequired ? null : 'Optional',
        suffixStyle: TextStyle(
          color: context.colors.textMuted,
          fontSize: 11,
        ),
      ),
    );
  }
}
