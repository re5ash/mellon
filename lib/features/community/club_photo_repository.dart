import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/backend_provider.dart';
import '../../core/images/supabase_photo_source.dart';
import '../auth/application/auth_providers.dart';
import 'community_repository.dart';

final clubPhotoRepositoryProvider = Provider<ClubPhotoRepository>(
  (ref) => SupabaseClubPhotoRepository(ref.watch(backendProvider)),
);
final clubPhotoPickerProvider = Provider<ClubPhotoPicker>(
  (ref) => const ClubPhotoPicker(),
);
final clubPhotoUrlProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  path,
) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  return ref.watch(clubPhotoRepositoryProvider).url(path);
}, retry: (_, error) => null);

abstract interface class ClubPhotoRepository {
  Future<String> url(String path);
  Future<Uint8List> download(String path);
  Future<JsonRow> save({
    required String club,
    required String actor,
    required String path,
    required int revision,
    required Uint8List bytes,
  });
}

class SupabaseClubPhotoRepository implements ClubPhotoRepository {
  const SupabaseClubPhotoRepository(this.client);
  final SupabaseClient client;
  @override
  Future<String> url(String path) =>
      client.storage.from('club-photos').createSignedUrl(path, 3600);
  @override
  Future<Uint8List> download(String path) =>
      supabasePhotoSource(client).download('club-photos', path, edge: 384);
  @override
  Future<JsonRow> save({
    required String club,
    required String actor,
    required String path,
    required int revision,
    required Uint8List bytes,
  }) async {
    if (client.auth.currentUser?.id != actor)
      throw StateError('Аккаунт изменился.');
    try {
      await client.storage
          .from('club-photos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/png',
              upsert: false,
            ),
          );
    } on StorageException catch (error) {
      // Retrying an identical immutable object after a lost upload response.
      if (error.statusCode != '409') rethrow;
    }
    if (client.auth.currentUser?.id != actor)
      throw StateError('Аккаунт изменился.');
    return client.rpc<JsonRow>(
      'set_club_photo',
      params: {
        'p_youth': club,
        'p_path': path,
        'p_revision': revision,
        'p_expected_user': actor,
      },
    );
  }
}

class ClubPhotoPicker {
  const ClubPhotoPicker();
  Future<Uint8List?> pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Фотографии',
          mimeTypes: ['image/*'],
          uniformTypeIdentifiers: ['public.image'],
          extensions: [
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'bmp',
            'heic',
            'heif',
            'avif',
            'tif',
            'tiff',
          ],
        ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 50 * 1024 * 1024)
      throw StateError(
        'Фото слишком большое для обработки. Выберите другое фото.',
      );
    return file.readAsBytes();
  }
}
