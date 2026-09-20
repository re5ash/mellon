import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/feed/application/feed_providers.dart';
import 'package:moy_prihod/features/feed/domain/feed_repository.dart';
import 'package:moy_prihod/features/feed/domain/post.dart';

import 'club_dashboard_test.dart' as fixtures;

class RefreshCommunity implements CommunityRepository {
  final data = fixtures.dashboardFixture(manager: true);
  int reads = 0;
  Completer<JsonRow>? pending;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<dynamic> call(String name, [JsonRow params = const {}]) async {
    if (name != 'club_dashboard') throw StateError('Unexpected RPC: $name');
    reads++;
    final response = pending;
    return response == null ? data : await response.future;
  }
}

class RefreshFeed implements FeedRepository {
  int reads = 0;
  @override
  Future<CursorPage<Post>> page({String? parishId, PageCursor? before}) async {
    reads++;
    return const CursorPage(items: []);
  }
}

class RefreshFixture {
  final community = RefreshCommunity();
  final feed = RefreshFeed();
  final users = StreamController<AppUser?>.broadcast();
  final access = StreamController<AccountAccess>.broadcast();
  final scroll = ScrollController();
  final actor = 'actor';

  Future<void> dispose() async {
    scroll.dispose();
    await users.close();
    await access.close();
  }
}

Future<void> settleRefresh(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<RefreshFixture> mountRefresh(WidgetTester tester) async {
  final fixture = RefreshFixture();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) async* {
          yield AppUser(fixture.actor);
          yield* fixture.users.stream;
        }),
        accountAccessProvider.overrideWith((ref) async* {
          yield const AccountAccess(superAdmin: true);
          yield* fixture.access.stream;
        }),
        communityRepositoryProvider.overrideWithValue(fixture.community),
        feedRepositoryProvider.overrideWithValue(fixture.feed),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, child) {
            ref.watch(feedPageProvider((parishId: null, before: null)));
            return Scaffold(
              body: SingleChildScrollView(
                controller: fixture.scroll,
                child: ClubDashboard(club: 'club-a', onChooseClub: () {}),
              ),
            );
          },
        ),
      ),
    ),
  );
  await settleRefresh(tester);
  return fixture;
}

Future<void> pollAccess(WidgetTester tester, RefreshFixture fixture) async {
  // New server response with the same global flags; club rights may differ.
  fixture.access.add(AccountAccess(superAdmin: fixture.actor.isNotEmpty));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets(
    'background checks preserve the chat list and scroll but update club rights',
    (tester) async {
      final fixture = await mountRefresh(tester);
      expect(find.byTooltip('Поиск чата'), findsNothing);
      await tester.ensureVisible(find.text('Полезные материалы'));
      await settleRefresh(tester);
      final offset = fixture.scroll.offset;
      final loads = fixture.community.reads;
      final feedLoads = fixture.feed.reads;
      final response = Completer<JsonRow>();
      fixture.community.pending = response;

      await pollAccess(tester, fixture);
      expect(fixture.community.reads, loads + 1);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Полезные материалы'), findsOneWidget);
      expect(find.text('Болталка'), findsOneWidget);
      expect(find.byKey(const ValueKey('club-chat-search')), findsNothing);
      expect(fixture.scroll.offset, closeTo(offset, 0.5));

      // The same global access can now correspond to a demoted club member.
      response.complete({
        ...fixture.community.data,
        'can_create_chats': false,
        'can_manage_chats': false,
      });
      await settleRefresh(tester);
      expect(find.byKey(const ValueKey('add-club-chat')), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.text('Болталка'), findsOneWidget);
      expect(find.text('Полезные материалы'), findsOneWidget);
      expect(fixture.scroll.offset, closeTo(offset, 0.5));

      final afterPoll = fixture.community.reads;
      fixture.users.add(AppUser(fixture.actor));
      await settleRefresh(tester);
      expect(fixture.community.reads, afterPoll);
      expect(fixture.feed.reads, feedLoads);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a denied background request removes the previous club content', (
    tester,
  ) async {
    final fixture = await mountRefresh(tester);
    final response = Completer<JsonRow>();
    fixture.community.pending = response;
    await pollAccess(tester, fixture);
    expect(find.text('Болталка'), findsOneWidget);
    response.completeError(const AppFailure('Доступ к клубу отозван.'));
    await settleRefresh(tester);
    expect(find.text('Доступ к клубу отозван.'), findsOneWidget);
    expect(find.text('Болталка'), findsNothing);
    expect(find.text('Повторить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account switch clears old content and ignores its late response',
    (tester) async {
      final fixture = await mountRefresh(tester);
      final oldResponse = Completer<JsonRow>();
      fixture.community.pending = oldResponse;
      await pollAccess(tester, fixture);
      final newResponse = Completer<JsonRow>();
      fixture.community.pending = newResponse;
      final callsBeforeSwitch = fixture.community.reads;
      fixture.users.add(const AppUser('other-account'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fixture.community.reads, callsBeforeSwitch + 1);
      expect(find.text('Болталка'), findsNothing);
      oldResponse.complete(fixture.community.data);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Болталка'), findsNothing);

      newResponse.complete({
        ...fixture.community.data,
        'club': {
          ...(fixture.community.data['club'] as JsonRow),
          'name': 'Клуб другого аккаунта',
        },
      });
      await settleRefresh(tester);
      expect(find.text('Клуб другого аккаунта'), findsOneWidget);
      fixture.users.add(null);
      await settleRefresh(tester);
      expect(find.text('Клуб другого аккаунта'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
