import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/images/photo_cache.dart';
import 'package:moy_prihod/features/feed/data/publication_photo_cache.dart';
import 'package:moy_prihod/features/feed/data/publication_photo_repository.dart';
import 'package:moy_prihod/features/feed/presentation/publication_photo.dart';

import 'club_photo_loading_test.dart' show pixel;

void main() {
  testWidgets(
    'placeholder, image and a new revision keep identical geometry without flashing the old image',
    (tester) async {
      final cache = PhotoCache();
      addTearDown(cache.dispose);
      final first = Completer<Uint8List>();
      final second = Completer<Uint8List>();
      var path = 'photo-1';
      late StateSetter change;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            publicationPhotoCacheProvider.overrideWithValue(cache),
            publicationPhotoImageProvider(
              'photo-1',
            ).overrideWith((ref) => cache.load('photo-1', () => first.future)),
            publicationPhotoImageProvider(
              'photo-2',
            ).overrideWith((ref) => cache.load('photo-2', () => second.future)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return SizedBox(
                    width: 180,
                    height: 210,
                    child: PublicationPhoto(path: path),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final frame = tester.getRect(find.byType(PublicationPhoto));
      expect(
        find.byKey(const ValueKey('publication-photo-placeholder')),
        findsOneWidget,
      );
      first.complete(pixel);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.getRect(find.byType(PublicationPhoto)), frame);
      change(() => path = 'photo-2');
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(
        find.byKey(const ValueKey('publication-photo-placeholder')),
        findsOneWidget,
      );
      expect(tester.getRect(find.byType(PublicationPhoto)), frame);
      second.complete(pixel);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new publication photos are bounded to 640 pixels without changing aspect ratio',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xff4488aa), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final source = await picture.toImage(1600, 900);
        final data = await source.toByteData(format: ui.ImageByteFormat.png);
        source.dispose();
        picture.dispose();
        final result = await preparePublicationPhoto(
          data!.buffer.asUint8List(),
        );
        final codec = await ui.instantiateImageCodec(result);
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 640);
        expect(image.height, 360);
        image.dispose();
        codec.dispose();
      });
    },
  );
}
