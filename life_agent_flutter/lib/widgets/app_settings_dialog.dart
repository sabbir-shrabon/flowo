import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../app.dart'
    show
        themeModeProvider,
        fontSizeProvider,
        userMemoryProvider,
        accentColorProvider,
        AppAccentColor;

// ── Entry point ──────────────────────────────────────────────────────────────

void showAppSettingsDialog(BuildContext context) {
  final isDesktop = MediaQuery.of(context).size.width >= 560;
  if (isDesktop) {
    showDialog(
      context: context,
      builder: (_) => const AppSettingsDialog(),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSettingsMobileScreen()),
    );
  }
}

// ── Section enum ─────────────────────────────────────────────────────────────

enum _SettingsSection {
  appearance,
  accentColor,
  fontSize,
  dataControl,
  upgrade,
  logout,
}

extension _SettingsSectionExt on _SettingsSection {
  String get label => switch (this) {
        _SettingsSection.appearance => 'Appearance',
        _SettingsSection.accentColor => 'Accent Color',
        _SettingsSection.fontSize => 'Font Size',
        _SettingsSection.dataControl => 'Data & Privacy',
        _SettingsSection.upgrade => 'Upgrade',
        _SettingsSection.logout => 'Logout',
      };

  IconData get icon => switch (this) {
        _SettingsSection.appearance => Icons.palette_outlined,
        _SettingsSection.accentColor => Icons.color_lens_outlined,
        _SettingsSection.fontSize => Icons.text_fields,
        _SettingsSection.dataControl => Icons.shield_outlined,
        _SettingsSection.upgrade => Icons.star_outline,
        _SettingsSection.logout => Icons.logout,
      };

  bool get isDestructive => this == _SettingsSection.logout;
}

// ── Desktop Dialog ────────────────────────────────────────────────────────────

class AppSettingsDialog extends ConsumerStatefulWidget {
  const AppSettingsDialog({super.key});

  @override
  ConsumerState<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends ConsumerState<AppSettingsDialog> {
  _SettingsSection _selected = _SettingsSection.appearance;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.88).clamp(360.0, 880.0);
    final height = (size.height * 0.8).clamp(420.0, 600.0);

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
                child: Row(
                  children: [
                    SizedBox(width: 220, child: _sideNav()),
                    VerticalDivider(width: 1, color: context.colors.border),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: KeyedSubtree(
                          key: ValueKey(_selected),
                          child: _SettingsSectionPane(section: _selected),
                        ),
                      ),
                    ),
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
          Icon(Icons.settings_outlined,
              size: 22, color: context.colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Settings',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
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
          for (final s in _SettingsSection.values)
            if (s != _SettingsSection.logout) _navBtn(s),
          const Spacer(),
          _navBtn(_SettingsSection.logout),
        ],
      ),
    );
  }

  Widget _navBtn(_SettingsSection s) {
    final selected = _selected == s;
    final fg = s.isDestructive
        ? context.colors.error
        : context.colors.textPrimary;
    return Material(
      color: selected ? context.colors.background : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _selected = s),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(s.icon, size: 19, color: fg),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  s.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Mobile full-screen ────────────────────────────────────────────────────────

class AppSettingsMobileScreen extends ConsumerWidget {
  const AppSettingsMobileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: Text(
          'Settings',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: context.colors.border),
        ),
      ),
      body: ListView(
        children: [
          for (final s in _SettingsSection.values)
            _MobileSectionTile(section: s),
        ],
      ),
    );
  }
}

class _MobileSectionTile extends StatelessWidget {
  final _SettingsSection section;
  const _MobileSectionTile({required this.section});

  @override
  Widget build(BuildContext context) {
    final fg = section.isDestructive
        ? context.colors.error
        : context.colors.textSecondary;
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Icon(section.icon, size: 22, color: fg),
          title: Text(
            section.label,
            style: TextStyle(
              color: fg,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          trailing: section.isDestructive
              ? null
              : Icon(Icons.chevron_right,
                  size: 20, color: context.colors.textMuted),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AppSettingsSectionScreen(
                  sectionName: section.name,
                ),
              ),
            );
          },
        ),
        Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: context.colors.border,
        ),
      ],
    );
  }
}

