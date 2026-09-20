import 'chat.dart';

abstract interface class ChatRepository {
  Future<ChatRoom?> room(String id);
  Future<List<ChatRoom>> rooms(String parishId);
  Stream<List<ChatMessage>> recentMessages(String roomId);
  Future<void> send({
    required String roomId,
    required String body,
    required String nonce,
  });
}
