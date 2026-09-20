import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';
import 'package:moy_prihod/design_system/components/chat_surface.dart';
import 'package:moy_prihod/design_system/components/record_card.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/presentation/moderated_timeline.dart';
import 'package:moy_prihod/features/feed/domain/post.dart';
import 'package:moy_prihod/features/feed/presentation/feed_page.dart';

import 'community_chat_test.dart' as chat;
import 'design_navigation_test.dart' show mountApp, RecordingFeed;
import 'support/fake_chat_moderation.dart';

class LongFeed extends RecordingFeed {
  @override
  Future<CursorPage<Post>> page({
    String? parishId,
    PageCursor? before,
  }) async => CursorPage(
    items: [
      for (var i = 0; i < 60; i++)
        Post(
          id: 'post-$i',
          parishId: 'parish',
          title: 'Публикация $i',
          body: 'Текст публикации $i. Приглашаем на встречу молодёжного клуба.',
          publishedAt: DateTime(2026, 9, 19),
        ),
    ],
  );
}

void phone(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
}

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'photo edge is narrow and a single outlined collapse control works at $width',
      (tester) async {
        phone(tester, width: width);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RecordCard(
                  title: 'Встреча клуба',
                  body: List.filled(12, 'Приглашаем на встречу.').join(' '),
                  category: 'Встреча',
                  icon: Icons.groups_outlined,
                  photo: const ColoredBox(
                    key: ValueKey('photo'),
                    color: Colors.blue,
                  ),
                ),
              ),
            ),
          ),
        );
        final photo = find.byKey(const ValueKey('photo'));
        final edge = find.byKey(const ValueKey('publication-photo-edge'));
        expect(
          tester.getSize(edge).width / tester.getSize(photo).width,
          closeTo(.10, .001),
        );
        expect(find.byType(BackdropFilter), findsNothing);
        final rect = tester.getRect(photo);
        await tester.tap(find.text('Подробнее'));
        await tester.pumpAndSettle();
        expect(tester.getRect(photo), rect);
        expect(find.text('Подробнее'), findsNothing);
        expect(find.text('Свернуть'), findsOneWidget);
        final collapse = find.byKey(const ValueKey('publication-collapse'));
        final button = tester.widget<OutlinedButton>(collapse);
        expect(button.style!.shape!.resolve({}), isA<StadiumBorder>());
        expect(button.style!.side!.resolve({})!.color, const Color(0xff9673c7));
        await tester.ensureVisible(collapse);
        await tester.pumpAndSettle();
        await tester.tap(collapse);
        await tester.pumpAndSettle();
        expect(find.text('Свернуть'), findsNothing);
        expect(find.text('Подробнее'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real shell extends the feed behind a translucent safe-area navigation bar',
    (tester) async {
      phone(tester);
      await mountApp(tester, LongFeed());
      final feed = find.byType(FeedPage).first;
      final list = find
          .descendant(of: feed, matching: find.byType(ListView))
          .first;
      final surface = find.byKey(const ValueKey('floating-navigation-surface'));
      expect(tester.widget<Material>(surface).color!.a, lessThan(.5));
      expect(
        tester.getRect(list).bottom,
        greaterThan(tester.getRect(surface).top),
      );
      expect(tester.getRect(surface).bottom, lessThanOrEqualTo(844 - 34));
      expect(find.byType(RecordCard).evaluate().length, lessThan(60));
      await tester.fling(list, const Offset(0, -900), 1800);
      await tester.pumpAndSettle();
      final position = tester.widget<ListView>(list).controller!.position;
      expect(position.pixels, greaterThan(100));
      expect(find.byType(RecordCard).evaluate().length, lessThan(60));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chat builds visible rows and keeps older-history navigation functional',
    (tester) async {
      phone(tester);
      final repo = FakeChatModeration();
      final messages = [
        for (var i = 0; i < 50; i++)
          ChatMessage(
            id: 'm-$i',
            authorId: 'me',
            body: 'Сообщение $i',
            createdAt: DateTime(2026, 9, 19, 12).subtract(Duration(minutes: i)),
          ),
      ];
      repo.historyRows = [
        ChatMessage(
          id: 'older',
          authorId: 'me',
          body: 'Старое сообщение',
          createdAt: DateTime(2026, 9, 18),
        ),
      ];
      await chat.mount(tester, repo, messages: () => Stream.value(messages));
      final timeline = find.byType(ModeratedTimeline);
      final list = find.descendant(
        of: timeline,
        matching: find.byType(ListView),
      );
      expect(list, findsOneWidget);
      expect(find.byType(ChatMessageCard).evaluate().length, lessThan(50));
      expect(find.text('Сообщение 0'), findsOneWidget);
      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Более ранние сообщения'),
        400,
        scrollable: scrollable,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Более ранние сообщения'));
      await tester.pumpAndSettle();
      expect(repo.beforeRequested!.id, messages.last.id);
      expect(find.text('Старое сообщение'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
