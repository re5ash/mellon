import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/design_system/components/chat_surface.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

import 'club_dashboard_test.dart' show RecordingClubChats, dashboardFixture;
import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

ChatRoom room(int index) => index < 2
    ? ChatRoom.fromJson((dashboardFixture()['chats'] as List)[index] as JsonRow)
    : const ChatRoom(id: 'room-2', title: 'Третья комната', kind: 'group');

Future<void> mountSwitches(
  WidgetTester tester, {
  required Future<ChatRoom?> second,
  Future<ChatRoom?>? third,
  Future<Map<String, dynamic>>? access,
  Stream<List<ChatMessage>>? messages,
  Size size = const Size(1280, 1000),
  bool openFirst = true,
  bool editablePhoto = false,
  GestureDragUpdateCallback? onSectionDrag,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final data = dashboardFixture();
  data['club'] = <String, dynamic>{
    ...data['club'] as JsonRow,
    'can_edit_photo': editablePhoto,
  };
  (data['chats'] as List<dynamic>).add({
    ...(data['chats'] as List<dynamic>).first as JsonRow,
    'id': 'room-2',
    'title': 'Третья комната',
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('me')),
        ),
        communityRepositoryProvider.overrideWithValue(RecordingClubChats(data)),
        clubDashboardProvider('club-a').overrideWith((ref) async => data),
        chatModerationProvider.overrideWithValue(FakeChatModeration()),
        chatReadStoreProvider.overrideWithValue(FakeChatReads()),
        chatRoomProvider('room-0').overrideWith((ref) async => room(0)),
        chatRoomProvider('room-1').overrideWith((ref) => second),
        chatRoomProvider(
          'room-2',
        ).overrideWith((ref) => third ?? Future.value(room(2))),
        for (var i = 0; i < 3; i++)
          chatAccessProvider('room-$i').overrideWith(
            (ref) => i == 1 && access != null
                ? Stream.fromFuture(access)
                : Stream.value({'send': true}),
          ),
        for (var i = 0; i < 3; i++)
          chatMessagesProvider('room-$i').overrideWith(
            (ref) => i == 1 && messages != null
                ? messages
                : Stream.value(<ChatMessage>[]),
          ),
      ],
      child: RepaintBoundary(
        key: const ValueKey('chat-test-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: GestureDetector(
            onHorizontalDragUpdate: onSectionDrag,
            child: Scaffold(
              body: SingleChildScrollView(
                child: ClubDashboard(club: 'club-a', onChooseClub: () {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (!openFirst) return;
  await tester.tap(find.byKey(const ValueKey('club-chat-room-0')));
  await tester.pumpAndSettle();
  expect(tester.widget<ChatPage>(find.byType(ChatPage)).roomId, 'room-0');
}

Future<void> switchRoom(WidgetTester tester, int index) async {
  if (find.byType(ChatPage).evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip('К списку чатов'));
    await tester.pumpAndSettle();
  }
  final row = find.byKey(ValueKey('club-chat-room-$index'));
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

void main() {
  testWidgets(
    'selection is immediate and the frame stays fixed through slow loading',
    (tester) async {
      final metadata = Completer<ChatRoom?>();
      final access = Completer<Map<String, dynamic>>();
      final messages = StreamController<List<ChatMessage>>.broadcast();
      addTearDown(messages.close);
      await mountSwitches(
        tester,
        second: metadata.future,
        access: access.future,
        messages: messages.stream,
      );
      final chat = find.byType(ChatPage);
      final input = find.byKey(const ValueKey('chat-message-input'));
      final backdrop = find.byType(ChatBackdrop);
      await tester.enterText(input, 'Текст предыдущего чата');
      await tester.pumpAndSettle();
      final frameBefore = tester.getRect(chat);
      final inputBefore = tester.getRect(input);
      await switchRoom(tester, 1);
      await tester.pump();
      expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
      expect(
        find.descendant(of: chat, matching: find.text('Полезные материалы')),
        findsOneWidget,
      );
      expect(find.text('Текст предыдущего чата'), findsNothing);
      expect(tester.getRect(chat), frameBefore);
      expect(tester.getRect(input), inputBefore);
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Сообщений пока нет.'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton && widget.tooltip == 'Отправить',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == 'Эмодзи',
              ),
            )
            .onPressed,
        isNull,
      );
      final backdropElement = tester.element(backdrop);
      final inputElement = tester.element(input);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      metadata.complete(room(1));
      await tester.pump();
      await tester.pump();
      expect(tester.element(backdrop), same(backdropElement));
      expect(tester.element(input), same(inputElement));
      expect(tester.getRect(input), inputBefore);
      expect(tester.widget<TextField>(input).enabled, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Сообщений пока нет.'), findsNothing);
      access.complete({'send': true});
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextField>(input).enabled, isTrue);
      expect(tester.getRect(input), inputBefore);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Сообщений пока нет.'), findsNothing);
      messages.add([
        ChatMessage(
          id: 'new',
          authorId: 'other',
          body: 'Сообщение нового чата',
          createdAt: DateTime(2026, 9, 13),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
      expect(tester.element(backdrop), same(backdropElement));
      expect(tester.element(input), same(inputElement));
      expect(tester.getRect(chat), frameBefore);
      expect(tester.getRect(input), inputBefore);
      expect(find.text('Сообщение нового чата'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late completion cannot replace the immediately chosen chat', (
    tester,
  ) async {
    final second = Completer<ChatRoom?>();
    final third = Completer<ChatRoom?>();
    await mountSwitches(tester, second: second.future, third: third.future);
    final chat = find.byType(ChatPage);
    await switchRoom(tester, 1);
    await tester.pump();
    expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
    await switchRoom(tester, 2);
    await tester.pump();
    expect(tester.widget<ChatPage>(chat).roomId, 'room-2');
    second.complete(room(1));
    await tester.pump();
    expect(tester.widget<ChatPage>(chat).roomId, 'room-2');
    third.complete(room(2));
    await tester.pumpAndSettle();
    expect(tester.widget<ChatPage>(chat).roomId, 'room-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure keeps the selected title and backdrop with retry', (
    tester,
  ) async {
    final second = Completer<ChatRoom?>();
    await mountSwitches(tester, second: second.future);
    await switchRoom(tester, 1);
    await tester.pump();
    final chat = find.byType(ChatPage);
    final backdrop = tester.element(find.byType(ChatBackdrop));
    final frame = tester.getRect(chat);
    second.completeError(StateError('Нет связи'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
    expect(
      find.descendant(of: chat, matching: find.text('Полезные материалы')),
      findsOneWidget,
    );
    expect(tester.element(find.byType(ChatBackdrop)), same(backdrop));
    expect(tester.getRect(chat), frame);
    expect(find.text('Повторить'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Отправить',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('list metadata never grants send access', (tester) async {
    final metadata = Completer<ChatRoom?>();
    final access = Completer<Map<String, dynamic>>();
    await mountSwitches(tester, second: metadata.future, access: access.future);
    await switchRoom(tester, 1);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Отправить',
            ),
          )
          .onPressed,
      isNull,
    );
    metadata.complete(room(1));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == 'Отправить',
            ),
          )
          .onPressed,
      isNull,
    );
    access.complete({'send': false});
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Отправить',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Эмодзи',
      ),
      findsNothing,
    );
    expect(
      find.text('У вас нет права отправлять сообщения в этот чат.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile opening starts before the server responds', (
    tester,
  ) async {
    final metadata = Completer<ChatRoom?>();
    await mountSwitches(
      tester,
      second: metadata.future,
      size: const Size(390, 844),
      openFirst: false,
    );
    final row = find.byKey(const ValueKey('club-chat-room-1'));
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    await tester.pump();
    final chat = find.byType(ChatPage);
    expect(tester.widget<ChatPage>(chat).roomId, 'room-1');
    await tester.pump(const Duration(milliseconds: 450));
    final frame = tester.getRect(chat);
    final input = find.byKey(const ValueKey('chat-message-input'));
    final composer = tester.getRect(input);
    metadata.complete(room(1));
    await tester.pumpAndSettle();
    expect(tester.getRect(chat), frame);
    expect(tester.getRect(input), composer);
    expect(tester.widget<TextField>(input).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
