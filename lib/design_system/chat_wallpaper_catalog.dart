import 'package:flutter/material.dart';

import 'appearance_settings.dart';

class ChatWallpaperDesign {
  const ChatWallpaperDesign(
    this.label,
    this.family,
    this.top,
    this.bottom,
    this.ink,
    this.dark,
  );
  final String label;
  final int family;
  final Color top, bottom, ink;
  final bool dark;
}

abstract final class ChatWallpapers {
  static const designs = <ChatWallpaper, ChatWallpaperDesign>{
    ChatWallpaper.templesDawn: ChatWallpaperDesign(
      'Храмы · Рассвет',
      0,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.templesLinen: ChatWallpaperDesign(
      'Храмы · Лён',
      0,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.templesNight: ChatWallpaperDesign(
      'Храмы · Ночь',
      0,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.templesDusk: ChatWallpaperDesign(
      'Храмы · Сумерки',
      0,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
    ChatWallpaper.domesDawn: ChatWallpaperDesign(
      'Купола · Рассвет',
      1,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.domesLinen: ChatWallpaperDesign(
      'Купола · Лён',
      1,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.domesNight: ChatWallpaperDesign(
      'Купола · Ночь',
      1,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.domesDusk: ChatWallpaperDesign(
      'Купола · Сумерки',
      1,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
    ChatWallpaper.crossesDawn: ChatWallpaperDesign(
      'Кресты · Рассвет',
      2,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.crossesLinen: ChatWallpaperDesign(
      'Кресты · Лён',
      2,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.crossesNight: ChatWallpaperDesign(
      'Кресты · Ночь',
      2,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.crossesDusk: ChatWallpaperDesign(
      'Кресты · Сумерки',
      2,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
    ChatWallpaper.candlesDawn: ChatWallpaperDesign(
      'Свечи · Рассвет',
      3,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.candlesLinen: ChatWallpaperDesign(
      'Свечи · Лён',
      3,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.candlesNight: ChatWallpaperDesign(
      'Свечи · Ночь',
      3,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.candlesDusk: ChatWallpaperDesign(
      'Свечи · Сумерки',
      3,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
    ChatWallpaper.ornamentsDawn: ChatWallpaperDesign(
      'Орнаменты · Рассвет',
      4,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.ornamentsLinen: ChatWallpaperDesign(
      'Орнаменты · Лён',
      4,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.ornamentsNight: ChatWallpaperDesign(
      'Орнаменты · Ночь',
      4,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.ornamentsDusk: ChatWallpaperDesign(
      'Орнаменты · Сумерки',
      4,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
    ChatWallpaper.quietDawn: ChatWallpaperDesign(
      'Тихие узоры · Рассвет',
      5,
      Color(0xFFEDF3F7),
      Color(0xFFF8FAFB),
      Color(0xFF6789A4),
      false,
    ),
    ChatWallpaper.quietLinen: ChatWallpaperDesign(
      'Тихие узоры · Лён',
      5,
      Color(0xFFF5F0E5),
      Color(0xFFFCF9F2),
      Color(0xFFAC9061),
      false,
    ),
    ChatWallpaper.quietNight: ChatWallpaperDesign(
      'Тихие узоры · Ночь',
      5,
      Color(0xFF162638),
      Color(0xFF20354A),
      Color(0xFF91AEC9),
      true,
    ),
    ChatWallpaper.quietDusk: ChatWallpaperDesign(
      'Тихие узоры · Сумерки',
      5,
      Color(0xFF292537),
      Color(0xFF363047),
      Color(0xFFB4A1CC),
      true,
    ),
  };
}

/// Static vector tiles: no image download, animation, blur or scroll work.
class OrthodoxWallpaperPainter extends CustomPainter {
  const OrthodoxWallpaperPainter(this.design);
  final ChatWallpaperDesign design;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = design.ink.withValues(alpha: design.dark ? .23 : .2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var row = 0; row * 138.0 < size.height + 60; row++) {
      for (double x = row.isEven ? 36 : -32; x < size.width + 60; x += 144) {
        canvas.save();
        canvas.translate(x, row * 138.0 + 48);
        switch (design.family) {
          case 0:
            _temple(canvas, pen);
            break;
          case 1:
            _dome(canvas, pen, 1.0);
            _cross(canvas, pen, const Offset(0, -33), .45);
            break;
          case 2:
            _cross(canvas, pen, Offset.zero, 1);
            canvas.drawCircle(Offset.zero, 32, pen);
            break;
          case 3:
            _candle(canvas, pen);
            break;
          case 4:
            _ornament(canvas, pen);
            break;
          default:
            _quiet(canvas, pen);
            break;
        }
        canvas.restore();
      }
    }
  }

  void _cross(Canvas c, Paint p, Offset origin, double scale) {
    c.save();
    c.translate(origin.dx, origin.dy);
    c.scale(scale);
    c.drawPath(
      Path()
        ..moveTo(0, -27)
        ..lineTo(0, 29)
        ..moveTo(-8, -18)
        ..lineTo(8, -18)
        ..moveTo(-17, -7)
        ..lineTo(17, -7)
        ..moveTo(-10, 13)
        ..lineTo(10, 21),
      p,
    );
    c.restore();
  }

  void _dome(Canvas c, Paint p, double scale) {
    c.save();
    c.scale(scale);
    c.drawPath(
      Path()
        ..moveTo(-19, 15)
        ..cubicTo(-34, -5, -3, -16, 0, -29)
        ..cubicTo(3, -16, 34, -5, 19, 15)
        ..close()
        ..moveTo(-17, 15)
        ..lineTo(-17, 23)
        ..lineTo(17, 23)
        ..lineTo(17, 15),
      p,
    );
    c.restore();
  }

  void _temple(Canvas c, Paint p) {
    c.save();
    c.translate(0, -12);
    _dome(c, p, .62);
    _cross(c, p, const Offset(0, -24), .3);
    c.restore();
    c.drawPath(
      Path()
        ..moveTo(-15, 2)
        ..lineTo(-15, 31)
        ..lineTo(15, 31)
        ..lineTo(15, 2)
        ..moveTo(-15, 11)
        ..lineTo(-30, 11)
        ..lineTo(-30, 31)
        ..lineTo(30, 31)
        ..lineTo(30, 11)
        ..lineTo(15, 11)
        ..moveTo(-6, 31)
        ..lineTo(-6, 22)
        ..quadraticBezierTo(0, 12, 6, 22)
        ..lineTo(6, 31),
      p,
    );
  }

  void _candle(Canvas c, Paint p) {
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, -6, 14, 36),
        const Radius.circular(2),
      ),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(0, -9)
        ..cubicTo(-17, -15, 0, -28, 1, -34)
        ..cubicTo(2, -26, 15, -17, 0, -9)
        ..moveTo(-21, 31)
        ..lineTo(21, 31)
        ..moveTo(-13, 36)
        ..lineTo(13, 36),
      p,
    );
    c.drawLine(const Offset(-19, -18), const Offset(-25, -21), p);
    c.drawLine(const Offset(19, -18), const Offset(25, -21), p);
  }

  void _ornament(Canvas c, Paint p) {
    for (var n = 0; n < 4; n++) {
      c.save();
      c.rotate(n * 1.57079632679);
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-30, -10, -17, -37, 0, -28)
          ..cubicTo(17, -37, 30, -10, 0, 0),
        p,
      );
      c.restore();
    }
    c.drawCircle(Offset.zero, 5, p);
  }

  void _quiet(Canvas c, Paint p) {
    c.drawPath(
      Path()
        ..moveTo(-32, 18)
        ..quadraticBezierTo(0, -4, 32, 18)
        ..moveTo(-32, 26)
        ..quadraticBezierTo(0, 4, 32, 26),
      p,
    );
    c.drawArc(
      const Rect.fromLTWH(-19, -28, 38, 38),
      3.14159265359,
      3.14159265359,
      false,
      p,
    );
    for (var i = -1; i <= 1; i++) {
      c.drawCircle(Offset(i * 14.0, -36), 1.4, p);
    }
  }

  @override
  bool shouldRepaint(OrthodoxWallpaperPainter oldDelegate) =>
      oldDelegate.design != design;
}
