import 'package:encry_immortals_ui/app/theme.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color color) {
  double linear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    test('${brightness.name} 色板满足 WCAG AA（小字号 4.5:1）', () {
      AppColors.apply(brightness);
      final surfaces = [AppColors.background, AppColors.surface, AppColors.surfaceRaised];
      for (final foreground in {
        'text': AppColors.text,
        'muted': AppColors.muted,
        'faint': AppColors.faint,
        'accent': AppColors.accent,
        'success': AppColors.success,
        'blue': AppColors.blue,
        'amber': AppColors.amber,
        'danger': AppColors.danger,
        'violet': AppColors.violet,
      }.entries) {
        for (final surface in surfaces) {
          expect(
            _contrast(foreground.value, surface),
            greaterThanOrEqualTo(4.5),
            reason: '${foreground.key} on $surface',
          );
        }
      }
      expect(
        _contrast(AppColors.onAccent, AppColors.accent),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
