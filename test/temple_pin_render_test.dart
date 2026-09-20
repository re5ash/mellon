import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/map/presentation/temple_pin.dart';

void main() {
  testWidgets(
    'temple photograph fills the drop through its lower section without an oval cutout',
    (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundary,
                child: SizedBox(
                  width: 70,
                  height: 84,
                  child: TemplePin(onTap: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(TemplePin));
      await tester.runAsync(
        () => precacheImage(
          const ResizeImage(
            AssetImage('assets/map/alexander_nevsky.jpg'),
            width: 640,
          ),
          context,
        ),
      );
      await tester.pumpAndSettle();
      final image = await tester.runAsync(
        () =>
            (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 4),
      );
      final data = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final offset = (69 * 4 * image!.width + 35 * 4) * 4;
      expect(data!.getUint8(offset + 3), 255);
      expect([
        data.getUint8(offset),
        data.getUint8(offset + 1),
        data.getUint8(offset + 2),
      ], isNot([255, 255, 255]));
      if (const bool.fromEnvironment('MELLON_CAPTURE_PIN')) {
        await tester.runAsync(() async {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '../temple_pin_fixed.png',
          ).writeAsBytes(png!.buffer.asUint8List());
        });
      }
      image.dispose();
    },
  );
}
