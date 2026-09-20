import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const clubPhotoAspect = 1.0;

Rect clubCropRect(Size image, Offset center, double zoom) {
  final width =
      math.min(image.width, image.height * clubPhotoAspect) / zoom.clamp(1, 5);
  final height = width / clubPhotoAspect;
  return Rect.fromLTWH(
    (center.dx - width / 2)
        .clamp(0, math.max(0, image.width - width))
        .toDouble(),
    (center.dy - height / 2)
        .clamp(0, math.max(0, image.height - height))
        .toDouble(),
    width,
    height,
  );
}

Future<ui.Image> decodeClubPhoto(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  // Encoded ImageDescriptor.width/height throw UnsupportedError on the web.
  // This API supplies the intrinsic size on every platform and owns the buffer.
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (width, height) {
      final scale = math.min(1.0, 2560 / math.max(width, height));
      return ui.TargetImageSize(
        width: math.max(1, (width * scale).round()),
        height: math.max(1, (height * scale).round()),
      );
    },
  );
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> encodeClubCrop(ui.Image image, Rect crop) async {
  // Same source rectangle in the editor and the exported photograph.
  const size = Size(384, 384);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawImageRect(
    image,
    crop,
    Offset.zero & size,
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  ui.Image? rendered;
  try {
    rendered = await picture.toImage(size.width.toInt(), size.height.toInt());
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Не удалось подготовить фото.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    rendered?.dispose();
    picture.dispose();
  }
}

class ClubCropPainter extends CustomPainter {
  const ClubCropPainter(this.image, this.crop, {this.grid = false});
  final ui.Image image;
  final Rect crop;
  final bool grid;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawImageRect(
      image,
      crop,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (grid) {
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: .4)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(
          Offset(size.width * i / 3, 0),
          Offset(size.width * i / 3, size.height),
          paint,
        );
        canvas.drawLine(
          Offset(0, size.height * i / 3),
          Offset(size.width, size.height * i / 3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(ClubCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.crop != crop ||
      oldDelegate.grid != grid;
}
