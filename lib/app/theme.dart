import 'package:flutter/material.dart';

/// 语义化色板。深色是默认，浅色跟随系统外观；应用内不提供外观开关。
///
/// 颜色角色：brass（品牌/主操作/封印）、green（已验证/健康）、amber（警告）、
/// red（危险）、blue（信息/链接）。文字与表面的对比度均按 WCAG AA 计算。
class _AppPalette {
  const _AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.borderSoft,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentDeep,
    required this.onAccent,
    required this.success,
    required this.blue,
    required this.amber,
    required this.danger,
    required this.violet,
    required this.logBackground,
    required this.warningSurface,
    required this.warningBorder,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color border;
  final Color borderSoft;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentDeep;
  final Color onAccent;
  final Color success;
  final Color blue;
  final Color amber;
  final Color danger;
  final Color violet;
  final Color logBackground;
  final Color warningSurface;
  final Color warningBorder;
}

const _darkPalette = _AppPalette(
  brightness: Brightness.dark,
  background: Color(0xFF0E1116),
  surface: Color(0xFF151A21),
  surfaceRaised: Color(0xFF1C232C),
  border: Color(0xFF2D3742),
  borderSoft: Color(0xFF232C36),
  text: Color(0xFFEDE7DA),
  muted: Color(0xFFB0A99C),
  faint: Color(0xFF948E82),
  accent: Color(0xFFD2AE63),
  accentDeep: Color(0xFF8F742F),
  onAccent: Color(0xFF1A1408),
  success: Color(0xFF64C99F),
  blue: Color(0xFF82A7D9),
  amber: Color(0xFFE0A458),
  danger: Color(0xFFE07A6E),
  violet: Color(0xFFB9A0D8),
  logBackground: Color(0xFF0A0D12),
  warningSurface: Color(0xFF2A2113),
  warningBorder: Color(0xFF4D3B1A),
);

const _lightPalette = _AppPalette(
  brightness: Brightness.light,
  background: Color(0xFFF3EEE4),
  surface: Color(0xFFFCF9F3),
  surfaceRaised: Color(0xFFF0E9DC),
  border: Color(0xFFD8CEBD),
  borderSoft: Color(0xFFE7DFD2),
  text: Color(0xFF1E1B16),
  muted: Color(0xFF5E574C),
  faint: Color(0xFF6F675A),
  accent: Color(0xFF7A5C17),
  accentDeep: Color(0xFF5F4712),
  onAccent: Color(0xFFFFF8E8),
  success: Color(0xFF2A6E57),
  blue: Color(0xFF3E5F8A),
  amber: Color(0xFF8A5A12),
  danger: Color(0xFFA63A32),
  violet: Color(0xFF6B4D8A),
  logBackground: Color(0xFFF7F2E8),
  warningSurface: Color(0xFFF6EBD2),
  warningBorder: Color(0xFFE2C58D),
);

abstract final class AppColors {
  static _AppPalette _palette = _darkPalette;

  static void apply(Brightness brightness) {
    _palette = brightness == Brightness.dark ? _darkPalette : _lightPalette;
  }

  static Brightness get brightness => _palette.brightness;
  static bool get isDark => _palette.brightness == Brightness.dark;
  static Color get background => _palette.background;
  static Color get surface => _palette.surface;
  static Color get surfaceRaised => _palette.surfaceRaised;
  static Color get border => _palette.border;
  static Color get borderSoft => _palette.borderSoft;
  static Color get text => _palette.text;
  static Color get muted => _palette.muted;
  static Color get faint => _palette.faint;
  static Color get accent => _palette.accent;
  static Color get accentDeep => _palette.accentDeep;
  static Color get onAccent => _palette.onAccent;
  static Color get success => _palette.success;
  static Color get blue => _palette.blue;
  static Color get amber => _palette.amber;
  static Color get danger => _palette.danger;
  static Color get violet => _palette.violet;
  static Color get logBackground => _palette.logBackground;
  static Color get warningSurface => _palette.warningSurface;
  static Color get warningBorder => _palette.warningBorder;
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme(
    brightness: AppColors.brightness,
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.blue,
    onSecondary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    onError: AppColors.onAccent,
    outline: AppColors.border,
  );

  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(8)),
    borderSide: BorderSide(color: AppColors.border),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: AppColors.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
    focusColor: AppColors.accent.withValues(alpha: 0.22),
    hoverColor: AppColors.surfaceRaised,
    textTheme: TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: -0.6,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.6,
        color: AppColors.text,
      ),
      bodyMedium: TextStyle(
        fontSize: 13.5,
        height: 1.55,
        color: AppColors.muted,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.45,
        color: AppColors.faint,
      ),
      labelLarge: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: AppColors.text,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: AppColors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: AppColors.faint, fontSize: 13),
      labelStyle: TextStyle(color: AppColors.muted, fontSize: 13),
      errorStyle: TextStyle(color: AppColors.danger, fontSize: 11.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.muted,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 12.5),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.onAccent
            : AppColors.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.border,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.borderSoft,
      circularTrackColor: AppColors.borderSoft,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(AppColors.onAccent),
      side: BorderSide(color: AppColors.faint),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.border),
      radius: const Radius.circular(8),
      thickness: WidgetStateProperty.all(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
