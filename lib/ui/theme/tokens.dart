import 'package:material_ui/material_ui.dart';

/// Raw design tokens. Widgets should not read these directly; use
/// `Theme.of(context)` or `context.colors` so light and dark mode both work.
/// The exceptions are [Space], [Radii] and [Motion], which don't vary by
/// theme.

/// Spacing on a 4-pt grid.
abstract final class Space {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal padding for screen content.
  static const double gutter = lg;
}

/// Corner radii. Kept modest: rounded, not bubbly.
abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
}

/// Animation timings. Short on purpose so the app feels quick.
abstract final class Motion {
  /// Taps, toggles, small state changes.
  static const Duration fast = Duration(milliseconds: 120);

  /// Most transitions: expanding a card, swapping content.
  static const Duration medium = Duration(milliseconds: 200);

  /// Screen-level transitions.
  static const Duration slow = Duration(milliseconds: 300);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasised = Curves.easeInOutCubicEmphasized;
}

/// The palette. Warm neutrals with a single deep-green accent. Macro colours
/// are muted so a screen full of them doesn't look like a toy.
abstract final class Palette {
  // Light
  static const Color lightBackground = Color(0xFFF7F7F5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceMuted = Color(0xFFEFEFEC);
  static const Color lightBorder = Color(0xFFE2E2DE);
  static const Color lightTextPrimary = Color(0xFF1A1C1B);
  static const Color lightTextSecondary = Color(0xFF5C615E);
  static const Color lightTextTertiary = Color(0xFF666B68);
  static const Color lightAccent = Color(0xFF2E6F57);
  static const Color lightOnAccent = Color(0xFFFFFFFF);
  static const Color lightAccentSoft = Color(0xFFE3EFEA);
  static const Color lightError = Color(0xFFB3261E);
  static const Color lightWarning = Color(0xFF8F5200);
  static const Color lightProtein = Color(0xFFB4502F);
  static const Color lightCarbs = Color(0xFF9A6F12);
  static const Color lightFat = Color(0xFF45679B);
  static const Color lightFibre = Color(0xFF6E5E9E);

  // Dark
  static const Color darkBackground = Color(0xFF111312);
  static const Color darkSurface = Color(0xFF1A1D1C);
  static const Color darkSurfaceMuted = Color(0xFF232725);
  static const Color darkBorder = Color(0xFF2E3331);
  static const Color darkTextPrimary = Color(0xFFECEEED);
  static const Color darkTextSecondary = Color(0xFFA3A9A6);
  static const Color darkTextTertiary = Color(0xFF858C89);
  static const Color darkAccent = Color(0xFF6CC3A0);
  static const Color darkOnAccent = Color(0xFF0C1F17);
  static const Color darkAccentSoft = Color(0xFF1E3229);
  static const Color darkError = Color(0xFFF2B8B5);
  static const Color darkWarning = Color(0xFFF0B45B);
  static const Color darkProtein = Color(0xFFE8896F);
  static const Color darkCarbs = Color(0xFFE3B556);
  static const Color darkFat = Color(0xFF8AA8D6);
  static const Color darkFibre = Color(0xFFB1A3D6);
}
