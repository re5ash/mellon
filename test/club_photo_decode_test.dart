import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/community/club_photo_crop.dart';

Future<Uint8List> sourcePhoto(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF3494D4), ui.BlendMode.src);
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Could not create the test photo');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Run this file with --platform chrome as well as on the VM. The old decoder
  // passed native tests but failed on web before it produced the first image.
  for (final dimensions in [(320, 180), (3600, 1200), (1200, 3600)]) {
    test('photo decodes and exports on native and web: $dimensions', () async {
      final bytes = await sourcePhoto(dimensions.$1, dimensions.$2);
      final image = await decodeClubPhoto(bytes);
      try {
        expect(image.width, lessThanOrEqualTo(2560));
        expect(image.height, lessThanOrEqualTo(2560));
        expect(
          image.width / image.height,
          closeTo(dimensions.$1 / dimensions.$2, .005),
        );
        if (dimensions.$1 <= 2560 && dimensions.$2 <= 2560) {
          expect(image.width, dimensions.$1);
          expect(image.height, dimensions.$2);
        }
        final size = ui.Size(image.width.toDouble(), image.height.toDouble());
        final cropped = await encodeClubCrop(
          image,
          clubCropRect(size, ui.Offset(size.width / 2, size.height / 2), 1.5),
        );
        final preview = await decodeClubPhoto(cropped);
        try {
          expect(preview.width, 384);
          expect(preview.height, 384);
        } finally {
          preview.dispose();
        }
      } finally {
        image.dispose();
      }
    });
  }
}
