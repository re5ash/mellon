import 'package:flutter/material.dart';

// 32 seconds / 0.70: approximately 30% less travel speed.
const skyCloudTravelDuration = Duration(milliseconds: 45714);

/// Each cloud wraps only after it has travelled entirely beyond the scene.
Offset skyCloudPosition(double progress, Size size, int index) => Offset(
  size.width * (-.25 + ((progress + index * .25) % 1) * 1.5),
  size.height * const [.14, .27, .20, .32][index],
);

class SkyCloudsPainter extends CustomPainter {
  SkyCloudsPainter(this.drift) : super(repaint: drift);
  final Animation<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    const widths = [.17, .12, .15, .18];
    for (var index = 0; index < widths.length; index++) {
      final width = size.width * widths[index];
      final height = width * .34;
      final position = skyCloudPosition(drift.value, size, index);
      final origin = Offset(position.dx - width / 2, position.dy);
      final path = Path()
        ..moveTo(0, height * .74)
        ..cubicTo(
          -width * .03,
          height * .38,
          width * .11,
          height * .20,
          width * .24,
          height * .40,
        )
        ..cubicTo(
          width * .29,
          -height * .08,
          width * .55,
          -height * .07,
          width * .62,
          height * .28,
        )
        ..cubicTo(
          width * .78,
          height * .09,
          width * .91,
          height * .31,
          width * .88,
          height * .47,
        )
        ..cubicTo(
          width * 1.05,
          height * .45,
          width * 1.07,
          height * .87,
          width * .91,
          height * .91,
        )
        ..cubicTo(
          width * .68,
          height * 1.07,
          width * .22,
          height * 1.02,
          width * .08,
          height * .94,
        )
        ..quadraticBezierTo(0, height * .92, 0, height * .74)
        ..close();
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF5FFFFFF), Color(0xD9FFFFFF), Color(0x68CDE2EF)],
          stops: [0, .68, 1],
        ).createShader(Rect.fromLTWH(origin.dx, origin.dy, width, height))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .0018);
      canvas.drawPath(path.shift(origin), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SkyCloudsPainter oldDelegate) =>
      oldDelegate.drift != drift;
}
