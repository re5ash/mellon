import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_profile_repository.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => SupabaseProfileRepository(ref.watch(backendProvider)),
);

final ownProfileProvider =
    AsyncNotifierProvider<ProfileController, UserProfile?>(
      ProfileController.new,
      isAutoDispose: true,
      retry: (retryCount, error) => null,
    );

class ProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final userId = ref.watch(
      authUserProvider.select((value) => value.asData?.value?.id),
    );
    if (userId == null) return null;
    final profile = await ref.watch(profileRepositoryProvider).read();
    if (profile.userId != userId) throw StateError('Profile session changed');
    return profile;
  }

  // The RPC returns committed values. A second request could fail and hide
  // a successfully saved form if the network drops just after the save.
  void accept(UserProfile profile) {
    if (ref.read(authUserProvider).asData?.value?.id == profile.userId) {
      state = AsyncData(profile);
    }
  }
}
