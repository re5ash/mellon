import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/design_system/components/chat_surface.dart';
import 'package:moy_prihod/features/chats/presentation/chat_dates.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';

import 'club_scroll_test.dart' show mountClub, pagePosition, settle;

void main() {
  test('local calendar labels use time, yesterday, weekday and date', () {
    final now = DateTime(2026, 9, 13, 20);
    expect(chatListTimestamp(DateTime(2026, 9, 13, 9, 4), now: now), '09:04');
    expect(chatListTimestamp(DateTime(2026, 9, 12, 23, 59), now: now), 'Вчера');
    expect(chatListTimestamp(DateTime(2026, 9, 11), now: now), 'Пт');
    expect(chatListTimestamp(DateTime(2026, 8, 31), now: now), '31.08');
    expect(chatListTimestamp(DateTime(2025, 9, 1), now: now), '01.09.2025');
    expect(chatListTimestamp(null, now: now), '');
    expect(chatDayLabel(now, now: now), 'Сегодня');
    expect(chatDayLabel(DateTime(2026, 9, 12), now: now), 'Вчера');
    expect(chatDayLabel(DateTime(2025, 9, 1), now: now), '1 сентября 2025');
    expect(
      sameChatDay(DateTime(2026, 9, 13), DateTime(2026, 9, 13, 23)),
      isTrue,
    );
    expect(sameChatDay(DateTime(2026, 9, 13), DateTime(2026, 9, 14)), isFalse);
  });

  testWidgets('deep club chat returns to its original scroll after a swipe', (
    tester,
  ) async {
    await mountClub(tester);
    final room = find.byKey(const ValueKey('club-chat-room-10'));
    await tester.ensureVisible(room);
    await settle(tester);
    final position = pagePosition(tester);
    final saved = position.pixels;
    final route = ModalRoute.of(tester.element(find.byType(ClubDashboard)));
    await tester.tap(room);
    await settle(tester);
    await tester.ensureVisible(find.byTooltip('К списку чатов'));
    await settle(tester);
    final rect = tester.getRect(find.byType(ChatPage));
    await tester.dragFrom(
      rect.topLeft + const Offset(2, 110),
      Offset(rect.width * .65, 0),
    );
    await settle(tester);
    expect(find.byType(ChatPage), findsNothing);
    expect(pagePosition(tester).pixels, closeTo(position.pixels, 1));
    expect(position.pixels, closeTo(saved, 1));
    expect(find.byType(Scrollable), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(ClubDashboard))),
      same(route),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'chat directory has no ordinal numbers and places time on the right',
    (tester) async {
      final repo = await mountClub(tester);
      final row = find.byKey(const ValueKey('club-chat-room-0'));
      await tester.ensureVisible(row);
      await settle(tester);
      expect(find.descendant(of: row, matching: find.text('1')), findsNothing);
      expect(
        find.descendant(of: row, matching: find.text('12')),
        findsOneWidget,
      );
      final data =
          (repo.data['chats'] as List<dynamic>).first as Map<String, dynamic>;
      final label = chatListTimestamp(
        DateTime.parse(data['last_message_at'] as String),
      );
      final time = find.descendant(of: row, matching: find.text(label));
      expect(time, findsOneWidget);
      expect(
        tester.getTopLeft(time).dx,
        greaterThan(tester.getTopLeft(find.text('Чат клуба 1')).dx),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact bubbles wrap long text at 320px with enlarged fonts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final body =
        'Длинное сообщение с переносами\n${List.filled(10, 'ОченьДлинноеСлово').join()}\nДобрый вечер 👋';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  ChatMessageCard(
                    settings: const AppearanceSettings(),
                    body: body,
                    author: 'Александра Владимировна',
                    time: '19:37',
                    outgoing: false,
                  ),
                  const ChatMessageCard(
                    settings: AppearanceSettings(),
                    body: 'Да',
                    author: 'Вы',
                    time: '19:38',
                    outgoing: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text(body), findsOneWidget);
    expect(find.text('19:37'), findsOneWidget);
    expect(find.text('19:38'), findsOneWidget);
    expect(find.text('Вы'), findsNothing);
    for (final time in ['19:37', '19:38']) {
      final bounds = tester.getRect(find.text(time));
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(320));
    }
    expect(tester.takeException(), isNull);
  });
}
