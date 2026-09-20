import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

Future<void> mount(
  WidgetTester tester,
  FakeChatModeration repo, {
  double textScale = 1,
  Stream<List<ChatMessage>> Function()? messages,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatReadStoreProvider.overrideWithValue(FakeChatReads()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('me')),
        ),
        chatModerationProvider.overrideWithValue(repo),
        chatAccessProvider(
          'room',
        ).overrideWith((ref) => Stream.value(repo.rights)),
        chatRoomProvider('room').overrideWith(
          (ref) async => const ChatRoom(
            id: 'room',
            title: 'Болталка',
            kind: 'group',
            parishId: 'parish',
          ),
        ),
        chatMessagesProvider('room').overrideWith(
          (ref) =>
              messages?.call() ??
              Stream.value([
                ChatMessage(
                  id: 'own',
                  authorId: 'me',
                  body: 'Мой текст',
                  createdAt: DateTime(2026),
                ),
                ChatMessage(
                  id: 'foreign',
                  authorId: 'other',
                  authorName: 'Анна',
                  body: 'Чужой текст',
                  createdAt: DateTime(2026),
                ),
              ]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const ChatPage(roomId: 'room'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('chat create permission is separate from moderation and edit', () {
    expect(mayCreate({'messages.pin', 'chats.manage'}, 'chats'), isFalse);
    expect(mayCreate({'chats.create'}, 'chats'), isTrue);
    expect(mayDelete({'events.edit'}, 'events'), isFalse);
  });
  testWidgets(
    'member menu cannot delete foreign or pin; own delete needs confirmation',
    (tester) async {
      final repo = FakeChatModeration();
      await mount(tester, repo);
      await tester.longPress(find.text('Чужой текст'));
      await tester.pumpAndSettle();
      expect(find.text('Копировать'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Удалить сообщение'), findsNothing);
      expect(find.text('Закрепить'), findsNothing);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Мой текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить сообщение'));
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(repo.deleted, isEmpty);
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(repo.deleted, isEmpty);
      await tester.longPress(find.text('Мой текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить сообщение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['own']);
      expect(find.text('Мой текст'), findsNothing);
      expect(find.text('Сообщение удалено'), findsNothing);
      expect(find.text('Чужой текст'), findsOneWidget);
    },
  );
  testWidgets(
    'moderator can pin and visit a message outside the current page',
    (tester) async {
      final repo = FakeChatModeration()
        ..rights = {
          'send': true,
          'pin': true,
          'delete_any': true,
          'delete_own': true,
        }
        ..pinned = {
          'message_id': 'old',
          'body': 'Старое сообщение',
          'author_name': 'Анна',
        }
        ..historyRows = [
          ChatMessage(
            id: 'old',
            authorId: 'other',
            authorName: 'Анна',
            body: 'Старое сообщение',
            createdAt: DateTime(2020),
          ),
        ];
      await mount(tester, repo);
      await tester.tap(find.text('Закреплённое сообщение'));
      await tester.pumpAndSettle();
      expect(repo.anchorRequested, 'old');
      expect(find.text('Старое сообщение').hitTestable(), findsOneWidget);
      await tester.longPress(find.text('Старое сообщение'));
      await tester.pumpAndSettle();
      expect(find.text('Открепить'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Удалить сообщение'), findsOneWidget);
      await tester.tap(find.text('Открепить'));
      await tester.pumpAndSettle();
      expect(repo.pinCalls, [null]);
    },
  );
  testWidgets('progress reflects requests, not waiting for a menu choice', (
    tester,
  ) async {
    final repo = FakeChatModeration();
    await mount(tester, repo);
    final permissions = Completer<Map<String, dynamic>>();
    repo.pendingCapabilities = permissions;
    await tester.longPress(find.text('Мой текст'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Копировать'), findsNothing);
    await tester.longPress(find.text('Мой текст'));
    await tester.pump();
    expect(repo.capabilityCalls, 1);

    permissions.complete(repo.rights);
    await tester.pumpAndSettle();
    expect(find.text('Удалить сообщение'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Удалить сообщение'));
    await tester.pumpAndSettle();
    expect(find.text('Удалить сообщение?'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(repo.deleted, isEmpty);

    final deletion = Completer<void>();
    repo.pendingDelete = deletion;
    await tester.tap(find.text('Подтвердить'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.deleted, ['own']);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    deletion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Удалить сообщение?'), findsNothing);
    expect(find.text('Мой текст'), findsNothing);
    await tester.longPress(find.text('Чужой текст'));
    await tester.pumpAndSettle();
    expect(find.text('Копировать'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'failed deletion keeps the bubble and allows a successful retry',
    (tester) async {
      final repo = FakeChatModeration()..deleteError = StateError('Denied');
      await mount(tester, repo);
      await tester.longPress(find.text('Мой текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить сообщение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(find.text('Мой текст'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(repo.deleted, isEmpty);

      repo.deleteError = null;
      await tester.longPress(find.text('Мой текст'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить сообщение'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['own']);
      expect(find.text('Мой текст'), findsNothing);
      expect(find.text('Сообщение удалено'), findsNothing);
    },
  );
  testWidgets('remote deletion removes the last bubble and its pin', (
    tester,
  ) async {
    final updates = StreamController<List<ChatMessage>>.broadcast();
    addTearDown(updates.close);
    final repo = FakeChatModeration()
      ..pinned = {'message_id': 'remote', 'author_name': 'Анна'};
    final live = ChatMessage(
      id: 'remote',
      authorId: 'other',
      body: 'Сообщение Анны',
      createdAt: DateTime(2026),
    );
    final deleted = ChatMessage(
      id: 'remote',
      authorId: 'other',
      body: 'Сообщение удалено',
      createdAt: DateTime(2026),
      deleted: true,
    );
    var current = [live];
    Stream<List<ChatMessage>> messages() async* {
      yield current;
      yield* updates.stream;
    }

    await mount(tester, repo, messages: messages);
    expect(find.text('Сообщение Анны'), findsOneWidget);
    expect(find.text('Закреплённое сообщение'), findsOneWidget);
    repo.pinned = null;
    current = [deleted];
    updates.add(current);
    await tester.pumpAndSettle();
    expect(find.text('Сообщение Анны'), findsNothing);
    expect(find.text('Сообщение удалено'), findsNothing);
    expect(find.text('Закреплённое сообщение'), findsNothing);
    expect(find.text('Сообщений пока нет.'), findsOneWidget);
    // A refetch containing tombstones must not resurrect a deleted bubble.
    await tester.tap(find.byTooltip('Обновить чат'));
    await tester.pumpAndSettle();
    expect(find.text('Сообщение удалено'), findsNothing);
    expect(find.text('Сообщение Анны'), findsNothing);
  });
  testWidgets(
    'deleted history stays invisible without losing the older cursor',
    (tester) async {
      final rows = List.generate(
        50,
        (i) => ChatMessage(
          id: 'deleted-$i',
          authorId: 'other',
          body: 'Сообщение удалено',
          createdAt: DateTime(2026).subtract(Duration(minutes: i)),
          deleted: true,
        ),
      );
      final repo = FakeChatModeration()
        ..historyRows = [
          ChatMessage(
            id: 'earlier',
            authorId: 'other',
            body: 'Раннее сообщение',
            createdAt: DateTime(2025),
          ),
        ];
      await mount(tester, repo, messages: () => Stream.value(rows));
      expect(find.text('Сообщение удалено'), findsNothing);
      expect(find.text('Более ранние сообщения'), findsOneWidget);
      await tester.tap(find.text('Более ранние сообщения'));
      await tester.pumpAndSettle();
      expect(repo.beforeRequested?.id, rows.last.id);
      expect(find.text('Раннее сообщение'), findsOneWidget);
      expect(find.text('Сообщение удалено'), findsNothing);
    },
  );
  testWidgets('long text wraps on narrow screen with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeChatModeration()
      ..pinned = {
        'message_id': 'own',
        'body': 'Очень длинное сообщение ' * 40,
        'author_name': 'Длинное имя участника ' * 3,
      };
    await mount(tester, repo, textScale: 1.8);
    expect(tester.takeException(), isNull);
  });
}
