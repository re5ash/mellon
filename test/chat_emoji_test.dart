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
import 'package:moy_prihod/features/chats/domain/chat_repository.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/chats/presentation/emoji_catalog.dart';
import 'package:moy_prihod/features/chats/presentation/emoji_input.dart';

import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

class EmojiSender implements ChatRepository {
  final sent = <(String, String)>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<void> send({
    required String roomId,
    required String body,
    required String nonce,
  }) async {
    sent.add((roomId, body));
  }
}

Future<EmojiSender> mountEmojiChat(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool canSend = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final sender = EmojiSender();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('me')),
        ),
        chatRepositoryProvider.overrideWithValue(sender),
        chatModerationProvider.overrideWithValue(FakeChatModeration()),
        chatReadStoreProvider.overrideWithValue(FakeChatReads()),
        chatRoomProvider('room').overrideWith(
          (ref) async =>
              const ChatRoom(id: 'room', title: 'Болталка', kind: 'group'),
        ),
        chatAccessProvider('room')
            .overrideWith((ref) => Stream.value({'send': canSend})),
        chatMessagesProvider('room')
            .overrideWith((ref) => Stream.value(<ChatMessage>[])),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const ChatPage(roomId: 'room'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sender;
}

void main() {
  test(
    'catalog includes every Unicode 17 entry with no duplicate sequences',
    () {
      final values = chatEmojiGroups
          .expand((group) => group.emojis)
          .map((emoji) => emoji.value)
          .toSet();
      expect(values.length, chatEmojiCount);
      expect(chatEmojiCount, 3953);
      expect(chatEmojiGroups.length, 10);
      expect(
        values,
        containsAll([
          '😀',
          '🙏',
          '🙏🏽',
          '👨‍👩‍👧‍👦',
          '🇷🇺',
          '🫪',
          '🧑🏾‍⚕️',
        ]),
      );
    },
  );

  test(
    'inserts compound emoji at UTF-16 selection and replaces selected text',
    () {
      const family = '👨‍👩‍👧‍👦';
      const value = TextEditingValue(
        text: 'Привет мир',
        selection: TextSelection(baseOffset: 7, extentOffset: 10),
      );
      final inserted = insertChatEmoji(value, family);
      expect(inserted.text, 'Привет $family');
      expect(inserted.selection.baseOffset, 7 + family.length);
      expect(insertChatEmoji(inserted, '🙏🏽').text, 'Привет $family🙏🏽');
      expect(
        insertChatEmoji(const TextEditingValue(text: 'Да'), '😀').text,
        'Да😀',
      );
    },
  );

  test('message limit counts compound emoji as one character', () {
    final almostFull = TextEditingValue(text: List.filled(3999, 'а').join());
    final full = insertChatEmoji(almostFull, '👨‍👩‍👧‍👦');
    expect(full.text.characters.length, 4000);
    expect(insertChatEmoji(full, '😀'), full);
  });

  testWidgets(
    'picker keeps composer in place, inserts repeatedly and sends the emoji text',
    (tester) async {
      final sender = await mountEmojiChat(tester);
      final input = find.byKey(const ValueKey('chat-message-input'));
      await tester.enterText(input, 'Привет мир');
      final controller = tester.widget<TextField>(input).controller!;
      controller.selection = const TextSelection.collapsed(offset: 7);
      final before = tester.getRect(input);
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      expect(tester.getRect(input), before);
      final emoji = find.byKey(const ValueKey('emoji-😀'));
      await tester.tap(emoji);
      await tester.tap(emoji);
      await tester.pump();
      expect(controller.text, 'Привет 😀😀мир');
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();
      expect(sender.sent, [('room', 'Привет 😀😀мир')]);
      expect(controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picker fits a narrow screen with enlarged text and searches Russian names',
    (tester) async {
      await mountEmojiChat(tester, size: const Size(320, 640), scale: 1.8);
      await tester.tap(find.byTooltip('Эмодзи'));
      await tester.pumpAndSettle();
      final rect = tester.getRect(
        find.byKey(const ValueKey('chat-emoji-picker')),
      );
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(640));
      await tester.enterText(
        find.byKey(const ValueKey('emoji-search')),
        'сердце',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emoji-❤️')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read-only chat does not offer emoji sending', (tester) async {
    await mountEmojiChat(tester, canSend: false);
    expect(find.byTooltip('Эмодзи'), findsNothing);
    expect(find.byTooltip('Отправить'), findsNothing);
  });
}
