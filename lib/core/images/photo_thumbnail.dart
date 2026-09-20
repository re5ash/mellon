import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Codec work is asynchronous; no large Dart pixel loops run during scrolling.
Future<Uint8List> photoThumbnail(Uint8List bytes, {int edge = 640}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final codec = await ui.instantiateImageCodecWithSize(
    buffer,
    getTargetSize: (w, h) {
      final scale = math.min(1.0, edge / math.max(w, h));
      return ui.TargetImageSize(
        width: math.max(1, (w * scale).round()),
        height: math.max(1, (h * scale).round()),
      );
    },
  );
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
    if (encoded == null) throw StateError('Не удалось подготовить фотографию.');
    return encoded.buffer.asUint8List(
      encoded.offsetInBytes,
      encoded.lengthInBytes,
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
