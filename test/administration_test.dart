import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/router/route_access.dart';
import 'package:moy_prihod/core/access/permission_providers.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/administration/application/admin_providers.dart';
import 'package:moy_prihod/features/administration/domain/admin_models.dart';
import 'package:moy_prihod/features/administration/domain/admin_repository.dart';
import 'package:moy_prihod/features/administration/presentation/membership_requests_page.dart';
import 'package:moy_prihod/features/administration/presentation/parish_editor_page.dart';
import 'package:moy_prihod/features/administration/presentation/post_editor_page.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/domain/auth_repository.dart';
import 'package:moy_prihod/features/auth/presentation/auth_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const parishId = '20000000-0000-0000-0000-000000000001';

class FakeAdminRepository implements AdminRepository {
  final parishWrites = <ParishInput>[];
  final postWrites = <PostInput>[];
  final reviews = <({String id, bool approve})>[];
  Completer<String>? parishResult;
  Completer<String>? postResult;
  @override
  Future<String> saveParish(ParishInput input) {
    parishWrites.add(input);
    return parishResult?.future ?? Future.value(input.id);
  }

  @override
  Future<String> savePost(PostInput input) {
    postWrites.add(input);
    return postResult?.future ?? Future.value(input.id);
  }

  @override
  Future<void> review(String membershipId, {required bool approve}) async {
    reviews.add((id: membershipId, approve: approve));
  }

  @override
  Future<ParishBatch> parishes({String? after}) async =>
      const ParishBatch([], null);
  @override
  Future<AdminParish?> parish(String id) async => null;
  @override
  Future<AdminPost?> post(AdminPostRequest request) async => null;
  @override
  Future<CursorPage<AdminPost>> posts(AdminListRequest request) async =>
      const CursorPage(items: []);
  @override
  Future<CursorPage<PendingMembership>> requests(
    AdminListRequest request,
  ) async => const CursorPage(items: []);
}

