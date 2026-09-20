import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/images/photo_cache.dart';
import '../../../core/images/photo_store.dart';
import '../../../core/images/photo_thumbnail.dart';
import '../../auth/application/auth_providers.dart';
import 'publication_photo_repository.dart';

final publicationPhotoCacheProvider = Provider<PhotoCache>((ref) {
  final actor = ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
  final cache = PhotoCache(
    store: createPhotoStore('feed:${actor ?? "guest"}'),
    queue: ref.watch(photoLoadQueueProvider),
    prepare: (bytes) => photoThumbnail(bytes),
  );
  ref.onDispose(cache.dispose);
  return cache;
});

final publicationPhotoImageProvider = FutureProvider.autoDispose
    .family<MemoryImage, String>((ref, path) {
      final repository = ref.watch(publicationPhotoRepositoryProvider);
      return ref
          .watch(publicationPhotoCacheProvider)
          .load(path, () => repository.download(path));
    }, retry: (_, _) => null);
