import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../design_system/theme_controller.dart';

final chatReadStoreProvider = Provider<ChatReadStore>((ref) {
  final client = ref.watch(backendProvider);
  return ChatReadStore(
    ref.watch(preferencesProvider),
    readRemote: (actor) async {
      if (client.auth.currentUser?.id != actor)
        throw StateError('Аккаунт изменился.');
      final rows = await client.rpc<Map<String, dynamic>>(
        'my_chat_reads',
        params: {'p_expected_user': actor},
      );
      return rows.map((key, value) => MapEntry(key, value as String));
    },
    markRemote: (actor, room, at, messageId) async {
      if (client.auth.currentUser?.id != actor)
        throw StateError('Аккаунт изменился.');
      await client.rpc<void>(
        'mark_chat_read',
        params: {
          'p_expected_user': actor,
          'p_room': room,
          'p_message': messageId,
          'p_at': at.toUtc().toIso8601String(),
        },
      );
    },
  );
});

/// Server cursors synchronize devices; local storage remains an optional cache.
/// Account IDs are part of the storage key; no message contents are stored.
class ChatReadStore {
  ChatReadStore(
    this.preferences, {
    this.readRemote,
    this.markRemote,
    this.remoteTimeout = const Duration(seconds: 15),
  });
  final Duration remoteTimeout;
  final Future<Map<String, String>> Function(String actor)? readRemote;
  final Future<void> Function(
    String actor,
    String room,
    DateTime at,
    String? messageId,
  )?
  markRemote;
  final SharedPreferencesAsync preferences;
  final _cache = <String, Map<String, String>>{};
  Future<void> _pending = Future<void>.value();

  Future<Map<String, String>> load(String actor) async {
    await _pending;
    if (readRemote != null) return readRemote!(actor).timeout(remoteTimeout);
    return Map.of(await _read(actor));
  }

  Future<Map<String, String>> _read(String actor) async {
    if (_cache.containsKey(actor)) return _cache[actor]!;
    final values = <String, String>{};
    try {
      final source = await preferences
          .getString('club-chat-reads:$actor')
          .timeout(const Duration(seconds: 2));
      if (source != null) {
        final decoded = jsonDecode(source);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            if (entry.value is String &&
                DateTime.tryParse(entry.value as String) != null)
              values[entry.key] = entry.value as String;
          }
        }
      }
    } on Object {
      // Private browsing or unavailable local storage must not block the chat.
    }
    return _cache.putIfAbsent(actor, () => values);
  }

  Future<void> mark(
    String actor,
    String room,
    DateTime at, {
    String? messageId,
  }) {
    final operation = _pending.then((_) async {
      if (markRemote != null)
        await markRemote!(actor, room, at, messageId).timeout(remoteTimeout);
      final values = await _read(actor);
      final previous = DateTime.tryParse(values[room] ?? '');
      if (previous != null && !at.isAfter(previous)) return;
      values[room] = at.toUtc().toIso8601String();
      try {
        await preferences
            .setString('club-chat-reads:$actor', jsonEncode(values))
            .timeout(const Duration(seconds: 2));
      } on Object {
        // Retain the in-memory cursor if persistence is unavailable.
      }
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}
