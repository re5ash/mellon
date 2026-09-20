import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_information_editor.dart';
import 'package:moy_prihod/features/community/club_photo_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/feed/data/publication_photo_repository.dart';

import 'publication_editor_test.dart' show PublicationRecorder;

class FixedPhotoPicker extends ClubPhotoPicker {
  const FixedPhotoPicker(this.bytes);
  final Uint8List bytes;
  @override
  Future<Uint8List?> pick() async => bytes;
}

class RecordingPhotoUpload implements PublicationPhotoRepository {
  final paths = <String>[];
  final images = <Uint8List>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> upload(String path, Uint8List bytes, String actor) async {
    expect(actor, 'actor');
    paths.add(path);
    images.add(bytes);
  }
}

void main() {
  testWidgets(
    'ordinary photo is normalized, previewed, uploaded and attached to the saved event',
    (tester) async {
      final bytes = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(
          recorder,
        ).drawColor(const Color(0xff3388aa), ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(40, 20);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final result = await preparePublicationPhoto(
          data!.buffer.asUint8List(),
        );
        final codec = await ui.instantiateImageCodec(result);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 40);
        expect(frame.image.height, 20);
        frame.image.dispose();
        codec.dispose();
        return result;
      }))!;
      final repo = PublicationRecorder();
      final photos = RecordingPhotoUpload();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
            clubPhotoPickerProvider.overrideWithValue(FixedPhotoPicker(bytes)),
            publicationPhotoRepositoryProvider.overrideWithValue(photos),
            publicationPhotoProcessorProvider.overrideWithValue(
              (bytes) async => bytes,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => const ClubInformationEditor(
                      club: 'club',
                      actor: 'actor',
                      kind: 'events',
                    ),
                  ),
                  child: const Text('Открыть'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('club-information-title')),
        'Событие с фото',
      );
      final pick = find.byKey(const ValueKey('publication-pick-photo'));
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      expect(find.text('Убрать фото'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('save-club-information')));
      await tester.pumpAndSettle();
      expect(photos.paths, hasLength(1));
      expect(photos.images.single.length, greaterThan(0));
      expect(
        (repo.calls.single['p_data'] as JsonRow)['photo_path'],
        photos.paths.single,
      );
      expect(
        photos.paths.single,
        startsWith('club/${repo.calls.single['p_id']}/'),
      );
    },
  );
}
