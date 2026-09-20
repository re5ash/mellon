import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import 'chat_moderation.dart';
import 'chat_providers.dart';

final chatMemoryCacheProvider = Provider<ChatMemoryCache>((ref) {
  final cache = ChatMemoryCache(ref.container);
  ref.onDispose(cache.dispose);
  return cache;
});

/// Retains Riverpod's existing room, access and recent-message states, without
/// duplicating messages or writing private content to disk. Active subscriptions
/// keep realtime updates and the existing 20-second access checks running.
class ChatMemoryCache {
  ChatMemoryCache(
    this._container, {
    this.maxRooms = 8,
    this.idleLifetime = const Duration(minutes: 5),
  }) : assert(maxRooms > 0) {
    // This listener remains active even when every chat page is closed.
    _auth = _container.listen<String?>(
      authUserProvider.select((value) => value.asData?.value?.id),
      (_, actor) {
        if (_actor != actor) {
          _clear();
          _actor = actor;
        }
      },
      fireImmediately: true,
    );
  }

  final ProviderContainer _container;
  final int maxRooms;
  final Duration idleLifetime;
  final _rooms = LinkedHashMap<String, _CachedRoom>();
  late final ProviderSubscription<String?> _auth;
  String? _actor;
  bool _disposed = false;

  /// Called once per displayed, successfully loaded chat body. The returned
  /// release starts the idle timeout when the last displayed body goes away.
  void Function() retain(String room) {
    if (_disposed || _actor == null) return () {};
    final confirmed = _container.read(chatRoomProvider(room)).asData?.value;
    if (confirmed == null) return () {};
    if (_container.read(chatAccessProvider(room)).hasError ||
        _container.read(chatMessagesProvider(room)).hasError) {
      return () {};
    }
    var entry = _rooms.remove(room);
    final returning = entry != null;
    entry ??= _CachedRoom();
    final retained = entry;
    _rooms[room] = retained;
    retained.expiry?.cancel();
    retained.owners++;
    if (!returning) {
      retained.close.add(
        _container.listen(chatRoomProvider(room), (_, next) {
          if (next.hasError ||
              (!next.isLoading && next.asData?.value == null) ||
              (next.isLoading && next.isReloading)) {
            _reject(room, retained, source: 'room');
          }
        }, fireImmediately: true).close,
      );
      retained.close.add(
        _container.listen(chatAccessProvider(room), (_, next) {
          // send:false is valid read-only access. A failed capabilities RPC
          // means that the room must no longer be kept in the cache.
          if (next.hasError) _reject(room, retained, source: 'access');
        }, fireImmediately: true).close,
      );
      retained.close.add(
        _container.listen(chatMessagesProvider(room), (_, next) {
          if (next.hasError) _reject(room, retained, source: 'messages');
        }, fireImmediately: true).close,
      );
    } else if (!retained.rejected) {
      // Revalidate title, description and archive status in the background.
      // An explicit refresh retains the last successful value in the UI.
      _container.invalidate(chatRoomProvider(room));
    }
    while (_rooms.length > maxRooms) {
      final oldest = _rooms.entries
          .where((item) => item.value.owners == 0)
          .firstOrNull;
      _remove(oldest?.key ?? _rooms.keys.first);
    }
    var released = false;
    return () {
      if (released || _disposed || !identical(_rooms[room], retained)) return;
      released = true;
      retained.owners--;
      if (retained.owners == 0) {
        retained.expiry = Timer(idleLifetime, () {
          if (identical(_rooms[room], retained)) _remove(room);
        });
      }
    };
  }

  void _reject(String room, _CachedRoom entry, {required String source}) {
    if (_disposed || entry.rejected || !identical(_rooms[room], entry)) return;
    entry.rejected = true;
    // A first listener can report an error while retain is still attaching
    // the others. Defer cleanup until all subscriptions can be closed.
    scheduleMicrotask(() {
      if (_disposed || !identical(_rooms[room], entry)) return;
      _remove(room);
      // Drop associated private values, including active provider states.
      // Keep the originating error so the UI can display its retry action.
      if (source != 'room') {
        _container.invalidate(chatRoomProvider(room), asReload: true);
      }
      if (source != 'access') {
        _container.invalidate(chatAccessProvider(room), asReload: true);
      }
      if (source != 'messages') {
        _container.invalidate(chatMessagesProvider(room), asReload: true);
      }
    });
  }

  void _remove(String room) {
    final entry = _rooms.remove(room);
    if (entry == null) return;
    entry.expiry?.cancel();
    for (final close in entry.close.reversed) {
      close();
    }
  }

  void _clear() {
    for (final room in _rooms.keys.toList()) {
      _remove(room);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _auth.close();
    _clear();
  }
}

class _CachedRoom {
  final close = <void Function()>[];
  Timer? expiry;
  int owners = 0;
  bool rejected = false;
}
