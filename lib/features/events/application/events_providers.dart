import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/supabase_events_repository.dart';
import '../domain/event.dart';
import '../domain/events_repository.dart';

final eventsRepositoryProvider = Provider<ParishEventRepository>(
  (ref) => SupabaseParishEventRepository(ref.watch(backendProvider)),
);
final eventsProvider = FutureProvider.autoDispose<List<ParishEvent>>((ref) {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  return ref.watch(eventsRepositoryProvider).list();
});

final myParishEventsProvider = FutureProvider.autoDispose<List<ParishEvent>>((
  ref,
) async {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  final membership = await ref.watch(currentMembershipProvider.future);
  if (membership?.isActive != true) return [];
  return ref
      .watch(eventsRepositoryProvider)
      .list(parishId: membership!.parishId);
});
