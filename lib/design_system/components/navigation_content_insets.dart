import 'package:flutter/widgets.dart';

/// Scroll padding, not viewport padding: content may pass behind the bar, but
/// the last item can still be scrolled above the home indicator and controls.
class NavigationContentInsets extends InheritedWidget {
  const NavigationContentInsets({
    required this.bottom,
    required super.child,
    super.key,
  });
  final double bottom;
  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<NavigationContentInsets>()
          ?.bottom ??
      MediaQuery.paddingOf(context).bottom;
  @override
  bool updateShouldNotify(NavigationContentInsets oldWidget) =>
      bottom != oldWidget.bottom;
}
