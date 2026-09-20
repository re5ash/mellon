import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/core/access/permission_providers.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/administration/application/admin_providers.dart';
import 'package:moy_prihod/features/administration/domain/admin_models.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_admin_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/domain/chat_administration.dart';
import 'package:moy_prihod/features/chats/presentation/chat_editor_page.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'administration_test.dart' show tapVisible;
import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

const parish = '20000000-0000-0000-0000-000000000001';
const actor = '40000000-0000-0000-0000-000000000001';

class FakeChatAdmin implements ChatAdministrationRepository {
  final writes = <ChatInput>[];
  Completer<ManagedChat>? pending;
  @override
  Future<ManagedChat> save(ChatInput input) {
    writes.add(input);
    return pending?.future ??
        Future.value(
          ManagedChat(
            room: ChatRoom(id: input.id, title: input.title, kind: input.kind),
            revision: 2,
            access: 'parish',
          ),
        );
  }

  @override
  Future<ManagedChatBatch> list(String parishId, {String? after}) async =>
      const ManagedChatBatch([], null);
  @override
  Future<ManagedChat?> get(String parishId, String id) async => null;
}

AdminParish managed({bool allowed = true}) => AdminParish(
  id: parish,
  cityName: 'Город',
  name: 'Приход',
  description: '',
  address: '',
  joinMode: 'approval',
  isPublished: true,
  updatedAt: DateTime.utc(2026),
  permissions: allowed ? {'chats.manage'} : {},
);
Future<void> mountEditor(
  WidgetTester tester,
  FakeChatAdmin repository, {
  ManagedChat? chat,
  ManagedChat Function()? refreshedChat,
  bool allowed = true,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) =>
            ChatEditorPage(parishId: parish, roomId: chat?.room.id),
      ),
      GoRoute(
        path: '/admin/parishes/:id/chats',
        builder: (_, state) => const Scaffold(body: Text('Список чатов')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatReadStoreProvider.overrideWithValue(FakeChatReads()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(actor)),
        ),
        chatAdministrationRepositoryProvider.overrideWithValue(repository),
        refreshChatAdministrationProvider.overrideWithValue(() {}),
        managedParishProvider(
          parish,
        ).overrideWith((ref) async => managed(allowed: allowed)),
        if (chat != null)
          managedChatProvider((
            parishId: parish,
            id: chat.room.id,
          )).overrideWith((ref) async => refreshedChat?.call() ?? chat),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'create validates, prevents double submit and retries with the same identity',
    (tester) async {
      final repository = FakeChatAdmin()..pending = Completer<ManagedChat>();
      await mountEditor(tester, repository);
      await tapVisible(tester, find.text('Сохранить чат'));
      expect(repository.writes, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, 'Болталка');
      await tester.enterText(find.byType(TextFormField).last, '-1');
      await tapVisible(tester, find.text('Сохранить чат'));
      expect(repository.writes, isEmpty);
      await tester.enterText(find.byType(TextFormField).last, '10');
      await tapVisible(tester, find.text('Сохранить чат'));
      expect(repository.writes, hasLength(1));
      expect(repository.writes.single.actorId, actor);
      expect(repository.writes.single.parishId, parish);
      expect(repository.writes.single.kind, 'group');
      expect(repository.writes.single.archived, isFalse);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      repository.pending!.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Болталка',
      );
      repository.pending = null;
      await tapVisible(tester, find.text('Сохранить чат'));
      expect(repository.writes, hasLength(2));
      expect(repository.writes.first.id, repository.writes.last.id);
      expect(find.text('Список чатов'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'editing keeps revision and draft after a concurrent edit conflict',
    (tester) async {
      final repository = FakeChatAdmin()..pending = Completer<ManagedChat>();
      const chat = ManagedChat(
        room: ChatRoom(
          id: 'chat-1',
          title: 'Объявления',
          kind: 'channel',
          description: 'Важное',
          iconKey: 'news',
          sortOrder: 5,
          archived: true,
        ),
        revision: 7,
        access: 'restricted',
      );
      var loaded = chat;
      await mountEditor(
        tester,
        repository,
        chat: chat,
        refreshedChat: () => loaded,
      );
      // A background refresh must not advance the local draft's expected revision.
      loaded = ManagedChat(room: chat.room, revision: 8, access: 'restricted');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatEditorPage)),
      );
      container.invalidate(
        managedChatProvider((parishId: parish, id: chat.room.id)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Новое название',
      );
      await tapVisible(tester, find.text('Сохранить чат'));
      final sent = repository.writes.single;
      expect(sent.id, 'chat-1');
      expect(sent.create, isFalse);
      expect(sent.revision, 7);
      expect(sent.kind, 'channel');
      expect(sent.archived, isTrue);
      expect(sent.iconKey, 'news');
      repository.pending!.completeError(
        const PostgrestException(message: 'edit_conflict', code: '40001'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Запись уже изменена'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Новое название',
      );
      expect(find.byType(ChatEditorForm), findsOneWidget);
    },
  );
  testWidgets('without room-management capability no editor is displayed', (
    tester,
  ) async {
    await mountEditor(tester, FakeChatAdmin(), allowed: false);
    expect(find.text('Доступ ограничен'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });
  testWidgets('editor fits narrow screen with keyboard and enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              viewInsets: const EdgeInsets.only(bottom: 260),
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: ChatEditorForm(
              parishId: parish,
              parishName: 'Приход с длинным названием',
              actorId: actor,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
  });
  for (final item
      in <
        ({String kind, bool archived, Set<String> permissions, bool composer})
      >[
        (
          kind: 'group',
          archived: false,
          permissions: {'chat.send'},
          composer: true,
        ),
        (
          kind: 'channel',
          archived: false,
          permissions: {'chat.send'},
          composer: false,
        ),
        (
          kind: 'channel',
          archived: false,
          permissions: {'channels.publish'},
          composer: true,
        ),
        (
          kind: 'group',
          archived: true,
          permissions: {'chat.send', 'chats.manage'},
          composer: false,
        ),
      ]) {
    testWidgets(
      'composer obeys room kind ${item.kind}, archive ${item.archived}, rights ${item.permissions}',
      (tester) async {
        final room = ChatRoom(
          id: 'room',
          parishId: parish,
          title: 'Название',
          kind: item.kind,
          archived: item.archived,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatReadStoreProvider.overrideWithValue(FakeChatReads()),
              authUserProvider.overrideWith(
                (ref) => Stream.value(const AppUser(actor)),
              ),
              chatModerationProvider.overrideWithValue(FakeChatModeration()),
              chatAccessProvider(
                'room',
              ).overrideWith((ref) => Stream.value({'send': item.composer})),
              chatRoomProvider('room').overrideWith((ref) async => room),
              permissionsProvider(
                parish,
              ).overrideWith((ref) async => item.permissions),
              chatMessagesProvider(
                'room',
              ).overrideWith((ref) => Stream.value(<ChatMessage>[])),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const ChatPage(roomId: 'room'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Название'), findsOneWidget);
        expect(
          find.byTooltip('Отправить'),
          item.composer ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(TextField),
          item.composer ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('switching account discards the previous account draft', (
    tester,
  ) async {
    final auth = StreamController<AppUser?>();
    addTearDown(auth.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatReadStoreProvider.overrideWithValue(FakeChatReads()),
          authUserProvider.overrideWith((ref) => auth.stream),
          managedParishProvider(parish).overrideWith((ref) async => managed()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ChatEditorPage(parishId: parish),
        ),
      ),
    );
    auth.add(const AppUser(actor));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Личный черновик');
    auth.add(const AppUser('second-user'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
