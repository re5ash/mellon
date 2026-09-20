import 'dart:async';

import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';

class FakeChatModeration implements ChatModerationRepository {
  Map<String, dynamic> rights = {
    'send': true,
    'delete_own': true,
    'delete_any': false,
    'pin': false,
  };
  Map<String, dynamic>? pinned;
  List<ChatMessage> historyRows = [];
  String? anchorRequested;
  ChatMessage? beforeRequested;
  Object? deleteError;
  final deleted = <String>[];
  final pinCalls = <String?>[];
  Completer<Map<String, dynamic>>? pendingCapabilities;
  Completer<void>? pendingDelete;
  int capabilityCalls = 0;
  @override
  Future<Map<String, dynamic>> capabilities(String room) async {
    capabilityCalls++;
    return pendingCapabilities == null
        ? rights
        : await pendingCapabilities!.future;
  }

  @override
  Stream<List<Map<String, dynamic>>> changes(String room) => Stream.value([]);
  @override
  Future<Map<String, dynamic>?> pin(String room) async => pinned;
  @override
  Future<List<ChatMessage>> history(
    String room, {
    ChatMessage? before,
    String? anchor,
  }) async {
    anchorRequested = anchor;
    beforeRequested = before;
    return historyRows;
  }

  @override
  Future<void> setPin(String room, String? message, String actor) async {
    pinCalls.add(message);
    pinned = message == null
        ? null
        : {'message_id': message, 'author_name': 'Анна', 'body': 'Текст'};
  }

  @override
  Future<void> delete(String message, String actor) async {
    if (deleteError != null) throw deleteError!;
    deleted.add(message);
    if (pendingDelete != null) await pendingDelete!.future;
    if (pinned?['message_id'] == message) pinned = null;
  }
}
