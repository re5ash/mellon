import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/domain/chat_interactions.dart';

import 'community_chat_test.dart' as harness;
import 'support/fake_chat_moderation.dart';

class InteractionFixture extends FakeChatModeration
    implements ChatInteractionRepository {
  InteractionFixture() {
    rights = {...rights, 'react': true, 'pin': true};
  }
  final updates = StreamController<List<Map<String, dynamic>>>.broadcast();
  final pins = <Map<String, dynamic>>[];
  final reactions = <String, List<ChatReaction>>{};
  final historyRequests = <({String? before, String? anchor})>[];
  final replies =
      <
        ({String room, String body, String parent, String nonce, String actor})
      >[];
  Object? replyError;
  @override
  Stream<List<Map<String, dynamic>>> changes(String room) async* {
    yield [];
    yield* updates.stream;
  }

  void notify() => updates.add([]);
  Future<void> dispose() => updates.close();
  @override
  Future<List<ChatMessage>> history(
    String room, {
    ChatMessage? before,
    String? anchor,
  }) async {
    historyRequests.add((before: before?.id, anchor: anchor));
    return super.history(room, before: before, anchor: anchor);
  }

  @override
  Future<ChatInteractions> interactions(
    String room,
    List<String> messages,
  ) async =>
      ChatInteractions(pins: List.of(pins), reactions: Map.of(reactions));
  @override
  Future<void> react(
    String room,
    String message,
    String emoji,
    bool selected,
    String actor,
  ) async {
    final before = reactions[message]
        ?.where((r) => r.emoji == emoji)
        .firstOrNull;
    final count = (before?.count ?? 0) + (selected ? 1 : -1);
    reactions[message] = [if (count > 0) ChatReaction(emoji, count, selected)];
    notify();
  }

  @override
  Future<void> setPinned(
    String room,
    String message,
    bool pinned,
    String actor,
  ) async {
    pins.removeWhere((p) => p['message_id'] == message);
    if (pinned)
      pins.add({
        'message_id': message,
        'author_name': 'Анна',
        'body': 'Фрагмент $message',
      });
    notify();
  }

  @override
  Future<void> sendReply({
    required String room,
    required String body,
    required String replyTo,
    required String nonce,
    required String actor,
  }) async {
    replies.add((
      room: room,
      body: body,
      parent: replyTo,
      nonce: nonce,
      actor: actor,
    ));
    if (replyError != null) throw replyError!;
  }
}

