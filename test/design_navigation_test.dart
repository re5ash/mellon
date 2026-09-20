import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/router/app_router.dart';
import 'package:moy_prihod/app/router/route_access.dart';
import 'package:moy_prihod/app/shell/club_navigation_bar.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/core/access/permission_providers.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/data/club_registration_repository.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/presentation/club_registration_dialog.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/community/club_applications_page.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';
import 'package:moy_prihod/features/community/club_live_updates.dart';
import 'package:moy_prihod/features/community/club_selection_store.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/events/application/events_providers.dart';
import 'package:moy_prihod/features/events/domain/event.dart';
import 'package:moy_prihod/features/events/domain/events_repository.dart';
import 'package:moy_prihod/features/feed/application/feed_providers.dart';
import 'package:moy_prihod/features/feed/domain/feed_repository.dart';
import 'package:moy_prihod/features/feed/domain/post.dart';
import 'package:moy_prihod/features/help/application/help_providers.dart';
import 'package:moy_prihod/features/map/application/map_temples.dart';
import 'package:moy_prihod/features/membership/application/membership_providers.dart';
import 'package:moy_prihod/features/membership/domain/membership.dart';
import 'package:moy_prihod/features/notifications/application/notification_providers.dart';
import 'package:moy_prihod/features/notifications/domain/app_notification.dart';
import 'package:moy_prihod/features/parishes/application/parish_providers.dart';
import 'package:moy_prihod/features/parishes/domain/parish.dart';

const parishId = '20000000-0000-0000-0000-000000000001';

class RecordingFeed implements FeedRepository {
  final requests = <String?>[];
  @override
  Future<CursorPage<Post>> page({String? parishId, PageCursor? before}) async {
    requests.add(parishId);
    return const CursorPage(items: []);
  }
}

class RecordingEvents implements ParishEventRepository {
  final requests = <String?>[];
  @override
  Future<List<ParishEvent>> list({String? parishId}) async {
    requests.add(parishId);
    return [];
  }
}

