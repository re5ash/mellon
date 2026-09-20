import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/images/photo_cache.dart';
import '../../core/images/photo_store.dart';
import '../../core/images/photo_thumbnail.dart';
import '../auth/application/auth_providers.dart';
import 'club_photo_repository.dart';

final clubPhotoCacheProvider = Provider<ClubPhotoCache>((ref) {
  final actor = ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
  final cache = ClubPhotoCache(
    store: createPhotoStore('club:${actor ?? "guest"}'),
    queue: ref.watch(photoLoadQueueProvider),
    prepare: (bytes) => photoThumbnail(bytes, edge: 384),
    ttl: photoStoreLifetime,
  );
  ref.onDispose(cache.dispose);
  return cache;
});

final clubPhotoImageProvider = FutureProvider.autoDispose
    .family<MemoryImage, String>((ref, path) {
      final repository = ref.watch(clubPhotoRepositoryProvider);
      return ref
          .watch(clubPhotoCacheProvider)
          .load(path, () => repository.download(path), priority: 2);
    }, retry: (_, _) => null);

class ClubPhotoCache extends PhotoCache {
  ClubPhotoCache({
    super.maximumBytes = 8 * 1024 * 1024,
    super.maximumEntries = 8,
    super.ttl = const Duration(minutes: 10),
    super.now,
    super.store,
    super.queue,
    super.prepare,
  });
}

class ClubPhotoSaved {
  const ClubPhotoSaved({required this.path, required this.revision});
  final String path;
  final int revision;
}
