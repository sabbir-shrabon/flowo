import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

enum GuidedEntryTab { career, job, learn, test }

const _tabConfig = {
  GuidedEntryTab.career: _TabData(
    label: 'Career path',
    icon: Icons.work_outline,
    questions: [
      'What career suits my skills?',
      'How do I choose between career options?',
      'What skills should I learn for future jobs?',
      'Suggest a plan based on my interests',
    ],
  ),
  GuidedEntryTab.job: _TabData(
    label: 'Find a job',
    icon: Icons.badge_outlined,
    questions: [
      'How can I improve my resume?',
      'What jobs match my current skills?',
      'How do I prepare for interviews?',
      'Create a job search plan for me',
    ],
  ),
  GuidedEntryTab.learn: _TabData(
    label: 'Learn a topic',
    icon: Icons.school_outlined,
    questions: [
      'Create a learning plan for [topic]',
      'Explain this topic simply',
      'Give me a 7-day learning plan',
      'What should I learn first?',
    ],
  ),
  GuidedEntryTab.test: _TabData(
    label: 'Test knowledge',
    icon: Icons.quiz_outlined,
    questions: [
      'Take a quiz on [topic]',
      'Test my understanding of basics',
      'Give me practice questions',
      'Evaluate my skill level',
    ],
  ),
};

class _TabData {
  final String label;
  final IconData icon;
  final List<String> questions;
  const _TabData({
    required this.label,
    required this.icon,
    required this.questions,
  });
}

class GuidedEntryPanel extends StatelessWidget {
  final GuidedEntryTab activeTab;
  final bool disabled;
  final void Function(String question) onQuestionSelect;
  final void Function(GuidedEntryTab tab) onTabChange;

  const GuidedEntryPanel({
    super.key,
    required this.activeTab,
    required this.disabled,
    required this.onQuestionSelect,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    final config = _tabConfig[activeTab]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'How can I help you?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),

        // Tab chips
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: GuidedEntryTab.values.map((tab) {
              final tc = _tabConfig[tab]!;
              final isActive = tab == activeTab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: Icon(
                    tc.icon,
                    size: 16,
                    color: isActive
                        ? Colors.white
                        : context.colors.textSecondary,
                  ),
                  label: Text(tc.label),
                  selected: isActive,
                  onSelected: (_) => onTabChange(tab),
                  selectedColor: context.colors.accent,
                  labelStyle: TextStyle(
                    color: isActive
                        ? Colors.white
                        : context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        // Question cards
        ...config.questions.map(
          (q) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: disabled ? null : () => onQuestionSelect(q),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        q,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 14,
                      color: context.colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