Future<GoRouter> mountApp(
  WidgetTester tester,
  RecordingFeed feed, {
  bool signedIn = false,
  bool admin = false,
  Stream<AccountAccess>? accessStream,
  Stream<List<AppNotification>>? inboxStream,
  String? membershipStatus,
  double scale = 1,
  bool dark = false,
}) async {
  final club = <String, dynamic>{
    'id': 'club-a',
    'parish_id': parishId,
    'name': 'Молодёжный клуб для проверки',
    'description': '',
    'city_name': 'Город',
    'can_open': membershipStatus == 'active',
    'request_status': membershipStatus == 'pending' ? 'pending' : null,
  };
  final container = ProviderContainer(
    overrides: [
      mapTemplesProvider.overrideWith((ref) async => const <Parish>[]),
      notificationsProvider.overrideWith(
        (ref) => inboxStream ?? Stream.value(const <AppNotification>[]),
      ),
      clubLiveUpdatesProvider.overrideWith(
        (ref) => const Stream<ClubLiveUpdate>.empty(),
      ),
      accountAccessProvider.overrideWith(
        (ref) =>
            accessStream ??
            Stream.value(
              AccountAccess(superAdmin: admin, canManageRoles: admin),
            ),
      ),
      clubWorkspacesProvider.overrideWith((ref) async => []),
      clubDirectoryProvider.overrideWith((ref) async => [club]),
      clubEntryProvider('club-a').overrideWith((ref) async => club),
      savedClubSelectionProvider(
        'design-user',
      ).overrideWith((ref) async => null),
      clubDashboardProvider('club-a').overrideWith(
        (ref) async => {
          'club': club,
          'chats': <JsonRow>[],
          'events': <JsonRow>[],
          'schedule': <JsonRow>[],
          'help': <JsonRow>[],
          'can_manage_information': false,
          'can_manage_chats': false,
          'can_create_chats': false,
        },
      ),
      clubChoicesProvider.overrideWith((ref) async => []),
      myClubApplicationsProvider.overrideWith((ref) async => []),
      appConfigurationProvider.overrideWith(
        (ref) async => {
          'app_name': 'Мой приход',
          'welcome_text': '',
          'support_email': '',
        },
      ),
      authUserProvider.overrideWith(
        (ref) => Stream.value(signedIn ? const AppUser('design-user') : null),
      ),
      currentMembershipProvider.overrideWith(
        (ref) async => membershipStatus == null
            ? null
            : Membership(
                id: 'membership',
                parishId: parishId,
                status: membershipStatus,
              ),
      ),
      permissionsProvider(
        null,
      ).overrideWith((ref) async => admin ? {'parishes.manage'} : <String>{}),
      permissionsProvider(parishId).overrideWith((ref) async => <String>{}),
      myYouthProvider.overrideWith((ref) async => []),
      scopePermissionsProvider((
        parish: null,
        youth: null,
      )).overrideWith((ref) async => <String>{}),
      scopePermissionsProvider((
        parish: parishId,
        youth: null,
      )).overrideWith((ref) async => <String>{}),
      feedRepositoryProvider.overrideWithValue(feed),
      eventsProvider.overrideWith((ref) async => []),
      myParishEventsProvider.overrideWith((ref) async => []),
      myParishHelpProvider.overrideWith((ref) async => []),
      helpProvider.overrideWith((ref) async => []),
      chatRoomsProvider.overrideWith((ref) async => []),
      parishProvider(parishId).overrideWith(
        (ref) async => const Parish(
          id: parishId,
          name: 'Приход для проверки',
          address: 'Тестовый адрес',
          description: '',
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // Keep the auto-dispose router alive for the complete mounted test.
  final routerSubscription = container.listen(routerProvider, (_, next) {});
  addTearDown(routerSubscription.close);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  final router = routerSubscription.read();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'guest has three navigation buttons and club opens one auth modal',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = await mountApp(tester, RecordingFeed());
      await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/map');
      expect(find.byKey(const ValueKey('main-navigation-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('main-navigation-1')));
      // Fixed pumps: the background animation intentionally remains active.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(ClubRegistrationDialog), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/map');
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Телефон или email'), findsNothing);
      await tester.tap(find.byTooltip('Закрыть регистрацию'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('main-navigation-0')));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/feed');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'feed tap, swipe and deep link stay in sync; guest does not request parish feed',
    (tester) async {
      final feed = RecordingFeed();
      final router = await mountApp(tester, feed);
      expect(find.widgetWithText(Tab, 'Клубы'), findsNothing);
      expect(find.widgetWithText(Tab, 'Общая'), findsOneWidget);
      expect(feed.requests.whereType<String>(), isEmpty);
      await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters['tab'],
        'events',
      );
      router.go('/feed?tab=help');
      await tester.pumpAndSettle();
      expect(find.text('Пока нет объявлений о помощи'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final admin in [false, true]) {
    testWidgets('account menu exposes management by permission: $admin', (
      tester,
    ) async {
      await mountApp(tester, RecordingFeed(), signedIn: admin, admin: admin);
      await tester.tap(find.byTooltip('Профиль и меню'));
      await tester.pumpAndSettle();
      expect(find.text('Управление'), admin ? findsOneWidget : findsNothing);
      expect(find.text('Настройки'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending member does not load private news', (tester) async {
    final feed = RecordingFeed();
    final router = await mountApp(
      tester,
      feed,
      signedIn: true,
      membershipStatus: 'pending',
    );
    router.go('/feed?tab=parish');
    await tester.pumpAndSettle();
    expect(find.text('Молодёжный клуб для проверки'), findsOneWidget);
    expect(find.text('Чаты клуба'), findsNothing);
    expect(feed.requests.whereType<String>(), isEmpty);
    router.go('/my-parish');
    await tester.pumpAndSettle();
    expect(find.text('Заявка отправлена'), findsOneWidget);
    expect(find.textContaining('Статус: на рассмотрении'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retired parish links open the selected club with no management controls',
    (tester) async {
      final router = await mountApp(
        tester,
        RecordingFeed(),
        signedIn: true,
        membershipStatus: 'active',
      );
      for (final route in [
        '/parishes',
        '/my-parish',
        '/my-parish/about',
        '/parishes/legacy',
      ]) {
        router.go(route);
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/my-youth');
        expect(find.text('Выберите молодёжный клуб'), findsNothing);
        expect(find.text('Молодёжный клуб для проверки'), findsOneWidget);
        expect(find.text('Чаты клуба'), findsOneWidget);
        expect(find.text('Открыть клуб'), findsNothing);
        expect(find.text('Управление молодёжкой'), findsNothing);
        expect(find.text('Создать клуб'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'profile menu login opens the existing modal in login mode without navigation',
    (tester) async {
      final router = await mountApp(tester, RecordingFeed());
      final path = router.routeInformationProvider.value.uri.path;
      await tester.tap(find.byTooltip('Профиль и меню'));
      await tester.pumpAndSettle();
      expect(find.text('Моя молодёжка'), findsNothing);
      expect(find.text('Все приходы'), findsNothing);
      await tester.tap(find.text('Войти'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final dialog = tester.widget<ClubRegistrationDialog>(
        find.byType(ClubRegistrationDialog),
      );
      expect(dialog.startWithSignIn, isTrue);
      expect(dialog.accountOnly, isTrue);
      expect(find.byKey(const ValueKey('club-sign-in-submit')), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Имя'), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, path);
      await tester.tap(find.byTooltip('Закрыть регистрацию'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets('feed and club card adapt at $size with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = await mountApp(
        tester,
        RecordingFeed(),
        signedIn: true,
        membershipStatus: 'active',
        scale: 1.8,
        dark: size.width == 844,
      );
      expect(tester.takeException(), isNull);
      if (find.byType(NavigationRail).evaluate().isNotEmpty) {
        expect(
          tester
              .widget<NavigationRail>(find.byType(NavigationRail))
              .destinations
              .length,
          3,
        );
      } else {
        expect(ClubNavigationBar.destinations.length, 3);
      }
      router.go('/my-parish');
      await tester.pumpAndSettle();
      expect(find.text('Молодёжный клуб для проверки'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'return paths preserve supported feed tab and parish destinations only',
    () {
      expect(safeDestination('/feed?tab=events'), '/feed?tab=events');
      expect(safeDestination('/feed?tab=unknown'), '/feed');
      expect(safeDestination('/my-parish/news'), '/my-parish/news');
      expect(safeDestination('https://example.com/feed?tab=events'), '/feed');
      expect(requiresSignIn('/my-parish/events'), isTrue);
    },
  );

  for (final status in ['pending', 'active']) {
    test(
      'own events repository called only for active parish: $status',
      () async {
        final repository = RecordingEvents();
        final container = ProviderContainer(
          overrides: [
            clubLiveUpdatesProvider.overrideWith(
              (ref) => const Stream<ClubLiveUpdate>.empty(),
            ),
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('events-user')),
            ),
            currentMembershipProvider.overrideWith(
              (ref) async =>
                  Membership(id: 'm', parishId: parishId, status: status),
            ),
            eventsRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final authSubscription = container.listen(
          authUserProvider,
          (_, next) {},
        );
        addTearDown(authSubscription.close);
        await container.read(authUserProvider.future);
        final eventsSubscription = container.listen(
          myParishEventsProvider,
          (_, next) {},
        );
        addTearDown(eventsSubscription.close);
        await container.read(myParishEventsProvider.future);
        expect(repository.requests, status == 'active' ? [parishId] : isEmpty);
      },
    );
  }
}
