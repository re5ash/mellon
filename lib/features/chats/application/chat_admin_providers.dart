import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_chat_administration_repository.dart';
import '../domain/chat_administration.dart';
import 'chat_providers.dart';

final chatAdministrationRepositoryProvider =
    Provider<ChatAdministrationRepository>(
      (ref) => SupabaseChatAdministrationRepository(ref.watch(backendProvider)),
    );
final managedChatsProvider = FutureProvider.autoDispose
    .family<ManagedChatBatch, ({String parishId, String? after})>((
      ref,
      request,
    ) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref
          .watch(chatAdministrationRepositoryProvider)
          .list(request.parishId, after: request.after);
    });
final managedChatProvider = FutureProvider.autoDispose
    .family<ManagedChat?, ({String parishId, String id})>((ref, request) {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      return ref
          .watch(chatAdministrationRepositoryProvider)
          .get(request.parishId, request.id);
    });
final refreshChatAdministrationProvider = Provider<void Function()>(
  (ref) => () {
    if (!ref.mounted) return;
    ref.invalidate(managedChatsProvider);
    ref.invalidate(managedChatProvider);
    ref.invalidate(chatRoomsProvider);
    ref.invalidate(chatRoomProvider);
  },
);
