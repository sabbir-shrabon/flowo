import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Duration option for the adapt plan popup
class DurationOption {
  final int days;
  final String label;
  final bool isCustom;

  const DurationOption({
    required this.days,
    required this.label,
    this.isCustom = false,
  });
}

const List<DurationOption> _defaultDurations = [
  DurationOption(days: 7, label: '7 days'),
  DurationOption(days: 14, label: '14 days'),
  DurationOption(days: 30, label: '30 days'),
  DurationOption(days: 60, label: '60 days'),
  DurationOption(days: 90, label: '90 days'),
];

const List<String> _dayLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

class AdaptPlanResult {
  final int durationDays;
  final List<int> workingDays;

  const AdaptPlanResult({
    required this.durationDays,
    required this.workingDays,
  });
}

/// Modal bottom sheet for "Adapt with Plan" feature
class AdaptWithPlanPopup extends StatefulWidget {
  final String planTitle;
  final int? initialDurationDays;
  final List<int>? initialWorkingDays;
  final VoidCallback? onCancel;

  const AdaptWithPlanPopup({
    super.key,
    required this.planTitle,
    this.initialDurationDays,
    this.initialWorkingDays,
    this.onCancel,
  });

  @override
  State<AdaptWithPlanPopup> createState() => _AdaptWithPlanPopupState();
}

class _AdaptWithPlanPopupState extends State<AdaptWithPlanPopup> {
  int? _selectedDuration;
  bool _isCustom = false;
  final _customController = TextEditingController();

  // Working days: 0=Mon, 6=Sun
  final Set<int> _workingDays = {0, 1, 2, 3, 4}; // Default: Mon-Fri

  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialDurationDays != null) {
      final match = _defaultDurations.firstWhere(
        (d) => d.days == widget.initialDurationDays,
        orElse: () => const DurationOption(days: 0, label: '', isCustom: true),
      );
      if (match.days > 0) {
        _selectedDuration = widget.initialDurationDays;
      } else {
        _isCustom = true;
        _customController.text = widget.initialDurationDays.toString();
      }
    }
    if (widget.initialWorkingDays != null &&
        widget.initialWorkingDays!.isNotEmpty) {
      _workingDays.clear();
      _workingDays.addAll(widget.initialWorkingDays!);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggleWorkingDay(int day) {
    setState(() {
      if (_workingDays.contains(day)) {
        if (_workingDays.length > 1) {
          _workingDays.remove(day);
        }
      } else {
        _workingDays.add(day);
      }
    });
  }

  int get _finalDurationDays {
    if (_isCustom) {
      final parsed = int.tryParse(_customController.text);
      return parsed ?? 30;
    }
    return _selectedDuration ?? 30;
  }

  void _onSubmit() {
    final days = _finalDurationDays;
    if (days < 1 || days > 365) {
      setState(() => _error = 'Please enter a valid duration (1-365 days)');
      return;
    }
    if (_workingDays.isEmpty) {
      setState(() => _error = 'Please select at least one working day');
      return;
    }

    Navigator.of(context).pop(
      AdaptPlanResult(
        durationDays: days,
        workingDays: _workingDays.toList()..sort(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Adapt with Plan',
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.planTitle,
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Question 1: Duration
                  Text(
                    'In how many days do you want to complete this plan?',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Duration chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._defaultDurations.map((d) => _buildDurationChip(d)),
                      _buildCustomChip(),
                    ],
                  ),

                  // Custom input
                  if (_isCustom) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: 'Enter number of days',
                        hintStyle: TextStyle(color: context.colors.textMuted),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
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
                          borderSide: BorderSide(
                            color: context.colors.accent,
                            width: 2,
                          ),
                        ),
                      ),
                      style: TextStyle(color: context.colors.textPrimary),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Question 2: Working days
                  Text(
                    'Which days will you work on this plan?',
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Day toggles
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(7, (i) => _buildDayToggle(i)),
                  ),

                  // Error message
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: context.colors.error,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: context.colors.error,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Bottom buttons
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.background,
              border: Border(top: BorderSide(color: context.colors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Cancel
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: () {
                        widget.onCancel?.call();
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: context.colors.border),
                        foregroundColor: context.colors.textSecondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Adapt
                  Expanded(
                    flex: 3,
                    child: FilledButton(
                      onPressed: _onSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.accent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Adapt Plan',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationChip(DurationOption option) {
    final selected = !_isCustom && _selectedDuration == option.days;
    return ChoiceChip(
      label: Text(option.label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _selectedDuration = option.days;
          _isCustom = false;
          _error = null;
        });
      },
      labelStyle: TextStyle(
        color: selected ? Colors.white : context.colors.textPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: context.colors.elevated,
      selectedColor: context.colors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? context.colors.accent : context.colors.border,
        ),
      ),
    );
  }

  Widget _buildCustomChip() {
    return ChoiceChip(
      label: const Text('Custom'),
      selected: _isCustom,
      onSelected: (_) {
        setState(() {
          _isCustom = true;
          _selectedDuration = null;
          _error = null;
        });
      },
      labelStyle: TextStyle(
        color: _isCustom ? Colors.white : context.colors.textPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: context.colors.elevated,
      selectedColor: context.colors.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: _isCustom ? context.colors.accent : context.colors.border,
        ),
      ),
    );
  }

  Widget _buildDayToggle(int dayIndex) {
    final selected = _workingDays.contains(dayIndex);
    final label = _dayLabels[dayIndex];

    return GestureDetector(
      onTap: () => _toggleWorkingDay(dayIndex),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected ? context.colors.accent : context.colors.elevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? context.colors.accent : context.colors.border,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : context.colors.textPrimary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the Adapt with Plan popup as a modal bottom sheet
Future<AdaptPlanResult?> showAdaptWithPlanPopup(
  BuildContext context, {
  required String planTitle,
  int? initialDurationDays,
  List<int>? initialWorkingDays,
}) async {
  return showModalBottomSheet<AdaptPlanResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AdaptWithPlanPopup(
      planTitle: planTitle,
      initialDurationDays: initialDurationDays,
      initialWorkingDays: initialWorkingDays,
    ),
  );
}