Future<void> menu(WidgetTester tester, String body, String action) async {
  await tester.longPress(find.text(body));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'member adds a reaction; remote count appears; own reaction toggles off',
    (tester) async {
      final repo = InteractionFixture();
      addTearDown(repo.dispose);
      await harness.mount(tester, repo);
      await menu(tester, 'Чужой текст', 'Добавить реакцию');
      await tester.tap(find.byKey(const ValueKey('emoji-😀')));
      await tester.pumpAndSettle();
      expect(find.text('😀 1'), findsOneWidget);
      repo.reactions['foreign'] = [const ChatReaction('😀', 2, true)];
      repo.notify();
      await tester.pumpAndSettle();
      expect(find.text('😀 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reaction-foreign-😀')));
      await tester.pumpAndSettle();
      expect(repo.reactions['foreign']!.single.mine, isFalse);
      expect(find.text('😀 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reply composer sends the selected parent and retains nonce on a failed retry',
    (tester) async {
      final repo = InteractionFixture()..replyError = StateError('offline');
      addTearDown(repo.dispose);
      await harness.mount(tester, repo);
      await menu(tester, 'Чужой текст', 'Ответить');
      expect(find.byKey(const ValueKey('cancel-chat-reply')), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Спасибо');
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      final nonce = repo.replies.single.nonce;
      expect(repo.replies.single.parent, 'foreign');
      expect(find.byKey(const ValueKey('cancel-chat-reply')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-send-error')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byTooltip('Отправить').hitTestable(), findsOneWidget);
      repo.replyError = null;
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(repo.replies, hasLength(2));
      expect(repo.replies.last.nonce, nonce);
      expect(repo.replies.last.body, 'Спасибо');
      expect(find.byKey(const ValueKey('cancel-chat-reply')), findsNothing);
      expect(find.byKey(const ValueKey('chat-send-error')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'several pins switch independently; unpin removes just the selected message',
    (tester) async {
      final repo = InteractionFixture();
      addTearDown(repo.dispose);
      await harness.mount(tester, repo);
      await menu(tester, 'Чужой текст', 'Закрепить');
      await menu(tester, 'Мой текст', 'Закрепить');
      expect(repo.pins.length, 2);
      expect(find.text('1/2'), findsOneWidget);
      await tester.tap(find.byTooltip('Следующее закреплённое сообщение'));
      await tester.pumpAndSettle();
      expect(find.text('2/2'), findsOneWidget);
      await menu(tester, 'Мой текст', 'Открепить');
      expect(repo.pins.single['message_id'], 'foreign');
      expect(find.byTooltip('Следующее закреплённое сообщение'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'reply to older history loads the parent and highlights it briefly',
    (tester) async {
      final repo = InteractionFixture();
      addTearDown(repo.dispose);
      repo.historyRows = [
        ChatMessage(
          id: 'parent',
          authorId: 'other',
          authorName: 'Анна',
          body: 'Исходное сообщение',
          createdAt: DateTime(2025),
        ),
      ];
      await harness.mount(
        tester,
        repo,
        messages: () => Stream.value([
          ChatMessage(
            id: 'answer',
            authorId: 'me',
            body: 'Ответ',
            createdAt: DateTime(2026),
            reply: const MessageReply(
              id: 'parent',
              author: 'Анна',
              excerpt: 'Исходное сообщение',
            ),
          ),
        ]),
      );
      await tester.tap(find.byKey(const ValueKey('reply-parent')));
      await tester.pumpAndSettle();
      expect(repo.anchorRequested, 'parent');
      expect(repo.historyRequests, [(before: null, anchor: 'parent')]);
      expect(find.text('Исходное сообщение'), findsOneWidget);
      final box = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('message-highlight-parent')),
      );
      expect(
        (box.decoration! as BoxDecoration).color,
        isNot(Colors.transparent),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      final faded = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('message-highlight-parent')),
      );
      expect((faded.decoration! as BoxDecoration).color, Colors.transparent);
      // A real server update must still refresh the open history window.
      repo.notify();
      await tester.pumpAndSettle();
      expect(repo.historyRequests, [
        (before: null, anchor: 'parent'),
        (before: null, anchor: 'parent'),
      ]);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'scrolling up shows jump button and counts only new incoming messages',
    (tester) async {
      final repo = InteractionFixture();
      addTearDown(repo.dispose);
      final messages = StreamController<List<ChatMessage>>();
      addTearDown(messages.close);
      final rows = List.generate(
        35,
        (i) => ChatMessage(
          id: 'm$i',
          authorId: 'other',
          body: 'Сообщение $i',
          createdAt: DateTime(2026, 1, 2, 12, 35 - i),
        ),
      );
      await harness.mount(tester, repo, messages: () => messages.stream);
      messages.add(rows);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-scroll-down')), findsNothing);
      await tester.drag(
        find.byKey(const ValueKey('chat-timeline-room')),
        const Offset(0, 500),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-scroll-down')), findsOneWidget);
      messages.add([
        ChatMessage(
          id: 'new',
          authorId: 'other',
          body: 'Новое сообщение',
          createdAt: DateTime(2026, 1, 2, 13),
        ),
        ...rows,
      ]);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(Badge), matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('chat-scroll-down')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('chat-scroll-down')), findsNothing);
      expect(find.text('Новое сообщение'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  test('reply and reaction projection parses author, deletion and counts', () {
    final reply = MessageReply.fromJson({
      'id': 'p',
      'author_name': 'Анна',
      'body': 'Сообщение удалено',
      'deleted': true,
    });
    expect(reply.deleted, isTrue);
    expect(reply.author, 'Анна');
    final state = ChatInteractions.fromJson({
      'pins': <Map<String, dynamic>>[],
      'reactions': [
        {'message_id': 'm', 'emoji': '👍', 'count': 3, 'mine': true},
      ],
    });
    expect(state.reactions['m']!.single.count, 3);
    expect(state.reactions['m']!.single.mine, isTrue);
  });
}
