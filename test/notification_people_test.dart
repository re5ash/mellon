import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/role_manager_dialog.dart';
import 'package:moy_prihod/features/community/role_manager_repository.dart';
import 'package:moy_prihod/features/notifications/application/notification_applicant_providers.dart';
import 'package:moy_prihod/features/notifications/application/notification_providers.dart';
import 'package:moy_prihod/features/notifications/data/notification_applicant_repository.dart';
import 'package:moy_prihod/features/notifications/domain/app_notification.dart';
import 'package:moy_prihod/features/notifications/domain/notification_applicant.dart';
import 'package:moy_prihod/features/notifications/domain/notification_repository.dart';
import 'package:moy_prihod/features/notifications/presentation/notifications_page.dart';

const _club = 'f0000000-0000-0000-0000-000000000201';
const _request = 'f0000000-0000-0000-0000-000000009001';
const _notice = AppNotification(
  id: 'notice',
  title: 'Новая заявка',
  body: 'Анна Волкова · МК Невского',
  targetPath: '/youth-requests/$_club?request=$_request',
  isRead: false,
  kind: 'youth_request',
  subjectUserId: 'anna',
  youthRequestId: _request,
);
final _person = NotificationApplicant(
  notificationId: 'notice',
  userId: 'anna',
  displayName: 'Анна',
  givenName: 'Анна',
  familyName: 'Волкова',
  email: 'anna@example.test',
  birthDate: DateTime(2001, 2, 3),
  phone: '+79991234567',
  registeredAt: DateTime.utc(2026, 9, 13),
  reviewStatus: 'pending',
  clubId: _club,
  clubName: 'Молодёжный клуб храма Александра Невского',
  requestId: _request,
  requestStatus: 'pending',
  canManageRoles: true,
);

class _Applicants implements NotificationApplicantRepository {
  NotificationApplicant? value = _person;
  Completer<NotificationApplicant?>? waiting;
  bool fail = false;
  @override
  Future<NotificationApplicant?> getApplicant(String notificationId) async {
    if (fail) throw const AppFailure('Не удалось загрузить данные');
    return waiting == null ? value : await waiting!.future;
  }
}

class _Notifications implements NotificationRepository {
  final read = <String>[];
  bool failRead = false;
  @override
  Future<void> markRead(String id) async {
    if (failRead) throw const AppFailure('Не удалось открыть уведомление');
    read.add(id);
  }

  @override
  Stream<List<AppNotification>> watchInbox(String userId) => Stream.value([]);
}

class _Roles implements RoleManagerRepository {
  final opened = <String>[];
  @override
  Future<List<RolePerson>> people(String search, String? after) async => [
    const RolePerson(
      id: 'other',
      name: 'Другой пользователь',
      summary: 'Участник',
    ),
    const RolePerson(id: 'anna', name: 'Анна Волкова', summary: 'Гость'),
  ];
  @override
  Future<RolePersonDetails> person(String id) async {
    opened.add(id);
    return RolePersonDetails(
      person: RolePerson(id: id, name: 'Анна Волкова', summary: 'Гость'),
      email: 'anna@example.test',
      globalRole: 'guest',
      revision: 'revision',
      clubs: const [],
      canGlobal: true,
      globalRoles: const [
        RoleOption(
          key: 'guest',
          title: 'Гость',
          baseline: 'guest',
          assignable: true,
        ),
      ],
    );
  }

  @override
  Future<String?> avatarUrl(String path) async => null;
  @override
  Future<void> save({
    required String user,
    required String actor,
    required String revision,
    required String request,
    required String? globalRole,
    required Map<String, String> clubs,
  }) async {
    throw StateError('Opening notifications must not save roles');
  }
}

class _Streams {
  final auth = StreamController<AppUser?>.broadcast();
  final access = StreamController<AccountAccess>.broadcast();
  final inbox = StreamController<List<AppNotification>>.broadcast();
  Future<void> dispose() async {
    await auth.close();
    await access.close();
    await inbox.close();
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  // ensureVisible changes the scroll position; the next frame updates the
  // rendered coordinates used by hit testing and tap().
  await _settle(tester);
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'The button must be visible and receive a real tap after scrolling.',
  );
  await tester.tap(finder);
  await _settle(tester);
}

Future<GoRouter> _mount(
  WidgetTester tester,
  _Streams streams,
  _Applicants applicants,
  _Notifications notices,
  _Roles roles, {
  double width = 1000,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(streams.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: NotificationsPage()),
      ),
      GoRoute(
        path: '/youth-requests/:club',
        builder: (_, state) => Scaffold(
          body: Text('request:${state.uri.queryParameters['request']}'),
        ),
      ),
      GoRoute(
        path: '/admin/youth-clubs',
        builder: (_, _) =>
            const Scaffold(body: Text('Настройки приёма заявок')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) => streams.auth.stream),
        accountAccessProvider.overrideWith((ref) => streams.access.stream),
        notificationsProvider.overrideWith((ref) => streams.inbox.stream),
        notificationApplicantRepositoryProvider.overrideWithValue(applicants),
        notificationRepositoryProvider.overrideWithValue(notices),
        roleManagerRepositoryProvider.overrideWithValue(roles),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  streams.auth.add(const AppUser('admin'));
  streams.inbox.add([_notice]);
  // Subscribe the applicant's access dependency before its restored value arrives.
  await tester.pump();
  streams.access.add(
    const AccountAccess(superAdmin: true, canManageRoles: true),
  );
  await _settle(tester);
  return router;
}

