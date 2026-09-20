import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/club_directory.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

JsonRow dashboardFixture({bool manager = false}) => {
  'club': {
    'id': 'club-a',
    'name': 'Молодёжный клуб храма Александра Невского',
    'description': 'Встречи и общение',
    'address': 'улица Киевская, 18',
    'city': 'Калининград',
    'leaders': 'Анна Волкова',
  },
  'can_manage_information': manager,
  'can_create_chats': manager,
  'can_manage_chats': manager,
  'chats': [
    for (var i = 0; i < 2; i++)
      {
        'id': 'room-$i',
        'title': i == 0 ? 'Болталка' : 'Полезные материалы',
        'description': i == 0
            ? 'Свободное общение участников'
            : 'Статьи, ссылки и рекомендации для участников клуба',
        'kind': 'group',
        'icon_key': i == 0 ? 'chat' : 'book',
        'access': 'parish',
        'sort_order': i + 1,
        'revision': 7,
        'unread_count': i == 0 ? 12 : 0,
        'last_message_at': i == 0
            ? DateTime.now().toUtc().toIso8601String()
            : null,
      },
  ],
  'events': [
    {
      'id': 'event',
      'title': 'Воскресная встреча',
      'description': 'Приглашаем на встречу',
      'starts_at': '2030-01-12T12:00:00Z',
      'ends_at': '2030-01-12T13:00:00Z',
      'status': 'published',
      'location_label': 'Зал встреч',
    },
  ],
  'help': [
    {
      'id': 'help',
      'title': 'Помощь на занятиях',
      'description': 'Нужны волонтёры',
      'status': 'published',
    },
  ],
};

// A widget-test fake must not construct a real auth client: its automatic
// refresh timer outlives the widget test's invariant checks.
class RecordingClubChats implements CommunityRepository {
  RecordingClubChats(this.data);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final JsonRow data;
  final requests = <(String, JsonRow)>[];
  Completer<void>? pending;
  Object? error;
  @override
  Future<dynamic> call(String name, [JsonRow params = const {}]) async {
    requests.add((name, Map.of(params)));
    if (pending != null) await pending!.future;
    if (error != null) throw error!;
    final chats = data['chats'] as List<dynamic>;
    if (name == 'delete_club_chat')
      chats.removeWhere((r) => (r as JsonRow)['id'] == params['p_room']);
    if (name == 'edit_club_chat_meta') {
      final row = chats.cast<JsonRow>().singleWhere(
        (r) => r['id'] == params['p_room'],
      );
      if (params['p_title'] != null) row['title'] = params['p_title'];
      if (params['p_icon'] != null) row['icon_key'] = params['p_icon'];
    }
    if (name == 'save_club_chat') {
      final existing = chats
          .where((r) => (r as JsonRow)['id'] == params['p_id'])
          .firstOrNull;
      if (existing != null)
        (existing as JsonRow)['title'] = params['p_title'];
      else
        chats.add({
          'id': params['p_id'],
          'title': params['p_title'],
          'description': params['p_description'],
          'kind': params['p_kind'],
          'icon_key': params['p_icon'],
          'access': 'parish',
          'sort_order': params['p_sort'],
          'revision': 1,
          'unread_count': 0,
        });
    }
    return params['p_id'];
  }
}

Future<void> mountDashboard(
  WidgetTester tester,
  RecordingClubChats repo, {
  double scale = 1,
  bool dark = false,
  Widget? child,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('actor')),
        ),
        communityRepositoryProvider.overrideWithValue(repo),
        clubDashboardProvider('club-a').overrideWith((ref) async => repo.data),
        clubDirectoryProvider.overrideWith(
          (ref) async => [
            {
              'id': 'club-a',
              'name': 'Клуб',
              'description': '',
              'can_open': true,
            },
          ],
        ),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, content) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: content!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            // The dashboard override bypasses the repository's auth dependency.
            // Keep a live subscription and let widget pumps deliver the session.
            ref.watch(authUserProvider);
            return Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      child ??
                      ClubDashboard(club: 'club-a', onChooseClub: () {}),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  final user = container.read(authUserProvider).asData?.value;
  expect(user?.id, 'actor', reason: 'The test must have a signed-in account.');
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

