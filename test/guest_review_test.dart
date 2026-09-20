import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/router/route_access.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/presentation/club_registration_dialog.dart';
import 'package:moy_prihod/features/auth/presentation/club_sky_scene.dart';
import 'package:moy_prihod/features/auth/presentation/club_welcome_art.dart';
import 'package:moy_prihod/features/community/club_applications_page.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/community/review_hourglass.dart';
import 'package:moy_prihod/features/notifications/application/notification_providers.dart';
import 'package:moy_prihod/features/notifications/domain/app_notification.dart';
import 'package:moy_prihod/features/notifications/domain/notification_repository.dart';
import 'package:moy_prihod/features/notifications/presentation/notification_bell.dart';
import 'package:moy_prihod/features/notifications/presentation/notifications_page.dart';

import 'design_navigation_test.dart' as design;

class ReviewNotifications implements NotificationRepository {
  final read = <String>[];
  @override
  Future<void> markRead(String id) async {
    read.add(id);
  }

  @override
  Stream<List<AppNotification>> watchInbox(String userId) => Stream.value([]);
}

class ReviewStreams {
  final access = StreamController<AccountAccess>.broadcast();
  final inbox = StreamController<List<AppNotification>>.broadcast();
  Future<void> dispose() async {
    await access.close();
    await inbox.close();
  }
}

