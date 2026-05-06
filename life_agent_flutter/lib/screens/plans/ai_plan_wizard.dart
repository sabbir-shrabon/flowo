import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/plan_models.dart';
import '../../models/milestone_models.dart';
import '../../services/adaptive_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_handler.dart';
import '../../widgets/auth_modal.dart';
import '../../widgets/adapt_with_plan_popup.dart';
import '../../providers/navigation_provider.dart';

// ─────────────────────────────────────────────────────────────
//  Data model for each wizard question
// ─────────────────────────────────────────────────────────────
class _Question {
  final String title;
  final String? subtitle;
  final bool isTextField;
  final String? textHint;
  final List<String>? chips;

  const _Question({
    required this.title,
    this.subtitle,
    this.isTextField = false,
    this.textHint,
    this.chips,
  });
}

final _questions = [
  _Question(
    title: 'What is your main learning goal?',
    chips: [
      'Get a Job',
      'Grow in my current role',
      'Build Projects / Side Hustles',
      'Strengthen Fundamentals',
      'Explore a New Field',
    ],
  ),
  _Question(
    title: 'What role or field do you want to focus on?',
    subtitle:
        'Explain in detail what you would like to focus on.\ne.g. I know intermediate JavaScript and want to focus on the advanced aspects.',
    isTextField: true,
    textHint: 'Describe your focus area…',
  ),
  _Question(
    title: 'What is your current skill level in this area?',
    chips: [
      'Beginner (just starting out)',
      'Intermediate (some hands-on experience)',
      'Advanced (comfortable, want to go deeper)',
    ],
  ),
  _Question(
    title: 'Are there specific things you want to focus on (or avoid)?',
    subtitle:
        'e.g. focus on vanilla JavaScript, avoid including frameworks or libraries',
    isTextField: true,
    textHint: 'Optional — leave blank if none',
  ),
  _Question(
    title: 'Anything else we should know about your goals?',
    subtitle:
        'e.g. I am a backend developer with expertise in Python, I recently started learning Node.js.',
    isTextField: true,
    textHint: 'Optional — additional context',
  ),
];

// ─────────────────────────────────────────────────────────────
//  Main wizard widget
// ─────────────────────────────────────────────────────────────
class AiPlanWizard extends ConsumerStatefulWidget {
  const AiPlanWizard({super.key});

  @override
  ConsumerState<AiPlanWizard> createState() => _AiPlanWizardState();
}

