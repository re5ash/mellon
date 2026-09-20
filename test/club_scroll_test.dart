import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/community/community_widgets.dart';

import 'club_dashboard_test.dart' show RecordingClubChats, dashboardFixture;

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<RecordingClubChats> mountClub(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  TargetPlatform platform = TargetPlatform.iOS,
  bool reducedMotion = false,
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final data = dashboardFixture();
  final template = (data['chats'] as List<dynamic>).first as JsonRow;
  data['chats'] = [
    for (var index = 0; index < 18; index++)
      <String, dynamic>{
        ...template,
        'id': 'room-$index',
        'title': 'Чат клуба ${index + 1}',
        'sort_order': index + 1,
      },
  ];
  final repo = RecordingClubChats(data);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('actor')),
        ),
        communityRepositoryProvider.overrideWithValue(repo),
        clubDashboardProvider('club-a').overrideWith((ref) async => repo.data),
        chatRoomProvider('room-10').overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: CommunityScaffold(
          title: 'Mellon',
          maxWidth: 1200,
          protectSession: false,
          children: [ClubDashboard(club: 'club-a', onChooseClub: () {})],
        ),
      ),
    ),
  );
  await settle(tester);
  return repo;
}

ScrollPosition pagePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      'dragging the chat list down and back restores the club header: $platform',
      (tester) async {
        final repo = await mountClub(tester, platform: platform);
        expect(find.byType(Scrollable), findsOneWidget);
        final page = find.byType(SingleChildScrollView);
        final header = find.byType(ClubIdentity);
        final originalHeader = tester.getRect(header);
        final position = pagePosition(tester);
        await tester.drag(page, const Offset(0, -600));
        await settle(tester);
        await tester.drag(page, const Offset(0, -400));
        await settle(tester);
        expect(position.pixels, greaterThan(500));
        expect(tester.getRect(header).bottom, lessThan(originalHeader.top));

        // A background update must not replace the scrollable or reset its offset.
        final offset = position.pixels;
        ((repo.data['chats'] as List<dynamic>).first
                as JsonRow)['unread_count'] =
            3;
        ProviderScope.containerOf(
          tester.element(find.byType(ClubDashboard)),
        ).invalidate(clubDashboardProvider('club-a'));
        await settle(tester);
        expect(pagePosition(tester).pixels, closeTo(position.pixels, 1));
        expect(position.pixels, closeTo(offset, 1));

        for (var swipe = 0; swipe < 8 && position.pixels > 1; swipe++) {
          await tester.drag(page, const Offset(0, 500));
          await settle(tester);
        }
        expect(position.pixels, closeTo(0, 1));
        expect(tester.getRect(header).top, closeTo(originalHeader.top, 1));
        expect(find.byType(Scrollable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets(
      'returning from a deep chat restores the same list position; reduced motion: $reduced',
      (tester) async {
        await mountClub(tester, reducedMotion: reduced);
        final room = find.byKey(const ValueKey('club-chat-room-10'));
        await tester.ensureVisible(room);
        await settle(tester);
        final position = pagePosition(tester);
        final offset = position.pixels;
        expect(offset, greaterThan(500));
        final route = ModalRoute.of(tester.element(find.byType(ClubDashboard)));
        await tester.tap(room);
        await settle(tester);
        expect(find.byType(ChatPage), findsOneWidget);
        expect(
          ModalRoute.of(tester.element(find.byType(ChatPage))),
          isNot(same(route)),
        );
        final back = find.byTooltip('К списку чатов');
        await tester.ensureVisible(back);
        await settle(tester);
        await tester.tap(back);
        await settle(tester);
        expect(find.byType(ChatPage), findsNothing);
        expect(pagePosition(tester).pixels, closeTo(position.pixels, 1));
        expect(position.pixels, closeTo(offset, 1));
        expect(find.byType(Scrollable), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'narrow enlarged text still allows returning all the way to the card',
    (tester) async {
      await mountClub(tester, size: const Size(320, 640), scale: 1.8);
      final page = find.byType(SingleChildScrollView);
      final top = tester.getTopLeft(find.byType(ClubIdentity)).dy;
      await tester.drag(page, const Offset(0, -550));
      await settle(tester);
      for (
        var swipe = 0;
        swipe < 6 && pagePosition(tester).pixels > 1;
        swipe++
      ) {
        await tester.drag(page, const Offset(0, 450));
        await settle(tester);
      }
      expect(tester.getTopLeft(find.byType(ClubIdentity)).dy, closeTo(top, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop list scroll stays independent from the club card', (
    tester,
  ) async {
    await mountClub(tester, size: const Size(1280, 1000));
    final list = find.byKey(const PageStorageKey('club-chat-list'));
    await tester.ensureVisible(list);
    final top = tester.getTopLeft(find.byType(ClubIdentity));
    final outer = pagePosition(tester).pixels;
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -400));
    await settle(tester);
    expect(controller.offset, greaterThan(100));
    expect(pagePosition(tester).pixels, closeTo(outer, 1));
    expect(tester.getTopLeft(find.byType(ClubIdentity)), top);
    expect(tester.takeException(), isNull);
  });
}
