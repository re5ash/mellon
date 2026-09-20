import 'package:flutter/material.dart';

import 'mellon_theme.dart';

/// Palette and surfaces shared by the parish hub, its menu and chat rows.
abstract final class ParishMenuTheme {
  static const blue = Color(0xFF0089FF);
  static const green = Color(0xFF18B767);
  static const orange = Color(0xFFFF613C);
  static const pink = Color(0xFFFF3F7D);
  static const ink = Color(0xFF101B50);
  static const muted = Color(0xFF7488BE);
  static const background = Color(0xFFEFF8FC);
  static const accents = [
    blue,
    pink,
    Color(0xFF56B1C5),
    green,
    orange,
    Color(0xFF22B7C0),
    Color(0xFF00A88F),
    Color(0xFFFFA217),
    Color(0xFF51C96B),
    Color(0xFFAB68E8),
    Color(0xFF6C99FF),
  ];

  static ThemeData from(ThemeData base) {
    // Reference themes supply their own typography and palette. Do not erase
    // them when entering a club or rebuilding its cached identity widget.
    if (base.extension<MellonThemeStyle>()?.enabled ?? false) return base;
    final dark = base.brightness == Brightness.dark;
    final colors = base.colorScheme.copyWith(
      onSurface: dark ? const Color(0xFFE4EEFF) : ink,
      onSurfaceVariant: dark ? const Color(0xFFABBDDF) : muted,
    );
    final text = ThemeData(brightness: base.brightness).textTheme
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
    return base.copyWith(
      colorScheme: colors,
      scaffoldBackgroundColor: base.scaffoldBackgroundColor,
      textTheme: text.copyWith(
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: base.scaffoldBackgroundColor,
        foregroundColor: colors.onSurface,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationRailTheme: base.navigationRailTheme.copyWith(
        backgroundColor: base.scaffoldBackgroundColor,
        selectedIconTheme: IconThemeData(color: colors.primary),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: colors.primary,
        ),
        unselectedIconTheme: IconThemeData(color: colors.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? colors.primary
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class ParishColorIcon extends StatelessWidget {
  const ParishColorIcon({
    required this.icon,
    required this.color,
    this.solid = false,
    super.key,
  });
  final IconData icon;
  final Color color;
  final bool solid;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: solid
          ? LinearGradient(
              colors: [Color.lerp(color, Colors.white, .16)!, color],
            )
          : null,
      color: solid ? null : color.withValues(alpha: .1),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, size: 28, color: solid ? Colors.white : color),
    ),
  );
}
