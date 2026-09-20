class ChatReaction {
  const ChatReaction(this.emoji, this.count, this.mine);
  final String emoji;
  final int count;
  final bool mine;
}

class ChatInteractions {
  const ChatInteractions({this.pins = const [], this.reactions = const {}});
  final List<Map<String, dynamic>> pins;
  final Map<String, List<ChatReaction>> reactions;
  factory ChatInteractions.fromJson(Map<String, dynamic> data) {
    final reactions = <String, List<ChatReaction>>{};
    for (final row in (data['reactions'] as List<dynamic>? ?? const [])) {
      final r = row as Map<String, dynamic>;
      reactions
          .putIfAbsent(r['message_id'] as String, () => [])
          .add(
            ChatReaction(
              r['emoji'] as String,
              (r['count'] as num).toInt(),
              r['mine'] == true,
            ),
          );
    }
    return ChatInteractions(
      pins: (data['pins'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      reactions: reactions,
    );
  }
}

/// Kept separate so older moderation adapters retain their existing contract.
abstract interface class ChatInteractionRepository {
  Future<ChatInteractions> interactions(String room, List<String> messages);
  Future<void> react(
    String room,
    String message,
    String emoji,
    bool selected,
    String actor,
  );
  Future<void> setPinned(
    String room,
    String message,
    bool pinned,
    String actor,
  );
  Future<void> sendReply({
    required String room,
    required String body,
    required String replyTo,
    required String nonce,
    required String actor,
  });
}
