import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../design_system/mellon_theme.dart';

/// The selected index remains owned by the router, including modal-only taps.
class ClubNavigationBar extends StatefulWidget {
  const ClubNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
    this.showClubs = true,
    super.key,
  });
  final int selectedIndex;
  final bool showClubs;
  final ValueChanged<int> onSelected;

  static const destinations = <({String label, IconData icon})>[
    (label: 'Лента', icon: Icons.view_day_outlined),
    (label: 'Молодёжный клуб', icon: Icons.church_rounded),
    (label: 'Карта', icon: Icons.location_on_outlined),
  ];

  @override
  State<ClubNavigationBar> createState() => _ClubNavigationBarState();
}

class _ClubNavigationBarState extends State<ClubNavigationBar>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  bool _ready = false;
  bool _reduced = false;
  late Rect _fromBounds, _toBounds;
  late Color _fromAccent, _toAccent;
  late Color _fromNeutral, _toNeutral;
  late Color _fromSurface, _toSurface;
  late List<double> _fromWeights;
  int _target = 0;

  List<int> get _indices => [0, if (widget.showClubs) 1, 2];
  double get _progress => Curves.easeOutCubic.transform(_motion.value);
  Color get _accent => Color.lerp(_fromAccent, _toAccent, _progress)!;
  Color get _neutral => Color.lerp(_fromNeutral, _toNeutral, _progress)!;
  Color get _surface => Color.lerp(_fromSurface, _toSurface, _progress)!;
  List<double> get _weights => List.generate(
    3,
    (index) =>
        lerpDouble(_fromWeights[index], index == _target ? 1 : 0, _progress)!,
  );

  // Geometry is stored as fractions so rotation/resize cannot leave stale pixels.
  Rect _boundsFor(int selected, TextDirection direction) {
    final indices = _indices;
    final total = indices.fold<int>(
      0,
      (sum, index) => sum + (index == 1 ? 2 : 1),
    );
    var before = 0;
    for (final index in indices) {
      final weight = index == 1 ? 2 : 1;
      if (index == selected) {
        final left = before / total;
        final right = (before + weight) / total;
        return direction == TextDirection.rtl
            ? Rect.fromLTRB(1 - right, 0, 1 - left, 1)
            : Rect.fromLTRB(left, 0, right, 1);
      }
      before += weight;
    }
    return const Rect.fromLTRB(0, 0, .5, 1);
  }

  Rect get _visualBounds {
    if (_motion.value == 1) return _toBounds;
    final lead = _progress;
    final tail = Curves.easeOutCubic.transform(
      ((_motion.value - .12) / .88).clamp(0.0, 1.0).toDouble(),
    );
    final rightward = _toBounds.center.dx >= _fromBounds.center.dx;
    var left = lerpDouble(
      _fromBounds.left,
      _toBounds.left,
      rightward ? tail : lead,
    )!;
    var right = lerpDouble(
      _fromBounds.right,
      _toBounds.right,
      rightward ? lead : tail,
    )!;
    // Keep the stretch subtle even when skipping the middle destination.
    final maxWidth =
        lerpDouble(_fromBounds.width, _toBounds.width, lead)! + .08;
    if (right - left > maxWidth) {
      if (rightward) {
        left = right - maxWidth;
      } else {
        right = left + maxWidth;
      }
    }
    return Rect.fromLTRB(left, 0, right, 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ClubNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final colors = Theme.of(context).colorScheme;
    final selected = _indices.contains(widget.selectedIndex)
        ? widget.selectedIndex
        : 0;
    final bounds = _boundsFor(selected, Directionality.of(context));
    _reduced =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (!_ready) {
      _fromBounds = _toBounds = bounds;
      _fromAccent = _toAccent = colors.primary;
      _fromNeutral = _toNeutral = colors.onSurfaceVariant;
      _fromSurface = _toSurface = colors.surface;
      _target = selected;
      _fromWeights = List.generate(3, (index) => index == selected ? 1.0 : 0.0);
      _ready = true;
      return;
    }
    if (bounds == _toBounds &&
        selected == _target &&
        colors.primary == _toAccent &&
        colors.onSurfaceVariant == _toNeutral &&
        colors.surface == _toSurface) {
      if (_reduced && _motion.isAnimating) {
        _motion.stop();
        _motion.value = 1;
      }
      return;
    }
    // A rapid second tap starts from the currently painted shape and colours.
    _fromBounds = _visualBounds;
    _fromWeights = _weights;
    _fromAccent = _accent;
    _fromNeutral = _neutral;
    _fromSurface = _surface;
    _toBounds = bounds;
    _toAccent = colors.primary;
    _toNeutral = colors.onSurfaceVariant;
    _toSurface = colors.surface;
    _target = selected;
    if (_reduced) {
      _motion.stop();
      _motion.value = 1;
    } else {
      _motion.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final design = MellonThemeStyle.of(context);
    final glass = design.enabled && !MediaQuery.highContrastOf(context);
    final indices = _indices;
    final total = indices.fold<int>(
      0,
      (sum, index) => sum + (index == 1 ? 2 : 1),
    );
    final labelStyle = theme.textTheme.labelSmall!.copyWith(
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );
    return RepaintBoundary(
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = math.max(0.0, constraints.maxWidth - 12);
            var labelHeight = 0.0;
            for (final index in indices) {
              final width = trackWidth * (index == 1 ? 2 : 1) / total;
              final measure = TextPainter(
                text: TextSpan(
                  text: ClubNavigationBar.destinations[index].label,
                  style: labelStyle,
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(maxWidth: math.max(1.0, width - 12));
              labelHeight = math.max(
                labelHeight,
                measure.height.ceilToDouble(),
              );
              measure.dispose();
            }
            // Same measured label space in every item: icons and height stay put.
            final height = 26.0 + 4.0 + labelHeight + 16.0;
            return AnimatedBuilder(
              animation: _motion,
              builder: (context, child) {
                final rect = _visualBounds;
                final weights = _weights;
                final accent = _accent;
                final dark = theme.brightness == Brightness.dark;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.shadow.withValues(
                          alpha: dark ? .12 : .04,
                        ),
                        blurRadius: 8,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Material(
                    key: const ValueKey('floating-navigation-surface'),
                    color: _surface.withValues(
                      alpha: glass ? (design.luminous ? .78 : .56) : 1,
                    ),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: dark ? .26 : .70),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: SizedBox(
                        height: height,
                        child: Stack(
                          children: [
                            Positioned(
                              left: rect.left * trackWidth + 2,
                              right: (1 - rect.right) * trackWidth + 2,
                              top: 0,
                              bottom: 0,
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  key: const ValueKey(
                                    'navigation-active-capsule',
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: glass
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Colors.white.withValues(
                                                alpha: dark ? .12 : .92,
                                              ),
                                              accent.withValues(
                                                alpha: dark ? .35 : .18,
                                              ),
                                              Colors.white.withValues(
                                                alpha: dark ? .14 : .7,
                                              ),
                                            ],
                                          )
                                        : null,
                                    boxShadow: glass
                                        ? [
                                            BoxShadow(
                                              color: accent.withValues(
                                                alpha: .20,
                                              ),
                                              blurRadius: 8,
                                            ),
                                            BoxShadow(
                                              color: Colors.white.withValues(
                                                alpha: .55,
                                              ),
                                              blurRadius: 3,
                                            ),
                                          ]
                                        : null,
                                    color: glass
                                        ? null
                                        : Color.alphaBlend(
                                            accent.withValues(
                                              alpha: dark ? .28 : .16,
                                            ),
                                            _surface.withValues(alpha: 1),
                                          ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: dark ? .30 : .78,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final index in indices)
                                  Expanded(
                                    flex: index == 1 ? 2 : 1,
                                    child: Semantics(
                                      selected: _target == index,
                                      button: true,
                                      label: ClubNavigationBar
                                          .destinations[index]
                                          .label,
                                      child: ExcludeSemantics(
                                        child: _NavigationButton(
                                          key: ValueKey(
                                            'navigation-button-$index',
                                          ),
                                          index: index,
                                          color: Color.lerp(
                                            _neutral,
                                            accent,
                                            weights[index],
                                          )!,
                                          labelStyle: labelStyle,
                                          labelHeight: labelHeight,
                                          reducedMotion: _reduced,
                                          onTap: () => widget.onSelected(index),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NavigationButton extends StatefulWidget {
  const _NavigationButton({
    required this.index,
    required this.color,
    required this.labelStyle,
    required this.labelHeight,
    required this.reducedMotion,
    required this.onTap,
    super.key,
  });
  final int index;
  final Color color;
  final TextStyle labelStyle;
  final double labelHeight;
  final bool reducedMotion;
  final VoidCallback onTap;

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton>
    with SingleTickerProviderStateMixin {
  late final _iconMotion = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds: widget.index == 0
          ? 900
          : widget.index == 1
          ? 460
          : 700,
    ),
    value: 1,
  );

  @override
  void didUpdateWidget(covariant _NavigationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion && _iconMotion.isAnimating) {
      _iconMotion.stop();
      _iconMotion.value = 1;
    }
  }

  @override
  void dispose() {
    _iconMotion.dispose();
    super.dispose();
  }

  void _tap() {
    if (!widget.reducedMotion && !_iconMotion.isAnimating) {
      _iconMotion.forward(from: 0);
    }
    // Navigation is synchronous with the tap; it never awaits the animation.
    widget.onTap();
  }

  Widget _icon(IconData icon) => RepaintBoundary(
    child: SizedBox(
      width: 26,
      height: 26,
      child: AnimatedBuilder(
        animation: _iconMotion,
        child: Icon(icon, size: 26, color: widget.color),
        builder: (context, child) {
          final t = widget.reducedMotion ? 1.0 : _iconMotion.value;
          final eased = Curves.easeInOutCubic.transform(t);
          if (widget.index == 0) {
            // Repeated frames roll within fixed bounds like a film strip.
            return ClipRect(
              key: const ValueKey('navigation-film-icon'),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final frame in [0, 1])
                    Positioned(
                      left: 0,
                      top: (frame - eased) * 26,
                      width: 26,
                      height: 26,
                      child: child!,
                    ),
                ],
              ),
            );
          }
          if (widget.index == 1) {
            final lift = t == 0 || t == 1 ? 0.0 : math.sin(math.pi * eased);
            return Transform.translate(
              key: const ValueKey('navigation-club-icon'),
              offset: Offset(0, -2.5 * lift),
              child: Transform.scale(scale: 1 + .10 * lift, child: child),
            );
          }
          return Transform.rotate(
            key: const ValueKey('navigation-map-icon'),
            angle: 2 * math.pi * eased,
            child: child,
          );
        },
      ),
    ),
  );
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final destination = ClubNavigationBar.destinations[widget.index];
    return InkWell(
      key: ValueKey('main-navigation-${widget.index}'),
      borderRadius: BorderRadius.circular(999),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: widget.color.withValues(alpha: .035),
      focusColor: widget.color.withValues(alpha: .08),
      onHighlightChanged: (value) {
        if (_pressed != value) setState(() => _pressed = value);
      },
      onTap: _tap,
      child: AnimatedScale(
        scale: _pressed && !widget.reducedMotion ? .97 : 1,
        duration: widget.reducedMotion
            ? Duration.zero
            : const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _icon(destination.icon),
              const SizedBox(height: 4),
              SizedBox(
                height: widget.labelHeight,
                child: Center(
                  child: Text(
                    destination.label,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    style: widget.labelStyle.copyWith(color: widget.color),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
