import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_memory_cache.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/domain/chat_repository.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/membership/application/membership_providers.dart';
import 'package:moy_prihod/features/membership/domain/membership.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

ChatMessage message(String body) => ChatMessage(
  id: body,
  authorId: 'other',
  body: body,
  createdAt: DateTime(2026, 9, 13),
);

class CacheRepository implements ChatRepository {
  final roomsRead = <String, int>{};
  final titles = <String, String>{};
  final streamsOpened = <String, int>{};
  final streamsClosed = <String, int>{};
  final pending = <String, Completer<ChatRoom?>>{};
  final rows = <String, List<ChatMessage>>{};
  final buses = <String, StreamController<List<ChatMessage>>>{};
  final unavailable = <String>{};

  @override
  Future<ChatRoom?> room(String id) async {
    roomsRead.update(id, (value) => value + 1, ifAbsent: () => 1);
    if (pending[id] case final request?) return request.future;
    if (unavailable.contains(id)) return null;
    return ChatRoom(id: id, title: titles[id] ?? 'Чат $id', kind: 'group');
  }

  @override
  Stream<List<ChatMessage>> recentMessages(String id) {
    streamsOpened.update(id, (value) => value + 1, ifAbsent: () => 1);
    buses.putIfAbsent(id, () => StreamController.broadcast());
    return Stream<List<ChatMessage>>.multi((output) {
      final subscription = buses[id]!.stream.listen(
        output.add,
        onError: output.addError,
        onDone: output.close,
      );
      output.add(rows[id] ?? [message('Текст $id')]);
      output.onCancel = () {
        streamsClosed.update(id, (value) => value + 1, ifAbsent: () => 1);
        return subscription.cancel();
      };
    });
  }

  void update(String id, List<ChatMessage> value) {
    rows[id] = value;
    buses[id]?.add(value);
  }

  @override
  Future<List<ChatRoom>> rooms(String parishId) async => [];
  @override
  Future<void> send({
    required String roomId,
    required String body,
    required String nonce,
  }) async {}
}

class CacheModeration extends FakeChatModeration {
  final errors = <String, Object>{};
  @override
  Future<Map<String, dynamic>> capabilities(String room) async {
    if (errors[room] case final error?) throw error;
    return super.capabilities(room);
  }
}

final _fixtures = <CacheFixture>[];

void cacheTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final fixture in _fixtures) {
        await fixture.dispose();
      }
      _fixtures.clear();
      await tester.pump(Duration.zero);
    }
  });
}

class CacheFixture {
  final repo = CacheRepository();
  final moderation = CacheModeration();
  final users = StreamController<AppUser?>.broadcast();
  Membership membership = const Membership(
    id: 'member',
    parishId: 'parish',
    status: 'active',
  );
  late final ProviderContainer container;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    container.dispose();
    await users.close();
    for (final bus in repo.buses.values) {
      await bus.close();
    }
  }

  Future<void> start(
    WidgetTester tester, {
    int maxRooms = 8,
    Duration idleLifetime = const Duration(minutes: 5),
  }) async {
    container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) async* {
          yield const AppUser('alice');
          yield* users.stream;
        }),
        currentMembershipProvider.overrideWith((ref) async => membership),
        chatRepositoryProvider.overrideWithValue(repo),
        chatModerationProvider.overrideWithValue(moderation),
        chatReadStoreProvider.overrideWithValue(FakeChatReads()),
        chatMemoryCacheProvider.overrideWith((ref) {
          final cache = ChatMemoryCache(
            ref.container,
            maxRooms: maxRooms,
            idleLifetime: idleLifetime,
          );
          ref.onDispose(cache.dispose);
          return cache;
        }),
      ],
    );
    // The app shell normally observes these session providers too.
    container.listen(authUserProvider, (_, _) {});
    container.listen(currentMembershipProvider, (_, _) {});
    _fixtures.add(this);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  Future<void Function()> open(WidgetTester tester, String room) async {
    final roomSub = container.listen(chatRoomProvider(room), (_, _) {});
    final messageSub = container.listen(chatMessagesProvider(room), (_, _) {});
    final accessSub = container.listen(chatAccessProvider(room), (_, _) {});
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    final release = container.read(chatMemoryCacheProvider).retain(room);
    return () {
      release();
      accessSub.close();
      messageSub.close();
      roomSub.close();
    };
  }
}

class CacheHarness extends StatefulWidget {
  const CacheHarness({super.key});
  @override
  State<CacheHarness> createState() => _CacheHarnessState();
}

class _CacheHarnessState extends State<CacheHarness> {
  String room = 'a';
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Row(
          children: [
            for (final id in ['a', 'b'])
              TextButton(
                key: ValueKey('choose-$id'),
                onPressed: () => setState(() => room = id),
                child: Text(id),
              ),
          ],
        ),
        Expanded(
          child: ChatPage(key: ValueKey(room), roomId: room),
        ),
      ],
    ),
  );
}

