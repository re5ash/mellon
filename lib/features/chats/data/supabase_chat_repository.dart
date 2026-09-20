import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat.dart';
import '../domain/chat_repository.dart';

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this.client);
  final SupabaseClient client;
  static const roomFields =
      'id,parish_id,youth_id,title,kind,description,icon_key,sort_order,is_archived';
  @override
  Future<ChatRoom?> room(String id) async {
    final row = await client
        .from('chat_rooms')
        .select(roomFields)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : ChatRoom.fromJson(row);
  }

  @override
  Future<List<ChatRoom>> rooms(String parishId) async {
    final rows = await client
        .from('chat_rooms')
        .select(roomFields)
        .eq('parish_id', parishId)
        .eq('is_archived', false)
        .order('sort_order', ascending: true)
        .order('title', ascending: true)
        .order('id', ascending: true)
        .limit(50);
    return rows.map(ChatRoom.fromJson).toList(growable: false);
  }

  @override
  Stream<List<ChatMessage>> recentMessages(String roomId) => client
      .from('chat_messages')
      .stream(primaryKey: ['id'])
      .eq('room_id', roomId)
      .order('created_at', ascending: false)
      .limit(50)
      .asyncMap((_) async {
        final rows = await client.rpc<List<dynamic>>(
          'chat_history_v2',
          params: {'p_room': roomId},
        );
        return rows
            .map((r) => ChatMessage.fromJson(r as Map<String, dynamic>))
            .toList(growable: false);
      });
  @override
  Future<void> send({
    required String roomId,
    required String body,
    required String nonce,
  }) async {
    await client.rpc<Object?>(
      'send_message',
      params: {'p_room': roomId, 'p_body': body, 'p_nonce': nonce},
    );
  }
}
