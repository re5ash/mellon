import 'package:flutter/material.dart';

import 'appearance_palette.dart';
import 'appearance_settings.dart';
import 'mellon_theme.dart';
import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData forAppearance(
    AppearanceSettings settings,
    Brightness brightness,
  ) => _build(brightness, settings: settings);
  static ThemeData _build(
    Brightness brightness, {
    AppearanceSettings settings = const AppearanceSettings(),
  }) {
    final design = MellonThemeStyle(
      settings.visualTheme,
      customAccent: settings.themeAccentOverride
          ? AppearancePalette.color(settings.accentIndex)
          : null,
    );
    final dark = brightness == Brightness.dark;
    final graphite = settings.nightPalette == NightPalette.graphite;
    final accent = design.enabled && !dark
        ? design.accent
        : AppearancePalette.color(settings.accentIndex, dark: dark);
    final surface = dark
        ? (graphite ? const Color(0xFF242628) : const Color(0xFF1B2C3C))
        : Colors.white;
    final colors =
        ColorScheme.fromSeed(
          seedColor: AppearancePalette.color(settings.accentIndex),
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: dark ? const Color(0xFF102030) : Colors.white,
          secondary: accent,
          onSecondary: dark ? const Color(0xFF102030) : Colors.white,
          surface: surface,
          onSurface: dark
              ? const Color(0xFFE5EDF5)
              : design.enabled
              ? design.ink
              : const Color(0xFF172C48),
          onSurfaceVariant: dark
              ? const Color(0xFFA9BACB)
              : design.enabled
              ? design.muted
              : const Color(0xFF657C92),
          primaryContainer: Color.lerp(surface, accent, dark ? .22 : .10),
          onPrimaryContainer: dark
              ? const Color(0xFFE5EDF5)
              : const Color(0xFF172C48),
        );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      extensions: [design],
      colorScheme: colors,
      brightness: brightness,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(
        design.enabled ? design.radius : AppLayout.radius,
      ),
      borderSide: BorderSide.none,
    );
    return base.copyWith(
      scaffoldBackgroundColor: dark
          ? (graphite ? const Color(0xFF17191B) : AppPalette.darkSurface)
          : design.enabled
          ? design.base
          : settings.preset == AppearancePreset.day
          ? const Color(0xFFF8FAFD)
          : Color.lerp(AppPalette.lightSurface, accent, .025),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: base.textTheme.headlineSmall?.copyWith(
          fontFamily: design.enabled
              ? design.headingFamily
              : AppType.headingFamily,
          color: colors.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 1,
        shadowColor: colors.primary.withValues(alpha: 0.09),
        color: colors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            design.enabled ? design.radius : AppLayout.radius,
          ),
          side: BorderSide(
            color: colors.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.all(AppSpace.md),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              design.enabled ? design.radius : AppLayout.radius,
            ),
          ),
        ),
      ),
      textTheme: base.textTheme.copyWith(
        titleSmall: design.enabled
            ? base.textTheme.titleSmall?.copyWith(
                fontFamily: design.headingFamily,
              )
            : base.textTheme.titleSmall,
        titleMedium: design.enabled
            ? base.textTheme.titleMedium?.copyWith(
                fontFamily: design.headingFamily,
              )
            : base.textTheme.titleMedium,
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: design.enabled
              ? design.headingFamily
              : AppType.headingFamily,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: design.enabled
              ? design.headingFamily
              : AppType.headingFamily,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: design.enabled
              ? design.headingFamily
              : AppType.headingFamily,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: design.enabled
              ? design.headingFamily
              : AppType.headingFamily,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      ),
    );
  }
}
