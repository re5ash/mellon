import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/permission_providers.dart';
import '../../../core/backend/backend_provider.dart';
import '../../../core/pagination/cursor_page.dart';
import '../../auth/application/auth_providers.dart';
import '../../feed/application/feed_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../../parishes/application/parish_providers.dart';
import '../data/supabase_admin_repository.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => SupabaseAdminRepository(ref.watch(backendProvider)),
);
final managedParishesProvider = FutureProvider.autoDispose
    .family<ParishBatch, String?>((ref, after) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(adminRepositoryProvider).parishes(after: after);
    });
final managedParishProvider = FutureProvider.autoDispose
    .family<AdminParish?, String>((ref, id) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(adminRepositoryProvider).parish(id);
    });
final adminPostsProvider = FutureProvider.autoDispose
    .family<CursorPage<AdminPost>, AdminListRequest>((ref, request) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(adminRepositoryProvider).posts(request);
    });
final adminPostProvider = FutureProvider.autoDispose
    .family<AdminPost?, AdminPostRequest>((ref, request) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(adminRepositoryProvider).post(request);
    });
final pendingMembershipsProvider = FutureProvider.autoDispose
    .family<CursorPage<PendingMembership>, AdminListRequest>((ref, request) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref.watch(adminRepositoryProvider).requests(request);
    });
final refreshAdminDataProvider = Provider<void Function()>(
  (ref) => () {
    if (!ref.mounted) return;
    ref.invalidate(managedParishesProvider);
    ref.invalidate(managedParishProvider);
    ref.invalidate(adminPostsProvider);
    ref.invalidate(adminPostProvider);
    ref.invalidate(pendingMembershipsProvider);
    ref.invalidate(parishListProvider);
    ref.invalidate(parishProvider);
    ref.invalidate(feedPageProvider);
    ref.invalidate(currentMembershipProvider);
    ref.invalidate(permissionsProvider);
  },
);
