import 'package:flutter/material.dart';

import '../mellon_theme.dart';

/// A painted glass surface: no per-card backdrop filter or animation layer.
class ClubGlassSurface extends StatelessWidget {
  const ClubGlassSurface({
    required this.child,
    this.radius = 20,
    this.selected = false,
    this.flat = false,
    super.key,
  });
  final Widget child;
  final double radius;
  final bool selected;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    final effectiveRadius = design.enabled && radius == 20
        ? design.radius
        : radius;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final tint = selected
        ? Color.lerp(colors.surface, colors.primary, .10)!
        : colors.surface;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(effectiveRadius),
        boxShadow: flat
            ? const []
            : [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: dark ? .10 : .035),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(effectiveRadius),
          side: BorderSide(
            color: flat
                ? Colors.transparent
                : selected
                ? colors.primary.withValues(alpha: .48)
                : Colors.white.withValues(alpha: dark ? .18 : .85),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                flat
                    ? Colors.transparent
                    : tint.withValues(
                        alpha: contrast
                            ? 1
                            : design.enabled
                            ? (dark ? .9 : design.surfaceTop)
                            : .86,
                      ),
                flat
                    ? Colors.transparent
                    : tint.withValues(
                        alpha: contrast
                            ? 1
                            : design.enabled
                            ? (dark ? .8 : design.surfaceBottom)
                            : .72,
                      ),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