void main() {
  for (final width in [1000.0, 320.0]) {
    testWidgets(
      'person details wrap and Roles opens the selected applicant at width $width',
      (tester) async {
        final roles = _Roles();
        final notifications = _Notifications();
        final router = await _mount(
          tester,
          _Streams(),
          _Applicants(),
          notifications,
          roles,
          width: width,
          scale: width < 400 ? 1.8 : 1,
        );
        expect(find.text('Анна Волкова'), findsOneWidget);
        expect(find.text('anna@example.test'), findsOneWidget);
        expect(find.text('03.02.2001'), findsOneWidget);
        expect(find.text('+79991234567'), findsOneWidget);
        expect(find.text('Ожидание проверки'), findsOneWidget);
        final open = find.byKey(const ValueKey('notification-roles-notice'));
        await _tapVisible(tester, open);
        expect(find.byType(RoleManagerDialog), findsOneWidget);
        expect(
          tester
              .widget<RoleManagerDialog>(find.byType(RoleManagerDialog))
              .initialUser,
          'anna',
        );
        expect(roles.opened, ['anna']);
        expect(notifications.read, ['notice']);
        expect(router.routeInformationProvider.value.uri.path, '/');
        await tester.tap(find.byTooltip('Закрыть'));
        await _settle(tester);
        expect(find.byType(RoleManagerDialog), findsNothing);
        expect(find.byType(NotificationsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('application button retains both club and request identifiers', (
    tester,
  ) async {
    final router = await _mount(
      tester,
      _Streams(),
      _Applicants(),
      _Notifications(),
      _Roles(),
    );
    final open = find.byKey(const ValueKey('notification-request-notice'));
    await _tapVisible(tester, open);
    expect(find.text('request:$_request'), findsOneWidget);
    final state = GoRouterState.of(
      tester.element(find.text('request:$_request')),
    );
    expect(state.pathParameters['club'], _club);
    expect(state.uri.queryParameters['request'], _request);
    router.pop();
    await _settle(tester);
    expect(find.byType(NotificationsPage), findsOneWidget);
  });
  testWidgets('missing club still shows one person and opens their Roles', (
    tester,
  ) async {
    final applicants = _Applicants()
      ..value = const NotificationApplicant(
        notificationId: 'notice',
        userId: 'anna',
        displayName: 'Анна Волкова',
        email: 'anna@example.test',
        reviewStatus: 'pending',
        canManageRoles: true,
      );
    final roles = _Roles();
    await _mount(tester, _Streams(), applicants, _Notifications(), roles);
    expect(find.text('Клуб для заявки пока не выбран'), findsOneWidget);
    expect(find.text('Не указан'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('notification-roles-notice')));
    await _settle(tester);
    expect(roles.opened, ['anna']);
    await tester.tap(find.byTooltip('Закрыть'));
    await _settle(tester);
  });
  testWidgets('revoked permission is rechecked before opening Roles', (
    tester,
  ) async {
    final applicants = _Applicants();
    final roles = _Roles();
    final notices = _Notifications();
    await _mount(tester, _Streams(), applicants, notices, roles);
    applicants.value = null;
    await tester.tap(find.byKey(const ValueKey('notification-roles-notice')));
    await _settle(tester);
    expect(find.byType(RoleManagerDialog), findsNothing);
    expect(roles.opened, isEmpty);
    expect(notices.read, isEmpty);
    expect(find.text('anna@example.test'), findsNothing);
  });
  testWidgets(
    'failed read can retry and late completion after account switch opens nothing',
    (tester) async {
      final streams = _Streams();
      final applicants = _Applicants();
      final notices = _Notifications()..failRead = true;
      final roles = _Roles();
      await _mount(tester, streams, applicants, notices, roles);
      await tester.tap(find.byKey(const ValueKey('notification-roles-notice')));
      await _settle(tester);
      expect(find.text('Не удалось открыть уведомление'), findsOneWidget);
      expect(find.byType(RoleManagerDialog), findsNothing);
      notices.failRead = false;
      final pendingResponse = Completer<NotificationApplicant?>();
      applicants.waiting = pendingResponse;
      await tester.tap(find.byKey(const ValueKey('notification-roles-notice')));
      await tester.pump();
      streams.auth.add(const AppUser('different-user'));
      streams.inbox.add([]);
      await tester.pump();
      pendingResponse.complete(_person);
      await _settle(tester);
      expect(find.text('anna@example.test'), findsNothing);
      expect(roles.opened, isEmpty);
      expect(notices.read, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
