class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.title,
    required this.kind,
    this.parishId = '',
    this.description = '',
    this.iconKey = 'auto',
    this.sortOrder = 100,
    this.archived = false,
    this.youthId,
  });
  final String? youthId;
  final String parishId, description, iconKey;
  final int sortOrder;
  final bool archived;
  final String id;
  final String title;
  final String kind;
  factory ChatRoom.fromJson(Map<String, dynamic> json) => ChatRoom(
    id: json['id'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String,
    youthId: json['youth_id'] as String?,
    parishId: json['parish_id'] as String? ?? '',
    description: json['description'] as String? ?? '',
    iconKey: json['icon_key'] as String? ?? 'auto',
    sortOrder: (json['sort_order'] as num?)?.toInt() ?? 100,
    archived: json['is_archived'] as bool? ?? false,
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.body,
    required this.createdAt,
    this.authorName = 'Участник',
    this.deleted = false,
    this.reply,
  });
  final String id;
  final String authorId;
  final String body;
  final DateTime createdAt;
  final String authorName;
  final bool deleted;
  final MessageReply? reply;
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    authorId: json['author_id'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
    authorName: json['author_name'] as String? ?? 'Участник',
    deleted: json['deleted_at'] != null,
    reply: json['reply'] is Map<String, dynamic>
        ? MessageReply.fromJson(json['reply'] as Map<String, dynamic>)
        : null,
  );
}

class MessageReply {
  const MessageReply({
    required this.id,
    required this.author,
    required this.excerpt,
    this.deleted = false,
  });
  final String id, author, excerpt;
  final bool deleted;
  factory MessageReply.fromJson(Map<String, dynamic> row) => MessageReply(
    id: row['id'] as String,
    author: row['author_name'] as String? ?? 'Участник',
    excerpt: row['body'] as String? ?? 'Вложение',
    deleted: row['deleted'] == true,
  );
}
