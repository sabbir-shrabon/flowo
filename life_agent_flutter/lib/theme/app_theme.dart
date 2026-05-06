import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../app.dart' show AppAccentColor;

// ── Theme-aware color system ──────────────────────────────────────────────
// All semantic colors live in ThemeExtension so every widget automatically
// picks the right palette for dark / light mode via context.colors.

class ThemeColors extends ThemeExtension<ThemeColors> {
  final Color background;
  final Color surface;
  final Color elevated;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentBg;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  const ThemeColors({
    required this.background,
    required this.surface,
    required this.elevated,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentBg,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  @override
  ThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? elevated,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentBg,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return ThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      accentBg: accentBg ?? this.accentBg,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  ThemeColors lerp(ThemeColors? other, double t) {
    if (other is! ThemeColors) return this;
    return ThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentBg: Color.lerp(accentBg, other.accentBg, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

// ── Accent Color Helpers ──
Color _getAccentColor(AppAccentColor color) {
  switch (color) {
    case AppAccentColor.blue:
      return const Color(0xFF5B9CF6);
    case AppAccentColor.ash:
      return const Color(0xFF9B9B9B);
    case AppAccentColor.green:
      return const Color(0xFF3DD6B5);
  }
}

// ── Dark palette (DeepSeek-inspired) ──
ThemeColors getDarkColors(AppAccentColor accent) {
  final accentColor = _getAccentColor(accent);
  return ThemeColors(
    background: const Color(0xFF09090F),
    surface: const Color(0xFF0F0F1C),
    elevated: const Color(0xFF17172A),
    border: const Color(0x0FFFFFFF),
    borderStrong: const Color(0x1FFFFFFF),
    textPrimary: const Color(0xFFE8E6F0),
    textSecondary: const Color(0xFF7B7A94),
    textMuted: const Color(0xFF3D3D54),
    accent: accentColor,
    accentBg: accentColor.withValues(alpha: 0.1),
    success: const Color(0xFF3DD6B5), // keep green for success
    warning: const Color(0xFFE8A843),
    error: const Color(0xFFE8605A),
    info: accentColor,
  );
}

// ── Light palette (ChatGPT / DeepSeek light-mode inspired) ──
ThemeColors getLightColors(AppAccentColor accent) {
  final accentColor = _getAccentColor(accent);
  return ThemeColors(
    background: const Color(0xFFF7F7F8),
    surface: const Color(0xFFFFFFFF),
    elevated: const Color(0xFFFFFFFF),
    border: const Color(0xFFE5E5E5),
    borderStrong: const Color(0xFFD9D9D9),
    textPrimary: const Color(0xFF0D0D0D),
    textSecondary: const Color(0xFF6B6B80),
    textMuted: const Color(0xFFACACBE),
    accent: accentColor,
    accentBg: accentColor.withValues(alpha: 0.08),
    success: const Color(0xFF10B981),
    warning: const Color(0xFFD4A017),
    error: const Color(0xFFE8605A),
    info: accentColor,
  );
}

// ── Convenience getters ──
extension ThemeColorsGetter on ThemeData {
  ThemeColors get colors => extension<ThemeColors>()!;
}

extension ContextColorsGetter on BuildContext {
  ThemeColors get colors => Theme.of(this).colors;
}

// ── Legacy static aliases (for gradual migration) ──
// These always return DARK-mode values. Prefer context.colors.
class AppColors {
  static const Color background = Color(0xFF09090F);
  static const Color surface = Color(0xFF0F0F1C);
  static const Color elevated = Color(0xFF17172A);
  static const Color border = Color(0x0FFFFFFF);
  static const Color borderStrong = Color(0x1FFFFFFF);
  static const Color textPrimary = Color(0xFFE8E6F0);
  static const Color textSecondary = Color(0xFF7B7A94);
  static const Color textMuted = Color(0xFF3D3D54);
  static const Color accent = Color(0xFF3DD6B5);
  static const Color accentBg = Color(0x1A3DD6B5);
  static const Color success = Color(0xFF3DD6B5);
  static const Color warning = Color(0xFFE8A843);
  static const Color error = Color(0xFFE8605A);
  static const Color info = Color(0xFF3DD6B5);
  static const Color surfaceLight = elevated;
  static const Color accentLight = accent;
}

class AppTheme {
  // ── Border Radius ──
  static const double radiusCard = 12;
  static const double radiusSmall = 8;
  static const double radiusPill = 20;

  static ThemeData getDarkTheme(AppAccentColor accent) {
    final c = getDarkColors(accent);
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      colorScheme: ColorScheme.dark(
        primary: c.accent,
        secondary: c.accent,
        surface: c.surface,
        error: c.error,
        onPrimary: Colors.white,
        onSurface: c.textPrimary,
      ),
      // Manrope feels more "product" than "template".
      textTheme: GoogleFonts.manropeTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: c.accent),
        ),
        hintStyle: TextStyle(color: c.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.elevated,
        contentTextStyle: TextStyle(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
    );
  }

  static ThemeData getLightTheme(AppAccentColor accent) {
    final c = getLightColors(accent);
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
      colorScheme: ColorScheme.light(
        primary: c.accent,
        secondary: c.accent,
        surface: c.surface,
        error: c.error,
        onPrimary: Colors.white,
        onSurface: c.textPrimary,
      ),
      textTheme: GoogleFonts.manropeTextTheme(
        ThemeData.light().textTheme,
      ).apply(bodyColor: c.textPrimary, displayColor: c.textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          color: c.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: c.accent),
        ),
        hintStyle: TextStyle(color: c.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.surface,
        selectedItemColor: c.accent,
        unselectedItemColor: c.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.elevated,
        contentTextStyle: TextStyle(color: c.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
    );
  }
}