void main() {
  cacheTest(
    'return displays cached messages on the first frame while metadata refreshes',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: f.container,
          child: MaterialApp(theme: AppTheme.light, home: const CacheHarness()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Текст a'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('choose-b')));
      await tester.pumpAndSettle();
      expect(find.text('Текст b'), findsOneWidget);
      f.repo.update('a', [message('Новое сообщение a')]);
      await tester.pump(Duration.zero);
      final pending = Completer<ChatRoom?>();
      f.repo.pending['a'] = pending;
      final streams = f.repo.streamsOpened['a'];
      await tester.tap(find.byKey(const ValueKey('choose-a')));
      await tester.pump(Duration.zero);
      expect(find.text('Новое сообщение a'), findsOneWidget);
      expect(find.text('Текст b'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-message-input')))
            .enabled,
        isTrue,
      );
      expect(f.repo.streamsOpened['a'], streams);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      pending.complete(
        const ChatRoom(id: 'a', title: 'Обновлённый чат', kind: 'group'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Обновлённый чат'), findsOneWidget);
      expect(find.text('Новое сообщение a'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  cacheTest(
    'inactive cached chats receive updates and retain only 50 messages',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      final close = await f.open(tester, 'a');
      close();
      await tester.pump(Duration.zero);
      f.repo.update('a', [for (var i = 0; i < 70; i++) message('updated-$i')]);
      await tester.pump(Duration.zero);
      final value = f.container.read(chatMessagesProvider('a')).asData!.value;
      expect(value.length, 50);
      expect(value.first.body, 'updated-0');
      expect(f.repo.streamsOpened['a'], 1);
      expect(f.repo.streamsClosed['a'] ?? 0, 0);
    },
  );

  cacheTest('cache evicts the least recently opened idle room', (tester) async {
    final f = CacheFixture();
    await f.start(tester, maxRooms: 2);
    (await f.open(tester, 'a'))();
    (await f.open(tester, 'b'))();
    (await f.open(tester, 'a'))();
    await tester.pump(Duration.zero);
    (await f.open(tester, 'c'))();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(f.repo.streamsClosed['b'], 1);
    expect(f.repo.streamsClosed['a'] ?? 0, 0);
    expect(f.repo.streamsClosed['c'] ?? 0, 0);
  });

  cacheTest(
    'idle expiry closes subscriptions and opening again loads fresh data',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester, idleLifetime: const Duration(seconds: 2));
      (await f.open(tester, 'a'))();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(Duration.zero);
      expect(f.repo.streamsClosed['a'], 1);
      f.repo.rows['a'] = [message('fresh')];
      (await f.open(tester, 'a'))();
      expect(f.repo.streamsOpened['a'], 2);
      expect(
        f.container.read(chatMessagesProvider('a')).asData!.value.single.body,
        'fresh',
      );
    },
  );

  cacheTest(
    'logout clears cached subscriptions even without an open chat page',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      (await f.open(tester, 'a'))();
      f.users.add(null);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(f.repo.streamsClosed['a'], 1);
      expect(
        f.container.read(chatMessagesProvider('a')).asData?.value ?? [],
        isEmpty,
      );
      f.repo.rows['a'] = [message('bob content')];
      f.users.add(const AppUser('bob'));
      await tester.pump(Duration.zero);
      (await f.open(tester, 'a'))();
      expect(
        f.container.read(chatMessagesProvider('a')).asData!.value.single.body,
        'bob content',
      );
    },
  );

  cacheTest(
    'same account and identical membership refresh retain cached data',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      (await f.open(tester, 'a'))();
      final reads = f.repo.roomsRead['a'];
      final capabilities = f.moderation.capabilityCalls;
      f.users.add(const AppUser('alice'));
      f.container.invalidate(currentMembershipProvider);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(f.repo.roomsRead['a'], reads);
      expect(f.repo.streamsOpened['a'], 1);
      expect(f.moderation.capabilityCalls, capabilities);
    },
  );

  cacheTest('changed membership clears cached room and message subscriptions', (
    tester,
  ) async {
    final f = CacheFixture();
    await f.start(tester);
    (await f.open(tester, 'a'))();
    f.membership = const Membership(
      id: 'member',
      parishId: 'parish',
      status: 'banned',
    );
    f.repo.unavailable.add('a');
    f.container.invalidate(currentMembershipProvider);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(f.repo.streamsClosed['a'], greaterThanOrEqualTo(1));
    expect(f.container.read(chatRoomProvider('a')).asData?.value, isNull);
  });

  cacheTest(
    'background access revocation drops cached messages without reopening',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      (await f.open(tester, 'a'))();
      f.moderation.errors['a'] = const PostgrestException(
        message: 'forbidden',
        code: '42501',
      );
      f.repo.unavailable.add('a');
      await tester.pump(const Duration(seconds: 21));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(f.repo.streamsClosed['a'], 1);
      expect(f.container.read(chatRoomProvider('a')).asData?.value, isNull);
    },
  );

  cacheTest(
    'read-only chat remains cached and send permission is not invented',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      f.moderation.rights['send'] = false;
      (await f.open(tester, 'a'))();
      await tester.pump(const Duration(seconds: 21));
      expect(f.repo.streamsClosed['a'] ?? 0, 0);
      expect(
        f.container.read(chatAccessProvider('a')).asData!.value['send'],
        isFalse,
      );
    },
  );
  cacheTest(
    'late reply from an old account cannot repopulate the new account cache',
    (tester) async {
      final f = CacheFixture();
      await f.start(tester);
      (await f.open(tester, 'a'))();
      final oldReply = Completer<ChatRoom?>();
      f.repo.pending['a'] = oldReply;
      f.container.invalidate(chatRoomProvider('a'));
      await tester.pump(Duration.zero);
      f.repo.pending.remove('a');
      f.repo.titles['a'] = 'Чат для Bob';
      f.repo.rows['a'] = [message('Текст для Bob')];
      f.users.add(const AppUser('bob'));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      (await f.open(tester, 'a'))();
      oldReply.complete(
        const ChatRoom(id: 'a', title: 'Старый чат Alice', kind: 'group'),
      );
      await tester.pump(Duration.zero);
      expect(
        f.container.read(chatRoomProvider('a')).asData!.value!.title,
        'Чат для Bob',
      );
      expect(
        f.container.read(chatMessagesProvider('a')).asData!.value.single.body,
        'Текст для Bob',
      );
    },
  );
}
