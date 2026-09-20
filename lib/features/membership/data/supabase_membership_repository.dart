import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/membership.dart';
import '../domain/membership_repository.dart';

class SupabaseMembershipRepository implements MembershipRepository {
  SupabaseMembershipRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Membership?> current(String userId) async {
    final row = await client
        .from('memberships')
        .select('id,parish_id,status')
        .eq('user_id', userId)
        .inFilter('status', ['pending', 'active'])
        .maybeSingle();
    return row == null ? null : Membership.fromJson(row);
  }

  @override
  Future<void> request(String parishId) async {
    await client.rpc<Object?>(
      'request_membership',
      params: {'p_parish': parishId},
    );
  }

  @override
  Future<void> leave() async {
    await client.rpc<Object?>('leave_parish');
  }
}
