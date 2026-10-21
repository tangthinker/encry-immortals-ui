import 'package:flutter/material.dart';

/// 纯色深色界面：不使用任何渐变。
abstract final class AppColors {
  static const background = Color(0xFF0A0D13);
  static const surface = Color(0xFF111722);
  static const surfaceRaised = Color(0xFF161E2B);
  static const border = Color(0xFF253044);
  static const borderSoft = Color(0xFF1B2433);
  static const text = Color(0xFFE8EDF7);
  static const muted = Color(0xFF94A2BC);
  static const faint = Color(0xFF63718B);
  static const accent = Color(0xFF3DDC97);
  static const accentDeep = Color(0xFF167A5A);
  static const blue = Color(0xFF6C9BFF);
  static const amber = Color(0xFFF2C14E);
  static const danger = Color(0xFFFF6B7A);
  static const violet = Color(0xFFAE8CFF);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Color(0xFF04140D),
    secondary: AppColors.blue,
    onSecondary: Color(0xFF06101F),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    onError: Color(0xFF1B0508),
    outline: AppColors.border,
  );

  const inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(9)),
    borderSide: BorderSide(color: AppColors.border),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    splashFactory: InkRipple.splashFactory,
    textTheme: const TextTheme(
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
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.borderSoft,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceRaised,
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppColors.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: AppColors.danger),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: AppColors.faint, fontSize: 13),
      labelStyle: TextStyle(color: AppColors.muted, fontSize: 13),
      errorStyle: TextStyle(color: AppColors.danger, fontSize: 11.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF04140D),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.muted,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceRaised,
      contentTextStyle: TextStyle(color: AppColors.text, fontSize: 12.5),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accent
            : AppColors.faint,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.accentDeep
            : AppColors.border,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.borderSoft,
      circularTrackColor: AppColors.borderSoft,
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
      textStyle: const TextStyle(color: AppColors.text, fontSize: 12),
    ),
  );
}
