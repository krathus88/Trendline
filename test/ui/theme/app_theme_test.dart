import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/theme/app_colors.dart';
import 'package:trendline/ui/theme/app_theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const normalText = 4.5; // WCAG AA, body text
  const uiElement = 3.0; // WCAG AA, non-text UI and large text

  for (final (name, colors) in [
    ('light', AppColors.light),
    ('dark', AppColors.dark),
  ]) {
    group('$name palette contrast', () {
      for (final (bgName, bg) in [
        ('background', colors.background),
        ('surface', colors.surface),
      ]) {
        test('text levels are readable on $bgName', () {
          for (final (fgName, fg) in [
            ('textPrimary', colors.textPrimary),
            ('textSecondary', colors.textSecondary),
            ('textTertiary', colors.textTertiary),
          ]) {
            expect(contrast(fg, bg), greaterThan(normalText), reason: fgName);
          }
        });

        test('accent, error and macro colours stand out on $bgName', () {
          for (final (fgName, fg) in [
            ('accent', colors.accent),
            ('error', colors.error),
            ('warning', colors.warning),
            ('protein', colors.protein),
            ('carbs', colors.carbs),
            ('fat', colors.fat),
            ('fibre', colors.fibre),
          ]) {
            expect(contrast(fg, bg), greaterThan(uiElement), reason: fgName);
          }
        });
      }

      test('text on the accent is readable', () {
        expect(
          contrast(colors.onAccent, colors.accent),
          greaterThan(normalText),
        );
      });

      test('text on the soft accent is readable', () {
        expect(
          contrast(colors.textPrimary, colors.accentSoft),
          greaterThan(normalText),
        );
      });
    });
  }

  group('AppTheme', () {
    test('exposes AppColors on both themes', () {
      expect(AppTheme.light.extension<AppColors>(), AppColors.light);
      expect(AppTheme.dark.extension<AppColors>(), AppColors.dark);
    });

    test('has matching brightness', () {
      expect(AppTheme.light.brightness, Brightness.light);
      expect(AppTheme.dark.brightness, Brightness.dark);
    });

    test('surfaces are not tinted by Material', () {
      expect(AppTheme.light.colorScheme.surfaceTint, Colors.transparent);
      expect(AppTheme.dark.colorScheme.surfaceTint, Colors.transparent);
    });
  });

  group('AppColors.lerp', () {
    test('returns the end points at 0 and 1', () {
      final atStart = AppColors.light.lerp(AppColors.dark, 0);
      final atEnd = AppColors.light.lerp(AppColors.dark, 1);
      expect(atStart.background, AppColors.light.background);
      expect(atEnd.background, AppColors.dark.background);
    });

    test('returns itself when the other side is null', () {
      expect(AppColors.light.lerp(null, 0.5), same(AppColors.light));
    });
  });
}
