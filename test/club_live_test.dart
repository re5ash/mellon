import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/club_directory.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';
import 'package:moy_prihod/features/community/club_settings_dialog.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

import 'club_dashboard_test.dart'
    show RecordingClubChats, dashboardFixture, tapVisible;

class ClubEntryFake implements CommunityRepository {
  int joins = 0, leaves = 0;
  String? status;
  bool approved = false, fail = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  JsonRow get entry => {
    'id': 'club-a',
    'name': 'МК Невского',
    'description': 'Встречи и общение',
    'can_open': approved,
    'request_status': status,
  };
  @override
  Future<dynamic> call(String name, [JsonRow params = const {}]) async {
    if (fail) throw StateError('Нет соединения');
    if (name == 'request_youth_club') {
      joins++;
      status = 'pending';
      return 'request';
    }
    if (name == 'leave_youth_club') {
      leaves++;
      approved = false;
      status = null;
      return null;
    }
    throw StateError(name);
  }
}

void main() {
  testWidgets(
    'application card hides internals; persisted pending status prevents duplicates, rejection replaces pending, approval opens dashboard',
    (tester) async {
      final repo = ClubEntryFake();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
            clubDirectoryProvider.overrideWith((ref) async => [repo.entry]),
            clubEntryProvider('club-a').overrideWith((ref) async => repo.entry),
            clubDashboardProvider(
              'club-a',
            ).overrideWith((ref) async => dashboardFixture()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, child) {
                    ref.watch(authUserProvider);
                    return const ClubDirectory();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('МК Невского'), findsOneWidget);
      expect(find.text('Чаты клуба'), findsNothing);
      await tapVisible(tester, find.text('Подать заявку'));
      expect(repo.joins, 1);
      expect(find.text('Подать заявку'), findsNothing);
      expect(find.text('Заявка отправлена'), findsOneWidget);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(ClubDirectory)),
      );
      scope.invalidate(clubDirectoryProvider);
      await tester.pumpAndSettle();
      expect(find.text('Подать заявку'), findsNothing);
      expect(find.text('Чаты клуба'), findsNothing);
      repo.status = 'rejected';
      scope.invalidate(clubDirectoryProvider);
      await tester.pumpAndSettle();
      expect(find.text('Заявка отправлена'), findsNothing);
      expect(find.text('Заявка отклонена'), findsOneWidget);
      repo.approved = true;
      scope.invalidate(clubDirectoryProvider);
      await tester.pumpAndSettle();
      expect(find.text('Чаты клуба'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leave needs confirmation; cancel and server failure keep membership',
    (tester) async {
      final repo = ClubEntryFake()..approved = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(authUserProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (_) => const ClubSettingsDialog(
                        club: 'club-a',
                        actor: 'actor',
                      ),
                    ),
                    child: const Text('Открыть'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Открыть'));
      await tapVisible(tester, find.text('Покинуть клуб'));
      expect(find.text('Вы точно хотите выйти?'), findsOneWidget);
      await tapVisible(tester, find.text('Отмена'));
      expect(repo.leaves, 0);
      repo.fail = true;
      await tapVisible(tester, find.text('Покинуть клуб'));
      await tapVisible(tester, find.text('Подтвердить'));
      expect(repo.approved, true);
      expect(find.text('Покинуть клуб'), findsOneWidget);
      repo.fail = false;
      await tapVisible(tester, find.text('Покинуть клуб'));
      await tapVisible(tester, find.text('Подтвердить'));
      expect(repo.leaves, 1);
      expect(repo.approved, false);
      expect(find.byType(ClubSettingsDialog), findsNothing);
    },
  );
  testWidgets(
    'chat covers the whole screen and returns to the retained directory',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = RecordingClubChats(dashboardFixture());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
            clubDashboardProvider(
              'club-a',
            ).overrideWith((ref) async => repo.data),
            chatRoomProvider('room-0').overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClubDashboard(club: 'club-a', onChooseClub: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.byType(ClubDashboard)));
      final list = find.byKey(const PageStorageKey('club-chat-list'));
      final controller = tester.widget<ListView>(list).controller;
      await tapVisible(tester, find.text('Болталка'));
      expect(find.byType(ChatPage), findsOneWidget);
      expect(find.text('Полезные материалы'), findsNothing);
      expect(
        tester.getRect(find.byType(ChatPage)),
        const Rect.fromLTWH(0, 0, 1280, 1000),
      );
      expect(
        ModalRoute.of(tester.element(find.byType(ChatPage))),
        isNot(same(route)),
      );
      await tapVisible(tester, find.byTooltip('К списку чатов'));
      expect(find.byType(ChatPage), findsNothing);
      expect(tester.widget<ListView>(list).controller, same(controller));
      expect(tester.takeException(), isNull);
    },
  );
}
