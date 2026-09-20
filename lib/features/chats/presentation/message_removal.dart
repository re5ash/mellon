import 'package:flutter/material.dart';

/// Retains the visible bubble only for its exit animation. Rows which were
/// already deleted when loaded never display a bubble or a placeholder.
class MessageRemoval extends StatefulWidget {
  const MessageRemoval({
    required this.removed,
    required this.onRemoved,
    required this.child,
    super.key,
  });

  final bool removed;
  final VoidCallback onRemoved;
  final Widget child;

  @override
  State<MessageRemoval> createState() => _MessageRemovalState();
}

class _MessageRemovalState extends State<MessageRemoval>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;
  Widget? _previousBubble;
  bool _reduceMotion = false, _notified = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 280),
          value: widget.removed ? 0 : 1,
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) _notifyRemoved();
        });
    _progress = _controller.drive(CurveTween(curve: Curves.easeInOutCubic));
    if (widget.removed) _notifyRemoved();
  }

  void _notifyRemoved() {
    if (_notified) return;
    _notified = true;
    // A cached deleted row can be mounted during its parent's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _previousBubble = null);
      widget.onRemoved();
    });
  }

  void _finishImmediately() {
    _controller.value = 0;
    // Jumping straight from the initial value to zero can leave the last
    // reported status unchanged. Complete removal without waiting for a tick
    // or a status notification; _notifyRemoved guards against duplicates.
    _notifyRemoved();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion && widget.removed) _finishImmediately();
  }

  @override
  void didUpdateWidget(covariant MessageRemoval oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removed && !oldWidget.removed) {
      _previousBubble = oldWidget.child;
      if (_reduceMotion) {
        _finishImmediately();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isDismissed) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: widget.removed,
      child: ExcludeSemantics(
        excluding: widget.removed,
        child: SizeTransition(
          sizeFactor: _progress,
          child: FadeTransition(
            opacity: _progress,
            child: widget.removed
                ? _previousBubble ?? const SizedBox.shrink()
                : widget.child,
          ),
        ),
      ),
    );
  }
}
