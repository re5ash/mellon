import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'browser_chat_gestures.dart';

/// Only the chat moves. Cupertino still owns back-gesture cancellation,
/// navigator bookkeeping, the draft's lifetime and system back handling.
class MellonChatRoute extends CupertinoPageRoute<void> {
  MellonChatRoute({
    required super.builder,
    required this.reducedMotion,
    super.settings,
  }) : super(allowSnapshotting: false);
  final bool reducedMotion;
  VoidCallback? _releaseBrowserGestures;
  @override
  void install() {
    super.install();
    _releaseBrowserGestures = protectChatBrowserGestures();
  }

  @override
  void dispose() {
    _releaseBrowserGestures?.call();
    super.dispose();
  }

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 340);
  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 280);

  // The directory must remain at its original position, size and scroll offset.
  // In particular do not delegate Cupertino's outgoing parallax to the shell.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

  @override
  DelegatedTransitionBuilder? get delegatedTransition => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final native = super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      RepaintBoundary(
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: child,
        ),
      ),
    );
    if (native is! CupertinoPageTransition) return native;
    final reduced = reducedMotion || MediaQuery.disableAnimationsOf(context);
    // Keep the native transition's gesture detector, replacing only its visual
    // transform. The native gesture remains linear until settling is complete.
    return ClipRect(
      child: AnimatedBuilder(
        animation: animation,
        child: native.child,
        builder: (context, page) {
          final double progress;
          if (popGestureInProgress) {
            progress = animation.value;
          } else if (reduced) {
            progress = 1;
          } else {
            progress = Curves.easeInOutCubic.transform(animation.value);
          }
          return FractionalTranslation(
            key: const ValueKey('mellon-chat-slide'),
            translation: Offset(1 - progress, 0),
            child: page,
          );
        },
      ),
    );
  }
}

class MellonChatScreenPage extends Page<void> {
  const MellonChatScreenPage({
    required this.child,
    required this.reducedMotion,
    super.key,
  });
  final Widget child;
  final bool reducedMotion;
  @override
  Route<void> createRoute(BuildContext context) => MellonChatRoute(
    builder: (_) => child,
    reducedMotion: reducedMotion,
    settings: this,
  );
}
