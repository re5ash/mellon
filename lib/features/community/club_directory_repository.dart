import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../auth/application/auth_providers.dart';
import 'community_repository.dart';

final clubDirectoryProvider = FutureProvider.autoDispose<List<JsonRow>>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  ref.watch(
    accountAccessProvider.select(
      (value) =>
          (value.asData?.value.restrictedGuest, value.asData?.value.superAdmin),
    ),
  );
  return ref.watch(communityRepositoryProvider).rows('youth_club_directory');
}, retry: (_, error) => null);

final managedClubsProvider = FutureProvider.autoDispose<List<JsonRow>>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  ref.listen(accountAccessProvider, (_, next) {
    if (!next.isLoading && next.asData != null) ref.invalidateSelf();
  });
  final access = ref.read(accountAccessProvider).asData?.value;
  if (access?.superAdmin != true || access?.restrictedGuest == true) return [];
  return ref.watch(communityRepositoryProvider).rows('managed_youth_groups');
}, retry: (_, error) => null);

final clubCitiesProvider = FutureProvider.autoDispose<List<JsonRow>>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  return ref.watch(communityRepositoryProvider).rows('club_management_cities');
}, retry: (_, error) => null);

// Content moderation stays available to the existing local roles. This endpoint
// does not permit creating, editing or archiving clubs themselves.
final clubWorkspacesProvider = FutureProvider.autoDispose<List<JsonRow>>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  ref.listen(accountAccessProvider, (_, next) {
    if (!next.isLoading && next.asData != null) ref.invalidateSelf();
  });
  return ref.watch(communityRepositoryProvider).rows('my_club_workspaces');
}, retry: (_, error) => null);

final clubEntryProvider = FutureProvider.autoDispose.family<JsonRow, String>((
  ref,
  club,
) async {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  return Map<String, dynamic>.from(
    await ref.watch(communityRepositoryProvider).call('club_entry', {
          'p_youth': club,
        })
        as Map<String, dynamic>,
  );
}, retry: (_, error) => null);