class _AiPlanWizardState extends ConsumerState<AiPlanWizard>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  final _answers = List<String>.filled(5, '');
  final _textController = TextEditingController();
  bool _generating = false;
  String? _error;
  CreatePlanResponse? _result;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _textController.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────
  void _next() {
    final q = _questions[_step];
    if (q.isTextField) {
      _answers[_step] = _textController.text.trim();
    }
    if (_answers[_step].isEmpty && _step < 3) return; // Q4/Q5 optional

    if (_step == _questions.length - 1) {
      _generate();
    } else {
      _fadeCtrl.reverse().then((_) {
        setState(() {
          _step++;
          if (_questions[_step].isTextField) {
            _textController.text = _answers[_step];
          }
        });
        _fadeCtrl.forward();
      });
    }
  }

  void _back() {
    if (_step == 0) return;
    _fadeCtrl.reverse().then((_) {
      setState(() {
        _step--;
        if (_questions[_step].isTextField) {
          _textController.text = _answers[_step];
        }
      });
      _fadeCtrl.forward();
    });
  }

  void _reset() {
    setState(() {
      _step = 0;
      for (int i = 0; i < _answers.length; i++) {
        _answers[i] = '';
      }
      _textController.clear();
      _result = null;
      _error = null;
    });
    _fadeCtrl.forward();
  }

  // ── Adapt with Plan ───────────────────────────────────────
  Future<void> _onAdaptWithPlan(PlanResponse plan) async {
    final result = await showAdaptWithPlanPopup(
      context,
      planTitle: plan.title ?? 'Learning Plan',
    );

    if (result != null && mounted) {
      setState(() => _generating = true);
      try {
        await adaptPlan(
          plan.id,
          durationDays: result.durationDays,
          workingDays: result.workingDays,
        );
        // Trigger today screen hard refresh (shows loading spinner) then navigate there
        ref.read(todayAdaptRefreshProvider.notifier).state++;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Plan adapted! Tasks scheduled over ${result.durationDays} days.',
                style: TextStyle(color: context.colors.background),
              ),
              backgroundColor: context.colors.success,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          // Navigate to today screen to show updated schedule
          context.go('/today');
        }
      } catch (e) {
        if (mounted) {
          showErrorSnackBar(context, e);
        }
      } finally {
        if (mounted) {
          setState(() => _generating = false);
        }
      }
    }
  }

  // ── Generate ──────────────────────────────────────────────
  Future<void> _generate() async {
    // Require auth before generating plan with AI
    final authed = await requireAuth(context, ref, () {});
    if (!authed) return;

    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final result = await generatePlanFromAnswers(
        learningGoal: _answers[0],
        focusArea: _answers[1],
        skillLevel: _answers[2],
        focusOrAvoid: _answers[3],
        extraContext: _answers[4],
      );
      setState(() {
        _result = result;
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _generating = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_generating) return _buildLoading();
    if (_result != null) return _buildResult(_result!);
    return _buildWizard();
  }

  // ── Loading screen ────────────────────────────────────────
  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingLogo(),
          const SizedBox(height: 32),
          Text(
            'Crafting your roadmap…',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'The AI is building a personalised plan\nbased on your answers.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ── Wizard screen ─────────────────────────────────────────
  Widget _buildWizard() {
    final q = _questions[_step];
    final isLast = _step == _questions.length - 1;
    final isOptional = _step >= 3;
    final canContinue = _answers[_step].isNotEmpty || isOptional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress bar
        _ProgressBar(current: _step + 1, total: _questions.length),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Question ${_step + 1} of ${_questions.length}',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Question card
        Expanded(
          child: FadeTransition(
            opacity: _fade,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.title,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  if (q.subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      q.subtitle!,
                      style: TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (q.isTextField)
                    _buildTextField(q, isOptional)
                  else
                    _buildChips(q),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: context.colors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Navigation buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Row(
            children: [
              if (_step > 0)
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _back,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textSecondary,
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Previous'),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: canContinue ? _next : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.colors.accent.withValues(
                      alpha: 0.3,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isLast ? 'Generate Plan' : 'Next Question',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(_Question q, bool isOptional) {
    return TextField(
      controller: _textController,
      maxLines: 5,
      minLines: 3,
      onChanged: (v) => setState(() => _answers[_step] = v.trim()),
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: q.textHint,
        hintStyle: TextStyle(color: context.colors.textMuted),
        filled: true,
        fillColor: context.colors.surface,
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
        contentPadding: const EdgeInsets.all(14),
        suffixText: isOptional ? 'Optional' : null,
        suffixStyle: TextStyle(color: context.colors.textMuted, fontSize: 11),
      ),
    );
  }

  Widget _buildChips(_Question q) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: q.chips!.map((chip) {
        final selected = _answers[_step] == chip;
        return GestureDetector(
          onTap: () => setState(() => _answers[_step] = chip),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? context.colors.accent.withValues(alpha: 0.12)
                  : context.colors.surface,
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
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Result screen ─────────────────────────────────────────
  Widget _buildResult(CreatePlanResponse result) {
    final plan = result.plan;
    final milestones = result.milestones;
    final totalTasks = result.taskCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.colors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Your plan is ready',
                    style: TextStyle(
                      color: context.colors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                plan.title ?? 'Learning Plan',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${milestones.length} steps · $totalTasks tasks',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _headerBtn(
                    Icons.calendar_month,
                    'Adapt with Plan',
                    context.colors.accent,
                    () => _onAdaptWithPlan(plan),
                  ),
                  const SizedBox(width: 10),
                  _headerBtn(
                    Icons.open_in_new,
                    'View Plan',
                    context.colors.textSecondary,
                    () => context.push('/plans/${plan.id}'),
                  ),
                  const SizedBox(width: 10),
                  _headerBtn(
                    Icons.refresh,
                    'Revise',
                    context.colors.textMuted,
                    _reset,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Divider(height: 1, color: context.colors.border),

        // Roadmap steps
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            itemCount: milestones.length + 1,
            itemBuilder: (ctx, i) {
              if (i == milestones.length) return _buildFeedback();
              return _MilestoneNode(
                milestone: milestones[i],
                index: i,
                isLast: i == milestones.length - 1,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _headerBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
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
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Divider(color: context.colors.border),
          const SizedBox(height: 16),
          Text(
            'Was this learning plan helpful?',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _feedbackBtn('👍  Helpful', context.colors.success),
              const SizedBox(width: 12),
              _feedbackBtn('👎  Not helpful', context.colors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _feedbackBtn(String label, Color color) {
    return OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Milestone node (expandable roadmap step)
// ─────────────────────────────────────────────────────────────
class _MilestoneNode extends StatefulWidget {
  final MilestoneResponse milestone;
  final int index;
  final bool isLast;

  const _MilestoneNode({
    required this.milestone,
    required this.index,
    required this.isLast,
  });

  @override
  State<_MilestoneNode> createState() => _MilestoneNodeState();
}

class _MilestoneNodeState extends State<_MilestoneNode>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expanded = widget.index == 0; // first step open by default
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: _expanded ? 1 : 0,
    );
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  static const _stepColors = [
    Color(0xFF3DD6B5),
    Color(0xFF5B9CF6),
    Color(0xFFE8A843),
    Color(0xFFE8605A),
    Color(0xFF9B8FE8),
    Color(0xFF7B7A94),
  ];

  Color get _color => _stepColors[widget.index % _stepColors.length];

  @override
  Widget build(BuildContext context) {
    final ms = widget.milestone;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline column
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Circle node
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _color.withValues(alpha: 0.15),
                    border: Border.all(color: _color, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${widget.index + 1}',
                      style: TextStyle(
                        color: _color,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                // Connector line
                if (!widget.isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: context.colors.border,
                    ),
                  ),
                if (widget.isLast) const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step header (tappable)
                GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(bottom: 8, top: 4),
                    color: Colors.transparent,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Step ${widget.index + 1}',
                                style: TextStyle(
                                  color: _color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ms.title,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${ms.tasks.length} tasks',
                                style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: context.colors.textMuted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                // Expanded tasks
                SizeTransition(
                  sizeFactor: _expandAnim,
                  child: Column(
                    children: [
                      ...ms.tasks.asMap().entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 22,
                                height: 22,
                                margin: const EdgeInsets.only(top: 1),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _color.withValues(alpha: 0.1),
                                  border: Border.all(
                                    color: _color.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '${e.key + 1}',
                                    style: TextStyle(
                                      color: _color,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  e.value.title,
                                  style: TextStyle(
                                    color: context.colors.textSecondary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Progress bar
// ─────────────────────────────────────────────────────────────
class _ProgressBar extends StatelessWidget {
  final int current;
  final int total;
  const _ProgressBar({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      width: double.infinity,
      color: context.colors.border,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: current / total,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.colors.accent, const Color(0xFF5B9CF6)],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Pulsing AI logo for loading state
// ─────────────────────────────────────────────────────────────
class _PulsingLogo extends StatefulWidget {
  @override
  State<_PulsingLogo> createState() => _PulsingLogoState();
}

class _PulsingLogoState extends State<_PulsingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _scale = Tween<double>(
      begin: 0.92,
      end: 1.08,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.colors.accent, const Color(0xFF5B9CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: context.colors.accent.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Center(
          child: Text(
            'AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
