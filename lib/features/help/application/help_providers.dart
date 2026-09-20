import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/supabase_help_repository.dart';
import '../domain/help_repository.dart';
import '../domain/help_request.dart';

final helpRepositoryProvider = Provider<HelpRequestRepository>(
  (ref) => SupabaseHelpRequestRepository(ref.watch(backendProvider)),
);
final helpProvider = FutureProvider.autoDispose<List<HelpRequest>>((ref) {
  ref.watch(authUserProvider);
  return ref.watch(helpRepositoryProvider).list();
});

final myParishHelpProvider = FutureProvider.autoDispose<List<HelpRequest>>((
  ref,
) async {
  ref.watch(authUserProvider);
  final membership = await ref.watch(currentMembershipProvider.future);
  if (membership == null || !membership.isActive) return [];
  return ref.watch(helpRepositoryProvider).list(parishId: membership.parishId);
});
