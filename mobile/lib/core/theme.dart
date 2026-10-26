import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Palette values chosen for outdoor readability: high contrast text on a
/// near-black canvas, one restrained emerald accent, no decorative gradients.
class AppColors {
  const AppColors._();

  static const Color accentDark = Color(0xFF34D399);
  static const Color accentLight = Color(0xFF0F766E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}

const ShadColorScheme _darkScheme = ShadColorScheme(
  background: Color(0xFF080B10),
  foreground: Color(0xFFE9EEF4),
  card: Color(0xFF101720),
  cardForeground: Color(0xFFE9EEF4),
  popover: Color(0xFF121A24),
  popoverForeground: Color(0xFFE9EEF4),
  primary: AppColors.accentDark,
  primaryForeground: Color(0xFF04140E),
  secondary: Color(0xFF1B2430),
  secondaryForeground: Color(0xFFE9EEF4),
  muted: Color(0xFF161F2A),
  mutedForeground: Color(0xFF9AA9B8),
  accent: Color(0xFF1E2A38),
  accentForeground: Color(0xFFE9EEF4),
  destructive: AppColors.danger,
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFF243040),
  input: Color(0xFF1A2430),
  ring: AppColors.accentDark,
  selection: Color(0x552DD4A7),
);

const ShadColorScheme _lightScheme = ShadColorScheme(
  background: Color(0xFFF6F7F9),
  foreground: Color(0xFF0C1219),
  card: Color(0xFFFFFFFF),
  cardForeground: Color(0xFF0C1219),
  popover: Color(0xFFFFFFFF),
  popoverForeground: Color(0xFF0C1219),
  primary: AppColors.accentLight,
  primaryForeground: Color(0xFFFFFFFF),
  secondary: Color(0xFFE9EDF2),
  secondaryForeground: Color(0xFF0C1219),
  muted: Color(0xFFEDF1F5),
  mutedForeground: Color(0xFF556170),
  accent: Color(0xFFE4EAEF),
  accentForeground: Color(0xFF0C1219),
  destructive: Color(0xFFDC2626),
  destructiveForeground: Color(0xFFFFFFFF),
  border: Color(0xFFD8DFE7),
  input: Color(0xFFF1F4F7),
  ring: AppColors.accentLight,
  selection: Color(0x330F766E),
);

ThemeData _materialTheme(Brightness brightness, ShadColorScheme scheme) {
  final base = ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brightness == Brightness.dark ? AppColors.accentDark : AppColors.accentLight,
      brightness: brightness,
    ),
    scaffoldBackgroundColor: scheme.background,
    visualDensity: VisualDensity.standard,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(fontSizeFactor: 1.0),
    splashFactory: InkSparkle.splashFactory,
  );
}

ShadThemeData buildDarkTheme() {
  return ShadThemeData(
    brightness: Brightness.dark,
    colorScheme: _darkScheme,
    radius: const BorderRadius.all(Radius.circular(14)),
  );
}

ShadThemeData buildLightTheme() {
  return ShadThemeData(
    brightness: Brightness.light,
    colorScheme: _lightScheme,
    radius: const BorderRadius.all(Radius.circular(14)),
  );
}

ThemeData buildMaterialTheme(Brightness brightness) {
  return _materialTheme(brightness, brightness == Brightness.dark ? _darkScheme : _lightScheme);
}