class LimitedEmailRepository implements AuthRepository {
  int signUps = 0;
  @override
  Stream<AppUser?> watchUser() => Stream.value(null);
  @override
  Future<bool> signUp(String email, String password) async {
    signUps++;
    throw const AuthException(
      'email rate limit exceeded',
      code: 'over_email_send_rate_limit',
    );
  }

  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  // Text entry can queue layout and caret scrolling. Settle those frames
  // before calculating the button's position in the current viewport.
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason:
        'The target must be visible and receive pointer events before tapping.',
  );
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> mountForm(
  WidgetTester tester,
  Widget form,
  FakeAdminRepository repository,
) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) => Scaffold(body: form),
      ),
      GoRoute(
        path: '/admin/parishes/:id',
        builder: (_, state) => const Scaffold(body: Text('Сохранено')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminRepositoryProvider.overrideWithValue(repository),
        refreshAdminDataProvider.overrideWithValue(() {}),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('permission refresh retains the open parish form', (
    tester,
  ) async {
    final reload = Completer<Set<String>>();
    var loads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          permissionsProvider(null).overrideWith((ref) {
            loads++;
            return loads == 1
                ? Future.value(<String>{'parishes.manage'})
                : reload.future;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ParishEditorPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).first,
      'Несохранённый приход',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ParishEditorPage)),
    );
    container.invalidate(permissionsProvider(null));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Несохранённый приход',
    );
    reload.complete({'parishes.manage'});
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'Несохранённый приход',
    );
  });
  test(
    'administration return paths are retained, external redirect is rejected',
    () {
      for (final route in [
        '/admin/parishes/new',
        '/admin/parishes/$parishId',
        '/admin/parishes/$parishId/edit',
        '/admin/parishes/$parishId/requests',
        '/admin/parishes/$parishId/chats',
        '/admin/parishes/$parishId/chats/new',
        '/admin/parishes/$parishId/chats/$parishId',
        '/admin/parishes/$parishId/posts/new',
        '/admin/parishes/$parishId/posts/$parishId',
      ]) {
        expect(safeDestination(route), route);
        expect(requiresSignIn(route), isTrue);
      }
      expect(
        safeDestination('https://other.example/admin/parishes/new'),
        '/feed',
      );
      expect(safeDestination('/admin/parishes/$parishId/delete'), '/feed');
    },
  );

  testWidgets(
    'parish validates, blocks duplicate submit and retries with stable identity',
    (tester) async {
      final repository = FakeAdminRepository()
        ..parishResult = Completer<String>();
      await mountForm(
        tester,
        const ParishEditorForm(canPublish: true),
        repository,
      );
      await tapVisible(tester, find.text('Сохранить приход'));
      expect(repository.parishWrites, isEmpty);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Приход');
      await tester.enterText(fields.at(1), 'Калининград');
      await tapVisible(tester, find.text('Сохранить приход'));
      expect(repository.parishWrites, hasLength(1));
      expect(repository.parishWrites.single.isPublished, isFalse);
      expect(repository.parishWrites.single.joinMode, 'approval');
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      repository.parishResult!.completeError(
        const PostgrestException(message: 'forbidden', code: '42501'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Нет доступа к этому действию.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.first).controller!.text,
        'Приход',
      );
      repository.parishResult = null;
      await tapVisible(tester, find.text('Сохранить приход'));
      expect(repository.parishWrites, hasLength(2));
      expect(repository.parishWrites[0].id, repository.parishWrites[1].id);
      expect(find.text('Сохранено'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new publication defaults to private draft and preserves text after failure',
    (tester) async {
      final repository = FakeAdminRepository()
        ..postResult = Completer<String>();
      await mountForm(
        tester,
        const PostEditorForm(parishId: parishId, parishName: 'Приход'),
        repository,
      );
      await tapVisible(tester, find.text('Сохранить'));
      expect(repository.postWrites, isEmpty);
      await tester.enterText(find.byType(TextFormField).first, 'Первая запись');
      await tester.enterText(find.byType(TextFormField).last, 'Содержание');
      await tapVisible(tester, find.text('Сохранить'));
      expect(repository.postWrites.single.visibility, 'parish');
      expect(repository.postWrites.single.status, 'draft');
      expect(repository.postWrites.single.parishId, parishId);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      repository.postResult!.completeError(
        const PostgrestException(message: 'edit_conflict', code: '40001'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Запись уже изменена'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).last)
            .controller!
            .text,
        'Содержание',
      );
      repository.postResult = null;
      await tapVisible(tester, find.text('Сохранить'));
      expect(repository.postWrites[0].id, repository.postWrites[1].id);
      expect(find.text('Сохранено'), findsOneWidget);
    },
  );

  testWidgets(
    'membership rejection can be cancelled; approval sends correct id',
    (tester) async {
      final repository = FakeAdminRepository();
      final item = PendingMembership(
        id: 'request-1',
        userId: 'user-1',
        displayName: 'Анна',
        requestedAt: DateTime.utc(2026, 9, 10),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adminRepositoryProvider.overrideWithValue(repository),
            refreshAdminDataProvider.overrideWithValue(() {}),
            pendingMembershipsProvider((
              parishId: parishId,
              before: null,
            )).overrideWith((ref) async => CursorPage(items: [item])),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: MembershipRequestList(
                parishId: parishId,
                parishName: 'Приход',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Отклонить'));
      expect(find.text('Отклонить заявку?'), findsOneWidget);
      await tapVisible(tester, find.text('Отмена'));
      expect(repository.reviews, isEmpty);
      await tapVisible(tester, find.text('Одобрить'));
      expect(repository.reviews, [(id: 'request-1', approve: true)]);
      expect(find.text('Заявка одобрена'), findsOneWidget);
    },
  );

  testWidgets('administration page denies editor without capability', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          managedParishProvider(parishId).overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PostEditorPage(parishId: parishId),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Доступ ограничен'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets(
    'email limit is explained and switching auth mode clears stale error',
    (tester) async {
      final repository = LimitedEmailRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(theme: AppTheme.light, home: const AuthPage()),
        ),
      );
      await tapVisible(tester, find.text('Создать аккаунт'));
      Finder field(String label) => find.ancestor(
        of: find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field('Электронная почта'), 'person@example.com');
      await tester.enterText(field('Пароль'), 'long-test-password');
      await tester.enterText(field('Повторите пароль'), 'different-password');
      await tapVisible(tester, find.text('Зарегистрироваться'));
      expect(repository.signUps, 0);
      expect(find.text('Пароли не совпадают'), findsOneWidget);
      await tester.enterText(field('Повторите пароль'), 'long-test-password');
      await tapVisible(tester, find.text('Зарегистрироваться'));
      expect(repository.signUps, 1);
      expect(
        find.textContaining('Достигнут лимит отправки писем'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Уже есть аккаунт'));
      expect(
        find.textContaining('Достигнут лимит отправки писем'),
        findsNothing,
      );
      expect(
        userError(const AuthException('Untrusted raw server detail')),
        isNot(contains('Untrusted')),
      );
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    for (final isPost in [false, true]) {
      testWidgets(
        'admin ${isPost ? 'post' : 'parish'} form fits $size with keyboard and large text',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: AppTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.8),
                    viewInsets: const EdgeInsets.only(bottom: 260),
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  body: isPost
                      ? const PostEditorForm(
                          parishId: parishId,
                          parishName: 'Приход',
                        )
                      : const ParishEditorForm(canPublish: true),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
