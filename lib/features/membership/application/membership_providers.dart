import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_membership_repository.dart';
import '../domain/membership.dart';
import '../domain/membership_repository.dart';

final membershipRepositoryProvider = Provider<MembershipRepository>(
  (ref) => SupabaseMembershipRepository(ref.watch(backendProvider)),
);
final currentMembershipProvider = FutureProvider.autoDispose<Membership?>((
  ref,
) async {
  final user = ref.watch(authUserProvider).asData?.value;
  if (user == null) return null;
  return ref.watch(membershipRepositoryProvider).current(user.id);
});