void main() {
  for (final layout in [
    (size: const Size(390, 844), scale: 1.0),
    (size: const Size(320, 568), scale: 2.0),
  ]) {
    testWidgets(
      'compact review modal retains sky and stays usable at ${layout.size.width} / ${layout.scale}',
      (tester) async {
        final streams = ReviewStreams();
        addTearDown(streams.dispose);
        tester.view.physicalSize = layout.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = await design.mountApp(
          tester,
          design.RecordingFeed(),
          signedIn: true,
          scale: layout.scale,
          accessStream: streams.access.stream,
        );
        streams.access.add(
          const AccountAccess(restrictedGuest: true, reviewStatus: 'pending'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Ожидание'), findsNothing);
        expect(find.widgetWithText(Tab, 'Клубы'), findsNothing);
        for (final tab in ['Общая', 'События', 'Помощь']) {
          expect(find.widgetWithText(Tab, tab), findsOneWidget);
        }
        await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('main-navigation-1')));
        // The sky intentionally animates continuously: do not pumpAndSettle here.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final dialog = find.byType(ClubRegistrationDialog);
        expect(dialog, findsOneWidget);
        expect(
          tester.widget<ClubRegistrationDialog>(dialog).reviewOnly,
          isTrue,
        );
        expect(router.routeInformationProvider.value.uri.path, '/map');
        expect(
          find.descendant(of: dialog, matching: find.text('Ожидание')),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Молодёжный клуб для проверки'), findsNothing);
        expect(find.text('Чаты клуба'), findsNothing);
        final surface = find.byKey(const ValueKey('club-scene-surface'));
        final bounds = tester.getRect(surface);
        expect(bounds.bottom, lessThanOrEqualTo(layout.size.height));
        expect(bounds.top, greaterThanOrEqualTo(0));
        if (layout.scale == 1) expect(bounds.height, lessThan(650));
        expect(find.text('Заявка на проверке'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('club-review-status-badge')),
          findsOneWidget,
        );
        Animation<double> sandFlow() =>
            (tester
                        .widget<CustomPaint>(
                          find.byKey(const ValueKey('review-hourglass-paint')),
                        )
                        .painter!
                    as ReviewHourglassPainter)
                .progress;
        final sand = sandFlow();
        final sandStart = sand.value;
        final background = tester.state<State<ClubWelcomeArt>>(
          find.byType(ClubWelcomeArt),
        );
        Animation<double> drift() =>
            (tester
                        .widget<CustomPaint>(
                          find.byKey(const ValueKey('club-sky-clouds')),
                        )
                        .painter!
                    as SkyCloudsPainter)
                .drift;
        final clouds = drift();
        final progress = clouds.value;
        streams.access.add(
          const AccountAccess(restrictedGuest: true, reviewStatus: 'pending'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.getRect(surface), bounds);
        expect(identical(drift(), clouds), isTrue);
        expect(clouds.value, greaterThan(progress));
        expect(identical(sandFlow(), sand), isTrue);
        expect(sand.value, greaterThan(sandStart));
        streams.access.add(
          const AccountAccess(restrictedGuest: true, reviewStatus: 'verified'),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('Проверен'), findsOneWidget);
        expect(find.text('Ожидание'), findsNothing);
        expect(
          find.text('Доступ к молодёжному клубу пока не открыт'),
          findsOneWidget,
        );
        expect(find.text('Молодёжный клуб для проверки'), findsNothing);
        expect(tester.getRect(surface).width, bounds.width);
        expect(find.byType(ReviewHourglass), findsNothing);
        expect(
          identical(
            tester.state<State<ClubWelcomeArt>>(find.byType(ClubWelcomeArt)),
            background,
          ),
          isTrue,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('club-review-close')),
        );
        await tester.tap(find.byKey(const ValueKey('club-review-close')));
        await tester.pumpAndSettle();
        expect(dialog, findsNothing);
        expect(router.routeInformationProvider.value.uri.path, '/map');
        if (layout.scale > 1) {
          expect(tester.takeException(), isNull);
          return;
        }
        // Closing must release the navigation guard so status can be opened again.
        await tester.tap(find.byKey(const ValueKey('main-navigation-1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(dialog, findsOneWidget);
        streams.access.add(const AccountAccess(reviewStatus: 'verified'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.byKey(const ValueKey('club-review-approved')),
          findsOneWidget,
        );
        expect(find.text('Молодёжный клуб для проверки'), findsNothing);
        await tester.ensureVisible(
          find.byKey(const ValueKey('club-review-close')),
        );
        await tester.tap(find.byKey(const ValueKey('club-review-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('main-navigation-1')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/my-youth');
        expect(find.text('Молодёжный клуб для проверки'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('main-navigation-0')));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(Tab, 'Клубы'), findsOneWidget);
        expect(find.text('Ожидание'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'hourglass pauses for reduced motion and inactive routes, then disposes',
    (tester) async {
      final reduced = ValueNotifier(false);
      final active = ValueNotifier(true);
      addTearDown(reduced.dispose);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: reduced,
            builder: (context, disabled, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: disabled),
              child: ValueListenableBuilder<bool>(
                valueListenable: active,
                builder: (context, enabled, child) => TickerMode(
                  enabled: enabled,
                  child: const Center(
                    child: ReviewHourglass(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('review-hourglass-paint')),
                  )
                  .painter!
              as ReviewHourglassPainter;
      final initial = painter.progress.value;
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter.progress.value, greaterThan(initial));
      reduced.value = true;
      await tester.pump();
      final paused = painter.progress.value;
      await tester.pump(const Duration(seconds: 1));
      expect(painter.progress.value, paused);
      reduced.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(painter.progress.value, greaterThan(paused));
      active.value = false;
      await tester.pump();
      final inactive = painter.progress.value;
      await tester.pump(const Duration(seconds: 1));
      expect(painter.progress.value, inactive);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification badge updates and click opens the exact applicant first',
    (tester) async {
      const club = 'f0000000-0000-0000-0000-000000000201';
      const request = 'f0000000-0000-0000-0000-000000009001';
      final streams = ReviewStreams();
      addTearDown(streams.dispose);
      final repository = ReviewNotifications();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(appBar: null, body: NotificationBell()),
          ),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const Scaffold(body: NotificationsPage()),
          ),
          GoRoute(
            path: '/youth-requests/:youthId',
            builder: (_, state) => ClubApplicationsPage(
              youth: state.pathParameters['youthId']!,
              requestId: state.uri.queryParameters['request'],
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('admin')),
            ),
            notificationsProvider.overrideWith((ref) => streams.inbox.stream),
            notificationRepositoryProvider.overrideWithValue(repository),
            clubApplicationsProvider(club).overrideWith(
              (ref) async => <JsonRow>[
                {
                  'id': 'other',
                  'display_name': 'Другой участник',
                  'email_confirmed': true,
                },
                {
                  'id': request,
                  'display_name': 'Иван Иванов',
                  'email_confirmed': true,
                },
              ],
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      // The real app router subscribes to auth before user interaction.
      // This isolated router needs the same restored session explicitly.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotificationBell)),
      );
      final auth = container.listen(authUserProvider, (_, next) {});
      addTearDown(auth.close);
      await tester.pumpAndSettle();
      expect(auth.read().asData?.value?.id, 'admin');
      streams.inbox.add([
        const AppNotification(
          id: 'notice',
          title: 'Новая заявка',
          body: 'Иван Иванов · МК Невского',
          targetPath: '/youth-requests/$club?request=$request',
          isRead: false,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Badge>(find.byKey(const ValueKey('notification-badge')))
            .isLabelVisible,
        isTrue,
      );
      await tester.tap(find.byType(NotificationBell));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Иван Иванов · МК Невского'));
      await tester.pumpAndSettle();
      expect(repository.read, ['notice']);
      // push() adds a page to the Navigator; the browser/base URI is not
      // the source of truth for that page's parameters.
      final applicationPage = find.byType(ClubApplicationsPage);
      expect(applicationPage, findsOneWidget);
      final opened = tester.widget<ClubApplicationsPage>(applicationPage);
      expect(opened.youth, club);
      expect(opened.requestId, request);
      final openedRoute = GoRouterState.of(tester.element(applicationPage));
      expect(openedRoute.uri.path, '/youth-requests/$club');
      expect(openedRoute.uri.queryParameters['request'], request);
      expect(
        tester.getTopLeft(find.text('Иван Иванов')).dy,
        lessThan(tester.getTopLeft(find.text('Другой участник')).dy),
      );
      expect(find.text('Принять'), findsNWidgets(2));
      expect(find.text('Отклонить'), findsNWidgets(2));
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ClubApplicationsPage), findsNothing);
      expect(find.byType(NotificationsPage), findsOneWidget);
      expect(find.text('Иван Иванов · МК Невского'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'application target keeps only safe request ID and guests cannot open internal club routes',
    () {
      const url = '/youth-requests/f0000000-0000-0000-0000-000000000201';
      const request = 'f0000000-0000-0000-0000-000000009001';
      expect(
        safeDestination('$url?request=$request&from=https://example.com'),
        '$url?request=$request',
      );
      expect(safeDestination('$url?request=invalid'), url);
      expect(allowedForRestrictedGuest('/my-youth'), isTrue);
      expect(allowedForRestrictedGuest('/my-youth?choose=1'), isTrue);
      expect(allowedForRestrictedGuest('/my-youth/private'), isFalse);
      expect(allowedForRestrictedGuest('/feed?tab=events'), isTrue);
      expect(allowedForRestrictedGuest('/help'), isTrue);
    },
  );
}
