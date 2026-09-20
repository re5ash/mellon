import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_administration.dart';

class SupabaseChatAdministrationRepository
    implements ChatAdministrationRepository {
  const SupabaseChatAdministrationRepository(this.client);
  final SupabaseClient client;
  @override
  Future<ManagedChatBatch> list(String parishId, {String? after}) async {
    final rows = await client.rpc<List<dynamic>>(
      'admin_chat_rooms',
      params: {'p_parish': parishId, 'p_after': after, 'p_limit': 21},
    );
    final items = rows
        .take(20)
        .map((row) => ManagedChat.fromJson(row as Map<String, dynamic>))
        .toList();
    return ManagedChatBatch(
      items,
      rows.length > 20 ? items.last.room.id : null,
    );
  }

  @override
  Future<ManagedChat?> get(String parishId, String id) async {
    final rows = await client.rpc<List<dynamic>>(
      'admin_chat_rooms',
      params: {'p_parish': parishId, 'p_only': id, 'p_limit': 1},
    );
    return rows.isEmpty
        ? null
        : ManagedChat.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<ManagedChat> save(ChatInput input) async {
    final row = await client.rpc<Map<String, dynamic>>(
      'admin_save_chat',
      params: {
        'p_id': input.id,
        'p_parish': input.parishId,
        'p_expected_user': input.actorId,
        'p_create': input.create,
        'p_title': input.title,
        'p_description': input.description,
        'p_kind': input.kind,
        'p_icon': input.iconKey,
        'p_sort': input.sortOrder,
        'p_archived': input.archived,
        'p_expected_revision': input.revision,
      },
    );
    return ManagedChat.fromJson(row);
  }
}
