import 'package:moy_prihod/features/chats/application/chat_read_store.dart';

class FakeChatReads implements ChatReadStore {
  final calls = <(String, String, DateTime, String?)>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<Map<String, String>> load(String actor) async => {};
  @override
  Future<void> mark(
    String actor,
    String room,
    DateTime at, {
    String? messageId,
  }) async {
    calls.add((actor, room, at, messageId));
  }
}
