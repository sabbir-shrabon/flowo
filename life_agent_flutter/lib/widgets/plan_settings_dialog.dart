import 'package:flutter/material.dart';
import '../models/plan_models.dart';
import '../theme/app_theme.dart';
import 'adapt_with_plan_popup.dart';

enum _PlanSettingsTab { rename, stop, adapt, delete }

typedef PlanRenameCallback = Future<void> Function(String title);
typedef PlanAdaptCallback = Future<void> Function(AdaptPlanResult result);

class PlanSettingsDialog extends StatefulWidget {
  final PlanResponse plan;
  final PlanRenameCallback? onRename;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;
  final Future<void> Function()? onDelete;
  final PlanAdaptCallback? onAdapt;

  const PlanSettingsDialog({
    super.key,
    required this.plan,
    this.onRename,
    this.onPause,
    this.onResume,
    this.onDelete,
    this.onAdapt,
  });

  @override
  State<PlanSettingsDialog> createState() => _PlanSettingsDialogState();
}

class _PlanSettingsDialogState extends State<PlanSettingsDialog> {
  _PlanSettingsTab _selected = _PlanSettingsTab.adapt;
  late final TextEditingController _renameController;
  late final TextEditingController _customDaysController;
  int? _selectedDuration;
  bool _isCustomDuration = false;
  final Set<int> _workingDays = {0, 1, 2, 3, 4};
  bool _busy = false;
  String? _error;

  static const _durationOptions = [7, 14, 30, 60, 90];
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  bool get _isAdapted =>
      widget.plan.durationDays != null && _initialWorkingDays().isNotEmpty;

  bool get _canStop =>
      widget.plan.status == PlanStatus.active && widget.onPause != null;

  bool get _canResume =>
      widget.plan.status == PlanStatus.paused && widget.onResume != null;

  @override
  void initState() {
    super.initState();
    _renameController = TextEditingController(text: widget.plan.title ?? '');
    _customDaysController = TextEditingController();
    final initialDuration = widget.plan.durationDays;
    if (initialDuration != null && _durationOptions.contains(initialDuration)) {
      _selectedDuration = initialDuration;
    } else if (initialDuration != null) {
      _isCustomDuration = true;
      _customDaysController.text = initialDuration.toString();
    } else {
      _selectedDuration = 30;
    }

    final days = _initialWorkingDays();
    if (days.isNotEmpty) {
      _workingDays
        ..clear()
        ..addAll(days);
    }
  }

  @override
  void dispose() {
    _renameController.dispose();
    _customDaysController.dispose();
    super.dispose();
  }

  List<int> _initialWorkingDays() {
    final raw = widget.plan.schedulePrefs?['working_days'];
    if (raw is List) {
      return raw
          .map((d) => d is int ? d : int.tryParse(d.toString()))
          .whereType<int>()
          .where((d) => d >= 0 && d <= 6)
          .toList();
    }
    return const [];
  }

  int? _durationValue() {
    if (_isCustomDuration) {
      return int.tryParse(_customDaysController.text.trim());
    }
    return _selectedDuration;
  }

