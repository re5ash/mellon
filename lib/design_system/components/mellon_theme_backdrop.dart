import 'package:flutter/material.dart';

import '../mellon_theme.dart';

/// A single cached wallpaper behind the shell, not a blur filter per list row.
/// Only the wallpaper crossfades; navigation and scroll state stay mounted.
class MellonThemeBackdrop extends StatelessWidget {
  const MellonThemeBackdrop({
    required this.child,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final bool enabled;

  static bool covered(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WallpaperScope>()?.active ??
      false;

  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    final active = enabled && design.enabled;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: active
                      ? SizedBox.expand(
                          key: ValueKey(
                            'theme-wallpaper-${design.kind.name}-$dark',
                          ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: design.base,
                              image: DecorationImage(
                                image: AssetImage(design.asset),
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                colorFilter: dark
                                    ? const ColorFilter.mode(
                                        Color(0xb8102032),
                                        BlendMode.srcATop,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.expand(
                          key: ValueKey('theme-wallpaper-none'),
                        ),
                ),
              ),
            ),
          ),
        ),
        _WallpaperScope(active: active, child: child),
      ],
    );
  }
}

class _WallpaperScope extends InheritedWidget {
  const _WallpaperScope({required this.active, required super.child});
  final bool active;
  @override
  bool updateShouldNotify(_WallpaperScope oldWidget) =>
      active != oldWidget.active;
}
