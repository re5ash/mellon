import 'chat.dart';

class ManagedChat {
  const ManagedChat({
    required this.room,
    required this.revision,
    required this.access,
  });
  final ChatRoom room;
  final int revision;
  final String access;
  factory ManagedChat.fromJson(Map<String, dynamic> json) => ManagedChat(
    room: ChatRoom.fromJson(json),
    revision: (json['revision'] as num).toInt(),
    access: json['access'] as String,
  );
}

class ManagedChatBatch {
  const ManagedChatBatch(this.items, this.next);
  final List<ManagedChat> items;
  final String? next;
}

class ChatInput {
  const ChatInput({
    required this.id,
    required this.parishId,
    required this.actorId,
    required this.create,
    required this.title,
    required this.description,
    required this.kind,
    required this.iconKey,
    required this.sortOrder,
    required this.archived,
    this.revision,
  });
  final String id, parishId, actorId, title, description, kind, iconKey;
  final bool create, archived;
  final int sortOrder;
  final int? revision;
}

abstract interface class ChatAdministrationRepository {
  Future<ManagedChatBatch> list(String parishId, {String? after});
  Future<ManagedChat?> get(String parishId, String id);
  Future<ManagedChat> save(ChatInput input);
}
