import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../core/pagination/cursor_page.dart';
import '../../auth/application/auth_providers.dart';
import '../../events/application/events_providers.dart';
import '../data/publication_photo_cache.dart';
import '../data/publication_photo_repository.dart';
import '../data/supabase_feed_repository.dart';
import '../domain/feed_repository.dart';
import '../domain/post.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => SupabaseFeedRepository(ref.watch(backendProvider)),
);
final feedPageProvider = FutureProvider.autoDispose
    .family<CursorPage<Post>, ({String? parishId, PageCursor? before})>((
      ref,
      request,
    ) async {
      ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
      final repository = ref.watch(feedRepositoryProvider);
      final page = await repository.page(
        parishId: request.parishId,
        before: request.before,
      );
      if (ref.mounted && repository is SupabaseFeedRepository) {
        final cache = ref.read(publicationPhotoCacheProvider);
        final photos = ref.read(publicationPhotoRepositoryProvider);
        for (final post in page.items.take(2)) {
          final path = post.photoPath;
          if (path != null)
            cache.prefetch(path, () => photos.download(path), priority: 3);
        }
      }
      return page;
    });

// One subscription shared by visible feed pages. Polling covers missed deletes,
// revoked read access and reconnects; private rows never enter the general view.
final feedChangesProvider = Provider.autoDispose<void>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  final repository = ref.watch(feedRepositoryProvider);
  if (repository is! SupabaseFeedRepository) return;
  final client = repository.client;
  Timer? debounce;
  var disposed = false;
  void refresh() {
    if (disposed) return;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 150), () {
      ref.invalidate(feedPageProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(myParishEventsProvider);
    });
  }

  final channel = client.channel('mellon-feed-${identityHashCode(ref)}');
  for (final table in ['posts', 'events', 'feed_publication_changes']) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      callback: (_) => refresh(),
    );
  }
  channel.subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) refresh();
  });
  final timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
  ref.onDispose(() {
    disposed = true;
    timer.cancel();
    debounce?.cancel();
    unawaited(client.removeChannel(channel));
  });
});
