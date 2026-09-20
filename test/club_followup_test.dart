import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/club_directory.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';
import 'package:moy_prihod/features/community/club_live_updates.dart';
import 'package:moy_prihod/features/community/club_selection_store.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'club_dashboard_test.dart' show dashboardFixture, tapVisible;
import 'club_live_test.dart' show ClubEntryFake;

class MemoryClubSelection implements ClubSelectionStore {
  final values = <String, String>{};
  @override
  Future<String?> load(String actor) async => values[actor];
  @override
  Future<void> save(String actor, String club) async {
    values[actor] = club;
  }
}

// Exercises unavailable local storage as well as a failed remote read receipt.
class UnavailableReadPreferences implements SharedPreferencesAsync {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Storage unavailable');
}

class LiveRefreshFixture {
  final updates = StreamController<ClubLiveUpdate>();
  int dashboard = 0, directory = 0, room = 0, access = 0, messages = 0;
  Future<void> dispose() => updates.close();
}

void main() {
  testWidgets(
    'selected club is restored across remounts and isolated by account',
    (tester) async {
      final store = MemoryClubSelection();
      var actor = 'alice';
      final clubs = <JsonRow>[
        {
          'id': 'club-a',
          'name': 'Клуб А',
          'description': '',
          'can_open': false,
        },
        {
          'id': 'club-b',
          'name': 'Клуб Б',
          'description': '',
          'can_open': false,
        },
      ];
      Future<void> mount() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWith(
                (ref) => Stream.value(AppUser(actor)),
              ),
              clubSelectionStoreProvider.overrideWithValue(store),
              clubDirectoryProvider.overrideWith((ref) async => clubs),
              for (final club in clubs)
                clubEntryProvider(
                  club['id'] as String,
                ).overrideWith((ref) async => club),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final user = ref.watch(authUserProvider).asData?.value;
                      return user == null
                          ? const SizedBox.shrink()
                          : ClubDirectory(key: ValueKey(user.id));
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      await tapVisible(tester, find.text('Клуб Б'));
      expect(store.values['alice'], 'club-b');
      expect(find.text('Выберите молодёжный клуб'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await mount();
      expect(find.text('Клуб Б'), findsOneWidget);
      expect(find.text('Клуб А'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ClubIdentity),
          matching: find.text('Подать заявку'),
        ),
        findsOneWidget,
      );
      store.values['bob'] = 'club-a';
      actor = 'bob';
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(ClubDirectory)),
      );
      scope.invalidate(authUserProvider);
      await tester.pumpAndSettle();
      expect(find.text('Клуб А'), findsOneWidget);
      expect(find.text('Клуб Б'), findsNothing);
      expect(store.values['alice'], 'club-b');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'successful leave closes internals while the directory refresh is still pending',
    (tester) async {
      final repo = ClubEntryFake()..approved = true;
      final store = MemoryClubSelection();
      Completer<List<JsonRow>>? refresh;
      final data = dashboardFixture();
      data['club'] = <String, dynamic>{
        ...data['club'] as JsonRow,
        'is_member': true,
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
            clubSelectionStoreProvider.overrideWithValue(store),
            clubDirectoryProvider.overrideWith(
              (ref) async =>
                  refresh == null ? [repo.entry] : await refresh.future,
            ),
            clubEntryProvider('club-a').overrideWith((ref) async => repo.entry),
            clubDashboardProvider('club-a').overrideWith((ref) async => data),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, _) {
                    final actor = ref.watch(authUserProvider).asData?.value?.id;
                    return actor == null
                        ? const SizedBox.shrink()
                        : ClubDirectory(key: ValueKey(actor));
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('Настройки клуба'));
      await tapVisible(tester, find.text('Покинуть клуб'));
      final waiting = Completer<List<JsonRow>>();
      refresh = waiting;
      await tapVisible(tester, find.text('Подтвердить'));
      expect(repo.leaves, 1);
      expect(find.text('Чаты клуба'), findsNothing);
      expect(find.text('Подать заявку'), findsOneWidget);
      waiting.complete([repo.entry]);
      await tester.pumpAndSettle();
      expect(find.byType(ClubDashboard), findsNothing);
      expect(find.text('Подать заявку'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'timed out receipt does not block another chat or poison subsequent retries',
    () async {
      final pending = Completer<void>();
      final calls = <String>[];
      final store = ChatReadStore(
        UnavailableReadPreferences(),
        remoteTimeout: const Duration(milliseconds: 10),
        markRemote: (actor, room, at, message) {
          calls.add(room);
          return calls.length == 1 ? pending.future : Future<void>.value();
        },
      );
      final at = DateTime.utc(2026, 9, 12);
      await expectLater(
        store.mark('alice', 'room-a', at),
        throwsA(isA<TimeoutException>()),
      );
      await store.mark('alice', 'room-b', at);
      await store.mark('alice', 'room-a', at);
      expect(calls, ['room-a', 'room-b', 'room-a']);
      pending.complete();
      final saved = await store.load('alice');
      expect(saved.keys, containsAll(['room-a', 'room-b']));
    },
  );

  testWidgets(
    'read receipts preserve open chat providers; reconnect reloads history and rights',
    (tester) async {
      final fixture = LiveRefreshFixture();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await fixture.dispose();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubLiveUpdatesProvider.overrideWith(
              (ref) => fixture.updates.stream,
            ),
            clubDashboardProvider('club-a').overrideWith((ref) async {
              fixture.dashboard++;
              return <String, dynamic>{};
            }),
            clubDirectoryProvider.overrideWith((ref) async {
              fixture.directory++;
              return <JsonRow>[];
            }),
            chatRoomProvider('room-a').overrideWith((ref) async {
              fixture.room++;
              return null;
            }),
            chatAccessProvider('room-a').overrideWith((ref) {
              fixture.access++;
              return Stream.value(<String, dynamic>{});
            }),
            chatMessagesProvider('room-a').overrideWith((ref) {
              fixture.messages++;
              return Stream.value(<ChatMessage>[]);
            }),
          ],
          child: MaterialApp(
            home: ClubLiveScope(
              child: Consumer(
                builder: (context, ref, _) {
                  ref.watch(clubDashboardProvider('club-a'));
                  ref.watch(clubDirectoryProvider);
                  ref.watch(chatRoomProvider('room-a'));
                  ref.watch(chatAccessProvider('room-a'));
                  ref.watch(chatMessagesProvider('room-a'));
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        [
          fixture.dashboard,
          fixture.directory,
          fixture.room,
          fixture.access,
          fixture.messages,
        ],
        [1, 1, 1, 1, 1],
      );
      fixture.updates.add(
        const ClubLiveUpdate(tables: {'club_chat_reads', 'chat_messages'}),
      );
      await tester.pumpAndSettle();
      expect(
        [
          fixture.dashboard,
          fixture.directory,
          fixture.room,
          fixture.access,
          fixture.messages,
        ],
        [2, 1, 1, 1, 1],
      );
      fixture.updates.add(const ClubLiveUpdate(reconnected: true));
      await tester.pumpAndSettle();
      expect(
        [
          fixture.dashboard,
          fixture.directory,
          fixture.room,
          fixture.access,
          fixture.messages,
        ],
        [3, 2, 2, 2, 2],
      );
      fixture.updates.add(const ClubLiveUpdate(tables: {'youth_memberships'}));
      await tester.pumpAndSettle();
      expect(
        [
          fixture.dashboard,
          fixture.directory,
          fixture.room,
          fixture.access,
          fixture.messages,
        ],
        [4, 3, 3, 3, 2],
      );
      expect(tester.takeException(), isNull);
    },
  );
}
