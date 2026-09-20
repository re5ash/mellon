import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/community/club_photo.dart';
import 'package:moy_prihod/features/community/club_photo_crop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'crop stays within portrait and landscape photos at every zoom and edge',
    () {
      for (final size in [
        const Size(300, 2000),
        const Size(2400, 600),
        const Size(1, 1),
      ]) {
        for (final zoom in [1.0, 1.5, 3.0, 5.0]) {
          for (final center in [
            Offset.zero,
            Offset(size.width, size.height),
            const Offset(-100, 99999),
          ]) {
            final crop = clubCropRect(size, center, zoom);
            expect(crop.left, greaterThanOrEqualTo(0));
            expect(crop.top, greaterThanOrEqualTo(0));
            expect(crop.right, lessThanOrEqualTo(size.width + .0001));
            expect(crop.bottom, lessThanOrEqualTo(size.height + .0001));
            expect(crop.width / crop.height, closeTo(clubPhotoAspect, .0001));
          }
        }
      }
    },
  );
  test(
    'export normalizes dimensions to the same crop used in preview',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final original = await picture.toImage(400, 900);
      try {
        final bytes = await encodeClubCrop(
          original,
          clubCropRect(const Size(400, 900), const Offset(200, 450), 2),
        );
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final decoded = await decodeClubPhoto(bytes);
        try {
          expect(decoded.width, 384);
          expect(decoded.height, 384);
        } finally {
          decoded.dispose();
        }
      } finally {
        original.dispose();
        picture.dispose();
      }
    },
  );
  Future<void> mount(WidgetTester tester, VoidCallback? edit) =>
      tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(width: 310, child: ClubPhoto(onEdit: edit)),
              ),
            ),
          ),
        ),
      );
  testWidgets('participant photograph has no pencil or edit interaction', (
    tester,
  ) async {
    await mount(tester, null);
    await tester.tap(find.byKey(const ValueKey('club-photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-club-photo')), findsNothing);
  });
  testWidgets(
    'touch reveals pencil first; editor opens only on second target',
    (tester) async {
      var edits = 0;
      await mount(tester, () => edits++);
      final pencil = find.byKey(const ValueKey('edit-club-photo'));
      expect(pencil.hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('club-photo')));
      await tester.pumpAndSettle();
      expect(edits, 0);
      expect(pencil.hitTestable(), findsOneWidget);
      await tester.tap(pencil);
      expect(edits, 1);
      await mount(tester, null);
      await tester.pumpAndSettle();
      expect(pencil, findsNothing);
    },
  );
  testWidgets('desktop hover does not reveal controls before a click', (
    tester,
  ) async {
    await mount(tester, () {});
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: const Offset(1, 1));
    await pointer.moveTo(
      tester.getCenter(find.byKey(const ValueKey('club-photo'))),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('edit-club-photo')).hitTestable(),
      findsNothing,
    );
    await pointer.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('edit-club-photo')).hitTestable(),
      findsNothing,
    );
    await pointer.removePointer();
  });
}
