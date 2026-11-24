import 'package:material_ui/material_ui.dart';
import 'package:trendline/ui/theme/tokens.dart';

/// Semantic colours that Material's `ColorScheme` has no slot for (text
/// levels, macro colours, warning). Read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const new({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.error,
    required this.warning,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fibre,
  });

  static const AppColors light = AppColors(
    background: Palette.lightBackground,
    surface: Palette.lightSurface,
    surfaceMuted: Palette.lightSurfaceMuted,
    border: Palette.lightBorder,
    textPrimary: Palette.lightTextPrimary,
    textSecondary: Palette.lightTextSecondary,
    textTertiary: Palette.lightTextTertiary,
    accent: Palette.lightAccent,
    onAccent: Palette.lightOnAccent,
    accentSoft: Palette.lightAccentSoft,
    error: Palette.lightError,
    warning: Palette.lightWarning,
    protein: Palette.lightProtein,
    carbs: Palette.lightCarbs,
    fat: Palette.lightFat,
    fibre: Palette.lightFibre,
  );

  static const AppColors dark = AppColors(
    background: Palette.darkBackground,
    surface: Palette.darkSurface,
    surfaceMuted: Palette.darkSurfaceMuted,
    border: Palette.darkBorder,
    textPrimary: Palette.darkTextPrimary,
    textSecondary: Palette.darkTextSecondary,
    textTertiary: Palette.darkTextTertiary,
    accent: Palette.darkAccent,
    onAccent: Palette.darkOnAccent,
    accentSoft: Palette.darkAccentSoft,
    error: Palette.darkError,
    warning: Palette.darkWarning,
    protein: Palette.darkProtein,
    carbs: Palette.darkCarbs,
    fat: Palette.darkFat,
    fibre: Palette.darkFibre,
  );

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color error;
  final Color warning;
  final Color protein;
  final Color carbs;
  final Color fat;
  final Color fibre;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? error,
    Color? warning,
    Color? protein,
    Color? carbs,
    Color? fat,
    Color? fibre,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentSoft: accentSoft ?? this.accentSoft,
      error: error ?? this.error,
      warning: warning ?? this.warning,
      protein: protein ?? this.protein,
      carbs: carbs ?? this.carbs,
      fat: fat ?? this.fat,
      fibre: fibre ?? this.fibre,
    );
  }

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceMuted: mix(surfaceMuted, other.surfaceMuted),
      border: mix(border, other.border),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      accentSoft: mix(accentSoft, other.accentSoft),
      error: mix(error, other.error),
      warning: mix(warning, other.warning),
      protein: mix(protein, other.protein),
      carbs: mix(carbs, other.carbs),
      fat: mix(fat, other.fat),
      fibre: mix(fibre, other.fibre),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The current theme's semantic colours.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
