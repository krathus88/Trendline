import 'package:material_ui/material_ui.dart';

/// The app's font family. `null` uses the platform font (Roboto on Android,
/// Segoe UI on Windows). A bundled font can be dropped in here later without
/// touching any screen.
const String? appFontFamily = null;

/// A small, consistent type scale. Large sizes get slightly tighter letter
/// spacing so headings and big numbers don't look loose.
TextTheme buildTextTheme({required Color primary, required Color secondary}) {
  TextStyle style(
    double size,
    double height,
    FontWeight weight, {
    double letterSpacing = 0,
    Color? color,
  }) {
    return TextStyle(
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color ?? primary,
    );
  }

  return TextTheme(
    displayLarge: style(40, 44, FontWeight.w600, letterSpacing: -0.8),
    displayMedium: style(34, 40, FontWeight.w600, letterSpacing: -0.6),
    displaySmall: style(28, 34, FontWeight.w600, letterSpacing: -0.4),
    headlineLarge: style(26, 32, FontWeight.w600, letterSpacing: -0.4),
    headlineMedium: style(24, 30, FontWeight.w600, letterSpacing: -0.3),
    headlineSmall: style(22, 28, FontWeight.w600, letterSpacing: -0.2),
    titleLarge: style(20, 26, FontWeight.w600, letterSpacing: -0.2),
    titleMedium: style(16, 22, FontWeight.w600),
    titleSmall: style(14, 20, FontWeight.w600),
    bodyLarge: style(16, 24, FontWeight.w400),
    bodyMedium: style(15, 22, FontWeight.w400),
    bodySmall: style(13, 18, FontWeight.w400, color: secondary),
    labelLarge: style(15, 20, FontWeight.w600),
    labelMedium: style(13, 16, FontWeight.w500),
    labelSmall: style(12, 16, FontWeight.w500, letterSpacing: 0.2),
  );
}

extension NumericText on TextStyle {
  /// Equal-width digits, so numbers line up and don't jitter as they change.
  /// Use for every number the user reads: weights, calories, grams, times.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