  Future<void> _run(Future<void> Function() action, {bool close = true}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && close) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitRename() async {
    final title = _renameController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Plan name cannot be empty.');
      return;
    }
    final onRename = widget.onRename;
    if (onRename == null) return;
    await _run(() => onRename(title));
  }

  Future<void> _submitAdapt() async {
    final duration = _durationValue();
    if (duration == null || duration < 1 || duration > 365) {
      setState(() => _error = 'Choose a duration between 1 and 365 days.');
      return;
    }
    if (_workingDays.isEmpty) {
      setState(() => _error = 'Choose at least one working day.');
      return;
    }
    final onAdapt = widget.onAdapt;
    if (onAdapt == null) return;
    await _run(
      () => onAdapt(
        AdaptPlanResult(
          durationDays: duration,
          workingDays: _workingDays.toList()..sort(),
        ),
      ),
    );
  }

  Future<void> _submitStopOrResume() async {
    if (_canResume) {
      await _run(widget.onResume!);
    } else if (_canStop) {
      await _run(widget.onPause!);
    }
  }

  Future<void> _submitDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    await _run(onDelete);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.9).clamp(320.0, 920.0);
    final height = (size.height * 0.8).clamp(420.0, 620.0);
    final compact = width < 560;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: height),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _header(),
              Expanded(
                child: compact
                    ? Column(
                        children: [
                          _mobileTabs(),
                          Expanded(child: _detailPane()),
                        ],
                      )
                    : Row(
                        children: [
                          SizedBox(width: 220, child: _sideNav()),
                          VerticalDivider(
                            width: 1,
                            color: context.colors.border,
                          ),
                          Expanded(child: _detailPane()),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 18, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plan Settings',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.plan.title ?? 'Untitled Plan',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sideNav() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 16, 18),
      child: Column(
        children: [
          _navButton(Icons.edit_outlined, 'Rename', _PlanSettingsTab.rename),
          _navButton(
            _canResume ? Icons.play_arrow_outlined : Icons.pause_outlined,
            _canResume ? 'Resume this plan' : 'Stop this plan',
            _PlanSettingsTab.stop,
            enabled: _canStop || _canResume,
          ),
          _navButton(
            Icons.tune_outlined,
            'Adapt your plan',
            _PlanSettingsTab.adapt,
          ),
          const Spacer(),
          _navButton(
            Icons.delete_outline,
            'Delete',
            _PlanSettingsTab.delete,
            destructive: true,
            enabled: widget.onDelete != null,
          ),
        ],
      ),
    );
  }

  Widget _mobileTabs() {
    final tabs = [
      (Icons.edit_outlined, 'Rename', _PlanSettingsTab.rename, true, false),
      (
        _canResume ? Icons.play_arrow_outlined : Icons.pause_outlined,
        _canResume ? 'Resume' : 'Stop',
        _PlanSettingsTab.stop,
        _canStop || _canResume,
        false,
      ),
      (Icons.tune_outlined, 'Adapt', _PlanSettingsTab.adapt, true, false),
      (
        Icons.delete_outline,
        'Delete',
        _PlanSettingsTab.delete,
        widget.onDelete != null,
        true,
      ),
    ];

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return _navButton(
            tab.$1,
            tab.$2,
            tab.$3,
            enabled: tab.$4,
            destructive: tab.$5,
            compact: true,
          );
        },
      ),
    );
  }

  Widget _navButton(
    IconData icon,
    String label,
    _PlanSettingsTab tab, {
    bool enabled = true,
    bool destructive = false,
    bool compact = false,
  }) {
    final selected = _selected == tab;
    final fg = destructive ? context.colors.error : context.colors.textPrimary;
    return Material(
      color: selected ? context.colors.background : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled && !_busy
            ? () {
                setState(() {
                  _selected = tab;
                  _error = null;
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: compact ? null : double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 12,
            vertical: 12,
          ),
          child: Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            children: [
              Icon(
                icon,
                size: 19,
                color: enabled ? fg : context.colors.textMuted,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? fg : context.colors.textMuted,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailPane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: switch (_selected) {
                  _PlanSettingsTab.rename => _renamePane(),
                  _PlanSettingsTab.stop => _stopPane(),
                  _PlanSettingsTab.adapt => _adaptPane(),
                  _PlanSettingsTab.delete => _deletePane(),
                },
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: context.colors.error, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renamePane() {
    return Column(
      key: const ValueKey('rename'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle('Rename', 'Change the name shown across your plans.'),
        const SizedBox(height: 18),
        TextField(
          controller: _renameController,
          autofocus: true,
          enabled: !_busy,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: const InputDecoration(hintText: 'Plan name'),
          onSubmitted: (_) => _submitRename(),
        ),
        const SizedBox(height: 18),
        _primaryButton('Save name', _submitRename),
      ],
    );
  }

  Widget _stopPane() {
    final canAct = _canStop || _canResume;
    return Column(
      key: const ValueKey('stop'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(
          _canResume ? 'Resume this plan' : 'Stop this plan',
          _canResume
              ? 'Put this plan back into your active schedule.'
              : 'Pause this plan so it stops showing as active work.',
        ),
        const SizedBox(height: 18),
        _infoRow('Current status', widget.plan.status.name),
        const SizedBox(height: 18),
        _primaryButton(
          _canResume ? 'Resume plan' : 'Stop plan',
          canAct ? _submitStopOrResume : null,
          danger: !_canResume,
        ),
      ],
    );
  }

  int _computeTasksPerDay() {
    final remaining = widget.plan.remainingTasks;
    if (remaining == 0) return 0;
    final duration = _durationValue() ?? widget.plan.durationDays ?? 1;
    if (duration <= 0) return 0;
    final workingDaysList = _workingDays.toList()..sort();
    if (workingDaysList.isEmpty) return 0;
    // Count working days in the duration window
    final now = DateTime.now();
    int workingDayCount = 0;
    for (int i = 0; i < duration; i++) {
      final d = now.add(Duration(days: i));
      // DateTime.weekday: Mon=1…Sun=7, our working_days: Mon=0…Sun=6
      if (workingDaysList.contains(d.weekday - 1)) {
        workingDayCount++;
      }
    }
    if (workingDayCount == 0) return 0;
    return (remaining / workingDayCount).round().clamp(1, remaining);
  }

  Widget _adaptPane() {
    if (!_isAdapted) {
      return _unadaptedPane();
    }
    return _adaptedPane();
  }

  Widget _unadaptedPane() {
    return Column(
      key: const ValueKey('adapt-unadapted'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(
          'Adapt your plan',
          'This plan is not yet adapted. Set a completion window and working days to start seeing tasks on your Today screen.',
        ),
        const SizedBox(height: 18),
        _infoRow('Total number of tasks', '${widget.plan.totalTasks}'),
        const SizedBox(height: 0),
        _infoRow('Current setup', 'Not adapted yet'),
        const SizedBox(height: 24),
        _primaryButton('Adapt with plan', _openAdaptPopup),
      ],
    );
  }

  Widget _adaptedPane() {
    final tasksPerDay = _computeTasksPerDay();
    return Column(
      key: const ValueKey('adapt-adapted'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle(
          'Adapt your plan',
          'Your current schedule is loaded here. Change it anytime.',
        ),
        const SizedBox(height: 18),
        _infoRow('Total number of tasks', '${widget.plan.totalTasks}'),
        const SizedBox(height: 0),
        _infoRow('Current setup', _adaptedSummary()),
        if (tasksPerDay > 0) ...[
          const SizedBox(height: 0),
          _infoRow('Tasks per working day', '~$tasksPerDay'),
        ],
        if (widget.plan.startDate != null) ...[
          const SizedBox(height: 0),
          _infoRow('Plan started date', _formatDate(widget.plan.startDate!)),
        ],
        if (widget.plan.endDate != null) ...[
          const SizedBox(height: 0),
          _infoRow('Plan ending date', _formatDate(widget.plan.endDate!)),
        ],
        const SizedBox(height: 24),
        Text(
          'Total days to complete',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in _durationOptions) _durationChip(days),
            _customChip(),
          ],
        ),
        if (_isCustomDuration) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customDaysController,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.colors.textPrimary),
            decoration: const InputDecoration(hintText: 'Enter days'),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Working days of the week',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: List.generate(7, _dayToggle)),
        const SizedBox(height: 24),
        _primaryButton('Update plan', _submitAdapt),
      ],
    );
  }

  Future<void> _openAdaptPopup() async {
    final result = await showAdaptWithPlanPopup(
      context,
      planTitle: widget.plan.title ?? 'Untitled Plan',
      initialDurationDays: widget.plan.durationDays,
      initialWorkingDays: _initialWorkingDays().isNotEmpty
          ? _initialWorkingDays()
          : null,
    );
    if (result == null) return;
    final onAdapt = widget.onAdapt;
    if (onAdapt == null) return;
    await _run(() => onAdapt(result));
  }

  Widget _deletePane() {
    return Column(
      key: const ValueKey('delete'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _paneTitle('Delete', 'This removes the plan and cannot be undone.'),
        const SizedBox(height: 18),
        _primaryButton('Delete plan', _submitDelete, danger: true),
      ],
    );
  }

  Widget _paneTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _adaptedSummary() {
    final days = widget.plan.durationDays;
    final working = _initialWorkingDays()
        .map((day) => _dayLabels[day])
        .join(', ');
    return '$days days, $working';
  }

  String _formatDate(DateTime d) {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Widget _durationChip(int days) {
    final selected = !_isCustomDuration && _selectedDuration == days;
    return ChoiceChip(
      label: Text('$days days'),
      selected: selected,
      onSelected: _busy
          ? null
          : (_) {
              setState(() {
                _selectedDuration = days;
                _isCustomDuration = false;
                _error = null;
              });
            },
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: context.colors.background,
      selectedColor: context.colors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? context.colors.accent : context.colors.border,
        ),
      ),
    );
  }

  Widget _customChip() {
    return ChoiceChip(
      label: const Text('Custom'),
      selected: _isCustomDuration,
      onSelected: _busy
          ? null
          : (_) {
              setState(() {
                _isCustomDuration = true;
                _selectedDuration = null;
                _error = null;
              });
            },
      labelStyle: TextStyle(
        color: _isCustomDuration ? Colors.white : context.colors.textPrimary,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: context.colors.background,
      selectedColor: context.colors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: _isCustomDuration
              ? context.colors.accent
              : context.colors.border,
        ),
      ),
    );
  }

  Widget _dayToggle(int day) {
    final selected = _workingDays.contains(day);
    return InkWell(
      onTap: _busy
          ? null
          : () {
              setState(() {
                if (selected && _workingDays.length > 1) {
                  _workingDays.remove(day);
                } else {
                  _workingDays.add(day);
                }
                _error = null;
              });
            },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? context.colors.accent : context.colors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? context.colors.accent : context.colors.border,
          ),
        ),
        child: Text(
          _dayLabels[day],
          style: TextStyle(
            color: selected ? Colors.white : context.colors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(
    String label,
    Future<void> Function()? onPressed, {
    bool danger = false,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        onPressed: _busy || onPressed == null ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: danger
              ? context.colors.error
              : context.colors.accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

Future<void> showPlanSettingsDialog(
  BuildContext context, {
  required PlanResponse plan,
  PlanRenameCallback? onRename,
  Future<void> Function()? onPause,
  Future<void> Function()? onResume,
  Future<void> Function()? onDelete,
  PlanAdaptCallback? onAdapt,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    builder: (_) => PlanSettingsDialog(
      plan: plan,
      onRename: onRename,
      onPause: onPause,
      onResume: onResume,
      onDelete: onDelete,
      onAdapt: onAdapt,
    ),
  );
}
