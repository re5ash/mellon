import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';

class SupabaseProfileRepository implements ProfileRepository {
  const SupabaseProfileRepository(this.client);
  final SupabaseClient client;
  @override
  Future<UserProfile> read() async => UserProfile.fromJson(
    await client.rpc<Map<String, dynamic>>('my_profile_v2'),
  );
  @override
  Future<UserProfile> save(ProfileInput input) async => UserProfile.fromJson(
    await client.rpc<Map<String, dynamic>>(
      'save_my_profile_v2',
      params: input.toRpc(),
    ),
  );
}
