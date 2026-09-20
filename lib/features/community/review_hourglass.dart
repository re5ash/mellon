import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Decorative sand flow followed by a slow turn; it is not a countdown.
class ReviewHourglass extends StatefulWidget {
  const ReviewHourglass({required this.color, super.key});
  final Color color;

  @override
  State<ReviewHourglass> createState() => _ReviewHourglassState();
}

class _ReviewHourglassState extends State<ReviewHourglass>
    with SingleTickerProviderStateMixin {
  late final _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5600),
    value: .16,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _progress.stop();
    } else if (!_progress.isAnimating) {
      _progress.repeat();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('review-hourglass-paint'),
        size: const Size(26, 32),
        painter: ReviewHourglassPainter(_progress, widget.color),
      ),
    ),
  );
}

class ReviewHourglassPainter extends CustomPainter {
  ReviewHourglassPainter(this.progress, this.color) : super(repaint: progress);
  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = progress.value;
    final filled = (phase / .78).clamp(0.0, 1.0).toDouble();
    final turn = ((phase - .78) / .22).clamp(0.0, 1.0).toDouble();
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.width / 32, size.height / 36);
    canvas.rotate(math.pi * Curves.easeInOutCubic.transform(turn));
    final frame = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(-8, -12), const Offset(8, -12), frame);
    canvas.drawLine(const Offset(-8, 12), const Offset(8, 12), frame);
    final glass = Path()
      ..moveTo(-6.5, -10)
      ..quadraticBezierTo(-6.5, -4.5, -1, 0)
      ..quadraticBezierTo(-6.5, 4.5, -6.5, 10)
      ..moveTo(6.5, -10)
      ..quadraticBezierTo(6.5, -4.5, 1, 0)
      ..quadraticBezierTo(6.5, 4.5, 6.5, 10);
    canvas.drawPath(glass, frame);
    final sand = Paint()..color = color.withValues(alpha: .65);
    final top = 9 * math.sqrt(1 - filled);
    final upper = Path()
      ..moveTo(-top * 5 / 9, -top)
      ..lineTo(top * 5 / 9, -top)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(upper, sand);
    final bottom = 9 * math.sqrt(1 - filled);
    final lower = Path()
      ..moveTo(-5, 9)
      ..lineTo(5, 9)
      ..lineTo(bottom * 5 / 9, bottom)
      ..lineTo(-bottom * 5 / 9, bottom)
      ..close();
    canvas.drawPath(lower, sand);
    if (phase < .78 && bottom > .5) {
      canvas.drawLine(
        const Offset(0, 0),
        Offset(0, bottom),
        Paint()
          ..color = color.withValues(alpha: .45)
          ..strokeWidth = .8,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReviewHourglassPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
