import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/chat.dart';
import '../domain/chat_interactions.dart';

final chatModerationProvider = Provider<ChatModerationRepository>(
  (ref) => SupabaseChatModerationRepository(ref.watch(backendProvider)),
);
final chatAccessProvider = StreamProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, room) {
      final actor = ref.watch(
        authUserProvider.select((value) => value.asData?.value?.id),
      );
      if (actor == null) return Stream.value(<String, dynamic>{});
      final repo = ref.watch(chatModerationProvider);
      final output = StreamController<Map<String, dynamic>>();
      var stopped = false, busy = false;
      late final Timer timer;
      Future<void> refresh() async {
        if (stopped || busy) return;
        busy = true;
        try {
          final access = await repo
              .capabilities(room)
              .timeout(const Duration(seconds: 20));
          if (!stopped) output.add(access);
        } on Object catch (error, stack) {
          if (!stopped) {
            stopped = true;
            timer.cancel();
            output.addError(error, stack);
            unawaited(output.close());
          }
        } finally {
          busy = false;
        }
      }

      timer = Timer.periodic(const Duration(seconds: 20), (_) {
        unawaited(refresh());
      });
      ref.onDispose(() {
        stopped = true;
        timer.cancel();
        unawaited(output.close());
      });
      unawaited(refresh());
      return output.stream;
    }, retry: (_, error) => null);

abstract interface class ChatModerationRepository {
  Future<Map<String, dynamic>> capabilities(String room);
  Future<List<ChatMessage>> history(
    String room, {
    ChatMessage? before,
    String? anchor,
  });
  Future<Map<String, dynamic>?> pin(String room);
  Future<void> setPin(String room, String? message, String actor);
  Future<void> delete(String message, String actor);
  Stream<List<Map<String, dynamic>>> changes(String room);
}

class SupabaseChatModerationRepository
    implements ChatModerationRepository, ChatInteractionRepository {
  const SupabaseChatModerationRepository(this.client);
  final SupabaseClient client;
  Future<Map<String, dynamic>> capabilities(String room) => client
      .rpc<Map<String, dynamic>>('chat_capabilities', params: {'p_room': room});
  Future<List<ChatMessage>> history(
    String room, {
    ChatMessage? before,
    String? anchor,
  }) async => (await client.rpc<List<dynamic>>(
    'chat_history_v2',
    params: {
      'p_room': room,
      'p_before': before?.createdAt.toUtc().toIso8601String(),
      'p_before_id': before?.id,
      'p_anchor': anchor,
    },
  )).map((r) => ChatMessage.fromJson(r as Map<String, dynamic>)).toList();
  Future<Map<String, dynamic>?> pin(String room) => client
      .rpc<Map<String, dynamic>?>('current_chat_pin', params: {'p_room': room});
  Future<void> setPin(String room, String? message, String actor) async {
    await client.rpc<void>(
      'set_chat_pin',
      params: {'p_room': room, 'p_message': message, 'p_expected_user': actor},
    );
  }

  Future<void> delete(String message, String actor) async {
    await client.rpc<void>(
      'delete_chat_message',
      params: {'p_message': message, 'p_expected_user': actor},
    );
  }

  Stream<List<Map<String, dynamic>>> changes(String room) => client
      .from('chat_interaction_changes')
      .stream(primaryKey: ['room_id'])
      .eq('room_id', room);

  @override
  Future<ChatInteractions> interactions(
    String room,
    List<String> messages,
  ) async => ChatInteractions.fromJson(
    await client.rpc<Map<String, dynamic>>(
      'chat_interactions',
      params: {'p_room': room, 'p_messages': messages},
    ),
  );
  @override
  Future<void> react(
    String room,
    String message,
    String emoji,
    bool selected,
    String actor,
  ) async {
    await client.rpc<void>(
      'set_chat_reaction',
      params: {
        'p_room': room,
        'p_message': message,
        'p_emoji': emoji,
        'p_selected': selected,
        'p_expected_user': actor,
      },
    );
  }

  @override
  Future<void> setPinned(
    String room,
    String message,
    bool pinned,
    String actor,
  ) async {
    await client.rpc<void>(
      'set_chat_message_pin',
      params: {
        'p_room': room,
        'p_message': message,
        'p_pinned': pinned,
        'p_expected_user': actor,
      },
    );
  }

  @override
  Future<void> sendReply({
    required String room,
    required String body,
    required String replyTo,
    required String nonce,
    required String actor,
  }) async {
    await client.rpc<Object?>(
      'send_chat_reply',
      params: {
        'p_room': room,
        'p_body': body,
        'p_reply_to': replyTo,
        'p_nonce': nonce,
        'p_expected_user': actor,
      },
    );
  }
}
