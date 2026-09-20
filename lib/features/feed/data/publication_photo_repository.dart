import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../core/images/supabase_photo_source.dart';
import '../../auth/application/auth_providers.dart';
import '../../community/club_photo_crop.dart';

final publicationPhotoProcessorProvider =
    Provider<Future<Uint8List> Function(Uint8List)>(
      (ref) => preparePublicationPhoto,
    );
final publicationPhotoRepositoryProvider = Provider<PublicationPhotoRepository>(
  (ref) => PublicationPhotoRepository(ref.watch(backendProvider)),
);
final publicationPhotoUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, path) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(publicationPhotoRepositoryProvider).url(path);
    }, retry: (_, error) => null);

class PublicationPhotoRepository {
  const PublicationPhotoRepository(this.client);
  final SupabaseClient client;
  Future<String> url(String path) =>
      client.storage.from('event-photos').createSignedUrl(path, 3600);

  Future<Uint8List> download(String path) =>
      supabasePhotoSource(client).download('event-photos', path, edge: 640);

  Future<void> upload(String path, Uint8List bytes, String actor) async {
    if (client.auth.currentUser?.id != actor)
      throw StateError('Аккаунт изменился.');
    try {
      await client.storage
          .from('event-photos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      if (error.statusCode != '409') rethrow;
    }
    if (client.auth.currentUser?.id != actor)
      throw StateError('Аккаунт изменился.');
  }
}

// A bounded, normalized image. Gradients are rendered by the card, not baked in.
Future<Uint8List> preparePublicationPhoto(Uint8List bytes) async {
  final source = await decodeClubPhoto(bytes);
  ui.Image? scaled;
  ui.Picture? picture;
  try {
    final ratio = math.min(1.0, 640 / math.max(source.width, source.height));
    final width = math.max(1, (source.width * ratio).round());
    final height = math.max(1, (source.height * ratio).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    canvas.drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    scaled = await picture.toImage(width, height);
    final data = await scaled.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || data.lengthInBytes > 8 * 1024 * 1024) {
      throw StateError(
        'Не удалось подготовить фото. Выберите другое изображение.',
      );
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    scaled?.dispose();
    picture?.dispose();
    source.dispose();
  }
}
