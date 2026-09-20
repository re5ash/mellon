import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../data/supabase_chat_repository.dart';
import '../domain/chat.dart';
import '../domain/chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => SupabaseChatRepository(ref.watch(backendProvider)),
);
final chatRoomsProvider = FutureProvider.autoDispose<List<ChatRoom>>((
  ref,
) async {
  ref.watch(authUserProvider);
  final repository = ref.watch(chatRepositoryProvider);
  final membership = await ref.watch(currentMembershipProvider.future);
  if (membership == null || !membership.isActive) return [];
  return repository.rooms(membership.parishId);
});
final chatMessagesProvider = StreamProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, roomId) {
      final user = ref.watch(
        authUserProvider.select((value) => value.asData?.value?.id),
      );
      _watchMembership(ref);
      if (user == null) return Stream.value([]);
      return ref
          .watch(chatRepositoryProvider)
          .recentMessages(roomId)
          .map((messages) => List<ChatMessage>.unmodifiable(messages.take(50)));
    });

final chatRoomProvider = FutureProvider.autoDispose.family<ChatRoom?, String>((
  ref,
  id,
) {
  final user = ref.watch(
    authUserProvider.select((value) => value.asData?.value?.id),
  );
  _watchMembership(ref);
  if (user == null) return null;
  return ref.watch(chatRepositoryProvider).room(id);
});

void _watchMembership(Ref ref) {
  // Identical background membership responses should not discard a warm chat.
  // Identity, parish, status and errors still invalidate private provider data.
  ref.watch(
    currentMembershipProvider.select(
      (value) => (
        value.value?.id,
        value.value?.parishId,
        value.value?.status,
        value.hasError,
      ),
    ),
  );
}