// Mobile sub-screen wrapper — takes the section name as a String to keep
// the private enum type out of the public constructor signature.
class AppSettingsSectionScreen extends StatelessWidget {
  final String sectionName;
  const AppSettingsSectionScreen({super.key, required this.sectionName});

  _SettingsSection get _section => _SettingsSection.values.firstWhere(
        (s) => s.name == sectionName,
        orElse: () => _SettingsSection.appearance,
      );

  @override
  Widget build(BuildContext context) {
    final section = _section;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: Text(
          section.label,
          style: TextStyle(
            color: context.colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: context.colors.border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _SettingsSectionPane(section: section),
      ),
    );
  }
}

// ── Section content pane (shared by desktop + mobile) ────────────────────────

class _SettingsSectionPane extends ConsumerStatefulWidget {
  final _SettingsSection section;
  const _SettingsSectionPane({required this.section});

  @override
  ConsumerState<_SettingsSectionPane> createState() =>
      _SettingsSectionPaneState();
}

class _SettingsSectionPaneState extends ConsumerState<_SettingsSectionPane> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: switch (widget.section) {
        _SettingsSection.appearance => _AppearancePane(),
        _SettingsSection.accentColor => const _AccentColorPane(),
        _SettingsSection.fontSize => _FontSizePane(),
        _SettingsSection.dataControl => _DataControlPane(),
        _SettingsSection.upgrade => _UpgradePane(),
        _SettingsSection.logout => _LogoutPane(),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APPEARANCE
// ─────────────────────────────────────────────────────────────────────────────

class _AppearancePane extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Appearance',
            'Choose how Life Agent looks on your device.'),
        const SizedBox(height: 24),
        Text(
          'Theme',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ThemeOptionCard(
                label: 'Light',
                icon: Icons.light_mode_outlined,
                selected: !isDark,
                onTap: () => ref.read(themeModeProvider.notifier).state =
                    ThemeMode.light,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ThemeOptionCard(
                label: 'Dark',
                icon: Icons.dark_mode_outlined,
                selected: isDark,
                onTap: () => ref.read(themeModeProvider.notifier).state =
                    ThemeMode.dark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeOptionCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected
              ? context.colors.accent.withValues(alpha: 0.12)
              : context.colors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? context.colors.accent
                : context.colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
              color: selected
                  ? context.colors.accent
                  : context.colors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? context.colors.accent
                    : context.colors.textSecondary,
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCENT COLOR
// ─────────────────────────────────────────────────────────────────────────────

class _AccentColorPane extends ConsumerWidget {
  const _AccentColorPane();

  static const _options = [
    (value: AppAccentColor.green, label: 'Sage',  color: Color(0xFF3DD6B5)),
    (value: AppAccentColor.blue,  label: 'Ocean', color: Color(0xFF5B9CF6)),
    (value: AppAccentColor.ash,   label: 'Stone', color: Color(0xFF9B9B9B)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(accentColorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Accent Color',
            'Choose the highlight color used throughout the app.'),
        const SizedBox(height: 28),

        // Three swatches
        Row(
          children: [
            for (int i = 0; i < _options.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: _AccentSwatch(
                  color: _options[i].color,
                  label: _options[i].label,
                  selected: current == _options[i].value,
                  onTap: () => ref.read(accentColorProvider.notifier).state =
                      _options[i].value,
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 28),

        // Live preview strip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PREVIEW',
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: context.colors.accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Active plan · 3 tasks today',
                    style: TextStyle(
                      color: context.colors.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: 0.62,
                  backgroundColor:
                      context.colors.accent.withValues(alpha: 0.15),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(context.colors.accent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: context.colors.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Save changes',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AccentSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.1)
              : context.colors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : context.colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: selected
                    ? [BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )]
                    : [],
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : context.colors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FONT SIZE
// ─────────────────────────────────────────────────────────────────────────────

class _FontSizePane extends ConsumerWidget {
  static const _steps = [
    (label: 'XS', value: 11.0),
    (label: 'S', value: 12.5),
    (label: 'Default', value: 14.0),
    (label: 'L', value: 16.0),
    (label: 'XL', value: 18.5),
  ];

  static const _previewText =
      'The quick brown fox jumps over the lazy dog. '
      'Life Agent helps you build great habits every day.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontSize = ref.watch(fontSizeProvider);
    final stepIndex = _closestStep(fontSize);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Font Size',
            'Adjust the text size across the whole app.'),
        const SizedBox(height: 28),

        // Preview box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: MediaQuery(
            // Override scaler inside preview so it mirrors the chosen size
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(fontSize / 14.0),
            ),
            child: Text(
              _previewText,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Step labels row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _steps.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => ref
                      .read(fontSizeProvider.notifier)
                      .state = _steps[i].value,
                  child: Column(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == stepIndex
                              ? context.colors.accent
                              : context.colors.border,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _steps[i].label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == stepIndex
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == stepIndex
                              ? context.colors.accent
                              : context.colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: context.colors.accent,
            inactiveTrackColor: context.colors.border,
            thumbColor: context.colors.accent,
            overlayColor: context.colors.accent.withValues(alpha: 0.15),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            min: 0,
            max: (_steps.length - 1).toDouble(),
            divisions: _steps.length - 1,
            value: stepIndex.toDouble(),
            onChanged: (v) {
              ref.read(fontSizeProvider.notifier).state =
                  _steps[v.round()].value;
            },
          ),
        ),
      ],
    );
  }

  static int _closestStep(double val) {
    int best = 0;
    double bestDist = double.infinity;
    for (var i = 0; i < _steps.length; i++) {
      final d = (_steps[i].value - val).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA & PRIVACY
// ─────────────────────────────────────────────────────────────────────────────

class _DataControlPane extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DataControlPane> createState() => _DataControlPaneState();
}

class _DataControlPaneState extends ConsumerState<_DataControlPane> {
  late final TextEditingController _memoryCtrl;

  @override
  void initState() {
    super.initState();
    _memoryCtrl =
        TextEditingController(text: ref.read(userMemoryProvider));
  }

  @override
  void dispose() {
    _memoryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final email = authState.user?.email ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Data & Privacy',
            'Manage your personal information and memory notes.'),
        const SizedBox(height: 24),

        // Email row
        _infoRow(context, 'Account', email),
        const SizedBox(height: 24),

        Text(
          'Memory note',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tell the AI a bit about yourself so it can personalise its suggestions.',
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _memoryCtrl,
          maxLines: 5,
          style: TextStyle(
              color: context.colors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'optional',
            hintStyle: TextStyle(
                color: context.colors.textMuted.withValues(alpha: 0.6),
                fontStyle: FontStyle.italic),
            filled: true,
            fillColor: context.colors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: context.colors.accent, width: 2),
            ),
          ),
          onChanged: (v) =>
              ref.read(userMemoryProvider.notifier).state = v,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UPGRADE
// ─────────────────────────────────────────────────────────────────────────────

class _UpgradePane extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: replace with real subscription status from auth/backend
    // ignore: prefer_const_declarations
    final bool isPro = const bool.fromEnvironment('LIFE_AGENT_PRO');
    final planLabel = isPro ? '✦  Pro' : 'Free Plan';
    final planDescription =
        isPro ? 'You\'re on the Pro plan.' : 'You\'re on the free plan.';
    final badgeColor = isPro
        ? context.colors.accent.withValues(alpha: 0.15)
        : context.colors.border.withValues(alpha: 0.4);
    final textColor =
        isPro ? context.colors.accent : context.colors.textSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Upgrade',
            'Unlock the full power of Life Agent.'),
        const SizedBox(height: 24),

        // Plan badge
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: context.colors.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  planLabel,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  planDescription,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              // TODO: navigate to billing / upgrade page
            },
            icon: const Icon(Icons.open_in_new, size: 17),
            label: const Text('Manage your account'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGOUT
// ─────────────────────────────────────────────────────────────────────────────

class _LogoutPane extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, 'Logout',
            'You will be signed out of your account on this device.'),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(authProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

Widget _sectionTitle(BuildContext context, String title, String subtitle) {
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

Widget _infoRow(BuildContext context, String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border:
          Border(bottom: BorderSide(color: context.colors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 14)),
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
