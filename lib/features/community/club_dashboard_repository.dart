import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../auth/application/auth_providers.dart';
import 'club_photo_cache.dart';
import 'club_photo_repository.dart';
import 'community_repository.dart';

final clubDashboardProvider = FutureProvider.autoDispose
    .family<JsonRow, String>((ref, club) async {
      final actor = ref.watch(
        authUserProvider.select((value) => value.asData?.value?.id),
      );
      // Keep checking club capabilities even if global access is unchanged.
      // An explicit refresh retains the current content while the RPC runs.
      ref.listen(accountAccessProvider, (_, next) {
        if (!next.isLoading && next.asData != null) ref.invalidateSelf();
      });
      if (actor == null) throw StateError('Войдите в аккаунт.');
      final repository = ref.watch(communityRepositoryProvider);
      final data = Map<String, dynamic>.from(
        await repository.call('club_publication_dashboard', {'p_youth': club})
            as Map<String, dynamic>,
      );
      if (ref.mounted && repository.runtimeType == CommunityRepository) {
        final path =
            (data['club'] as Map<String, dynamic>?)?['photo_path'] as String?;
        if (path != null) {
          final photos = ref.read(clubPhotoRepositoryProvider);
          ref
              .read(clubPhotoCacheProvider)
              .prefetch(path, () => photos.download(path), priority: 3);
        }
      }
      return data;
    }, retry: (_, error) => null);

List<JsonRow> dashboardRows(JsonRow data, String key) =>
    (data[key] as List<dynamic>? ?? [])
        .map((row) => Map<String, dynamic>.from(row as Map<String, dynamic>))
        .toList();