void main() {
  testWidgets(
    'member has four working tabs, real data and no chat search or management controls',
    (tester) async {
      final repo = RecordingClubChats(dashboardFixture());
      await mountDashboard(tester, repo);
      expect(find.text('Чаты клуба'), findsOneWidget);
      expect(find.byKey(const ValueKey('add-club-chat')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.text('12'), findsOneWidget);
      expect(find.byTooltip('Поиск чата'), findsNothing);
      expect(find.byKey(const ValueKey('club-chat-search')), findsNothing);
      expect(find.text('Болталка'), findsOneWidget);
      expect(find.text('Полезные материалы'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('club-tab-1')));
      expect(find.text('Добавить расписание'), findsNothing);
      expect(find.text('Воскресная встреча'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('club-tab-2')));
      expect(find.text('Воскресная встреча'), findsNWidgets(2));
      await tapVisible(tester, find.byKey(const ValueKey('club-tab-3')));
      expect(find.text('Помощь на занятиях'), findsOneWidget);
      expect(repo.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'delete requires confirmation and removes the row only after the server succeeds',
    (tester) async {
      final repo = RecordingClubChats(dashboardFixture(manager: true));
      await mountDashboard(tester, repo);
      final menu = find.byTooltip('Управление чатом «Болталка»');
      await tapVisible(tester, menu);
      await tapVisible(tester, find.text('Удалить чат'));
      expect(repo.requests, isEmpty);
      await tapVisible(tester, find.text('Отмена'));
      expect(find.text('Болталка'), findsOneWidget);
      await tapVisible(tester, menu);
      await tapVisible(tester, find.text('Удалить чат'));
      await tapVisible(tester, find.text('Подтвердить'));
      expect(repo.requests.single.$1, 'delete_club_chat');
      expect(repo.requests.single.$2, {
        'p_youth': 'club-a',
        'p_room': 'room-0',
        'p_revision': 7,
        'p_expected_user': 'actor',
      });
      expect(find.text('Болталка'), findsNothing);
      expect(find.text('Полезные материалы'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'failed deletion keeps chat and shows a useful permission error',
    (tester) async {
      final repo = RecordingClubChats(dashboardFixture(manager: true))
        ..error = const PostgrestException(message: 'forbidden', code: '42501');
      await mountDashboard(tester, repo);
      await tapVisible(tester, find.byTooltip('Управление чатом «Болталка»'));
      await tapVisible(tester, find.text('Удалить чат'));
      await tapVisible(tester, find.text('Подтвердить'));
      expect(find.text('Болталка'), findsOneWidget);
      expect(find.text('Нет доступа к этому действию.'), findsOneWidget);
    },
  );
  testWidgets(
    'rename keeps room identity and blocks repeated submission until completion',
    (tester) async {
      final repo = RecordingClubChats(dashboardFixture(manager: true))
        ..pending = Completer<void>();
      await mountDashboard(tester, repo);
      await tapVisible(tester, find.byTooltip('Управление чатом «Болталка»'));
      await tapVisible(tester, find.text('Переименовать'));
      await tester.enterText(
        find.byKey(const ValueKey('rename-chat-title')),
        'Общение',
      );
      final save = find.byKey(const ValueKey('save-chat-name'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save);
      await tester.pump();
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.$2['p_room'], 'room-0');
      expect(repo.requests.single.$2['p_revision'], 7);
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Общение'), findsOneWidget);
      expect(find.text('Болталка'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('create adds a real chat with a stable ID and selected club', (
    tester,
  ) async {
    final repo = RecordingClubChats(dashboardFixture(manager: true));
    await mountDashboard(tester, repo);
    await tapVisible(tester, find.byKey(const ValueKey('add-club-chat')));
    await tester.enterText(
      find.byKey(const ValueKey('club-chat-title')),
      'Новый чат',
    );
    await tapVisible(tester, find.byKey(const ValueKey('save-club-chat')));
    expect(repo.requests.single.$2['p_youth'], 'club-a');
    expect(repo.requests.single.$2['p_revision'], isNull);
    expect(find.text('Новый чат'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty dashboard does not invent events, messages or unread badges',
    (tester) async {
      final data = dashboardFixture()
        ..['chats'] = <JsonRow>[]
        ..['events'] = <JsonRow>[]
        ..['help'] = <JsonRow>[];
      await mountDashboard(tester, RecordingClubChats(data));
      expect(find.text('Чатов пока нет'), findsOneWidget);
      expect(find.text('События пока не запланированы'), findsOneWidget);
      expect(find.text('12'), findsNothing);
    },
  );
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'dashboard text wraps at $size and large font without overflow',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mountDashboard(
          tester,
          RecordingClubChats(dashboardFixture(manager: true)),
          scale: 1.8,
          dark: size.width == 390,
        );
        for (final i in [0, 1, 2, 3]) {
          await tapVisible(tester, find.byKey(ValueKey('club-tab-$i')));
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
  for (final force in [false, true]) {
    testWidgets(
      'single accessible club opens immediately without chooser after login: $force',
      (tester) async {
        await mountDashboard(
          tester,
          RecordingClubChats(dashboardFixture()),
          child: ClubDirectory(forceSelection: force),
        );
        expect(find.text('Выберите молодёжный клуб'), findsNothing);
        expect(find.text('Чаты клуба'), findsOneWidget);
        expect(find.byKey(const ValueKey('back-to-club-list')), findsNothing);
        expect(find.byTooltip('Обновить клуб'), findsNothing);
        expect(find.text('О храме'), findsOneWidget);
      },
    );
  }
}
