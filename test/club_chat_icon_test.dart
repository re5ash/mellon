import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/chats/presentation/chat_icon_badge.dart';

import 'club_dashboard_test.dart' as club;

void main() {
  testWidgets(
    'administrator commits the icon key and shared badge updates; cancel writes nothing',
    (tester) async {
      final repo = club.RecordingClubChats(
        club.dashboardFixture(manager: true),
      );
      await club.mountDashboard(tester, repo);
      Future<void> picker() async {
        await club.tapVisible(
          tester,
          find.byTooltip('Управление чатом «Болталка»'),
        );
        await club.tapVisible(tester, find.text('Изменить иконку'));
      }

      await picker();
      await tester.tap(find.byKey(const ValueKey('chat-icon-chat_4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(repo.requests, isEmpty);
      await picker();
      await tester.tap(find.byKey(const ValueKey('chat-icon-chat_4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(repo.requests.single.$1, 'edit_club_chat_meta');
      expect(repo.requests.single.$2, {
        'p_youth': 'club-a',
        'p_room': 'room-0',
        'p_title': null,
        'p_icon': 'chat_4',
        'p_revision': 7,
        'p_expected_user': 'actor',
      });
      final icon = find.descendant(
        of: find.byKey(const ValueKey('club-chat-room-0')),
        matching: find.byType(ChatIconBadge),
      );
      expect(tester.widget<ChatIconBadge>(icon).iconKey, 'chat_4');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('ordinary participant has no chat management menu', (
    tester,
  ) async {
    final repo = club.RecordingClubChats(club.dashboardFixture());
    await club.mountDashboard(tester, repo);
    expect(find.byTooltip('Управление чатом «Болталка»'), findsNothing);
    expect(repo.requests, isEmpty);
  });
}
