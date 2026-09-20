import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design_system/mellon_theme.dart';
import 'chat_appearance.dart';

/// One renderer is shared by the list, header and selection preview.
class ChatIconBadge extends StatefulWidget {
  const ChatIconBadge({
    required this.iconKey,
    this.title = '',
    this.description = '',
    this.seed = '',
    this.size = 46,
    this.unread = 0,
    this.motionToken = 0,
    this.animateOnMount = false,
    super.key,
  });
  final String iconKey, title, description, seed;
  final double size;
  final int unread, motionToken;
  final bool animateOnMount;
  @override
  State<ChatIconBadge> createState() => _ChatIconBadgeState();
}

class _ChatIconBadgeState extends State<ChatIconBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  static DateTime? _lastUnreadMotion;
  @override
  void initState() {
    super.initState();
    if (widget.animateOnMount)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _play();
      });
  }

  void _play({bool unread = false}) {
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled ||
        Scrollable.maybeOf(context)?.position.isScrollingNotifier.value == true)
      return;
    if (unread) {
      final now = DateTime.now();
      if (_lastUnreadMotion != null &&
          now.difference(_lastUnreadMotion!).inMilliseconds < 550)
        return;
      _lastUnreadMotion = now;
    }
    _motion.forward(from: 0);
  }

  @override
  void didUpdateWidget(ChatIconBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.motionToken != oldWidget.motionToken)
      _play();
    else if (widget.unread > oldWidget.unread)
      _play(unread: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _motion.value = 1;
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    final style = ChatAppearance.resolve(
      widget.iconKey,
      title: widget.title,
      description: widget.description,
      seed: widget.seed,
    );
    final glyph = style.key == 'church_5'
        ? CustomPaint(
            size: Size.square(widget.size * .57),
            painter: const _OrthodoxCross(),
          )
        : Icon(style.icon, color: Colors.white, size: widget.size * .55);
    final badge = Semantics(
      label: style.label,
      child: RepaintBoundary(
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              design.enabled ? design.iconRadius : widget.size * .32,
            ),
            boxShadow: design.enabled
                ? [
                    BoxShadow(
                      color: style.color.withValues(alpha: .16),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  style.color,
                  Colors.white,
                  design.enabled ? .40 : .23,
                )!,
                style.color,
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: design.enabled ? .82 : .24),
            ),
          ),
          child: Center(child: glyph),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _motion,
      child: badge,
      builder: (context, child) {
        final pulse = math.sin(_motion.value * math.pi);
        return Transform.translate(
          offset: Offset(0, -2 * pulse),
          child: Transform.rotate(
            angle: style.variant == 2
                ? .07 * math.sin(_motion.value * math.pi * 2)
                : 0,
            child: Transform.scale(scale: 1 + .08 * pulse, child: child),
          ),
        );
      },
    );
  }
}

class _OrthodoxCross extends CustomPainter {
  const _OrthodoxCross();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .085
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * .5, size.height * .05),
      Offset(size.width * .5, size.height * .95),
      p,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .22),
      Offset(size.width * .66, size.height * .22),
      p,
    );
    canvas.drawLine(
      Offset(size.width * .15, size.height * .4),
      Offset(size.width * .85, size.height * .4),
      p,
    );
    canvas.drawLine(
      Offset(size.width * .32, size.height * .65),
      Offset(size.width * .68, size.height * .79),
      p,
    );
  }

  @override
  bool shouldRepaint(_OrthodoxCross oldDelegate) => false;
}
