import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/shell/account_menu.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/domain/auth_repository.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';

class MenuAuthRepository implements AuthRepository {
  final changes = StreamController<AppUser?>.broadcast();
  AppUser? user = const AppUser('menu-user');
  Completer<void>? signOutGate;
  int signOutCalls = 0;

  @override
  Stream<AppUser?> watchUser() async* {
    yield user;
    yield* changes.stream;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final gate = signOutGate;
    if (gate != null) await gate.future;
    user = null;
    changes.add(null);
  }

  @override
  Future<void> signIn(String email, String password) async =>
      throw UnimplementedError();

  @override
  Future<bool> signUp(String email, String password) async =>
      throw UnimplementedError();
}

Future<void> settleMenu(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<GoRouter> mountMenu(
  WidgetTester tester,
  MenuAuthRepository repository,
) async {
  final router = GoRouter(
    initialLocation: '/feed',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          appBar: AppBar(actions: const [AccountMenu()]),
          body: shell,
        ),
        branches: [
          for (final paths in [
            ['/feed'],
            ['/my-youth', '/profile', '/admin'],
            ['/map'],
          ])
            StatefulShellBranch(
              routes: [
                for (final path in paths)
                  GoRoute(
                    path: path,
                    builder: (context, state) => Center(
                      key: ValueKey('page-$path'),
                      child: Text('Page: $path'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await repository.changes.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        accountAccessProvider.overrideWith((ref) {
          final user = ref.watch(authUserProvider).asData?.value;
          return Stream.value(AccountAccess(superAdmin: user != null));
        }),
        clubWorkspacesProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await settleMenu(tester);
  return router;
}

Future<void> selectMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Профиль и меню'));
  await settleMenu(tester);
  final item = find.text(label);
  expect(item, findsOneWidget);
  await tester.tap(item);
  await settleMenu(tester);
}

void main() {
  testWidgets('settings, management and sign-out work in the same shell menu', (
    tester,
  ) async {
    final repository = MenuAuthRepository();
    final router = await mountMenu(tester, repository);
    final menuState = tester.state(find.byType(AccountMenu));

    for (final entry in [
      (label: 'Настройки', path: '/profile'),
      (label: 'Управление', path: '/admin'),
      (label: 'Настройки', path: '/profile'),
    ]) {
      await selectMenuItem(tester, entry.label);
      expect(find.byKey(ValueKey('page-${entry.path}')), findsOneWidget);
      expect(tester.state(find.byType(AccountMenu)), same(menuState));
    }

    // Navigation still supports Back; menu actions do not need a prior pop.
    expect(router.canPop(), isTrue);
    router.pop();
    await settleMenu(tester);
    expect(find.byKey(const ValueKey('page-/admin')), findsOneWidget);
    await selectMenuItem(tester, 'Выйти');
    expect(repository.signOutCalls, 1);
    expect(repository.user, isNull);
    expect(find.byKey(const ValueKey('page-/feed')), findsOneWidget);
    await tester.tap(find.byTooltip('Профиль и меню'));
    await settleMenu(tester);
    expect(find.text('Войти'), findsOneWidget);
    expect(find.text('Выйти'), findsNothing);
    expect(find.text('Управление'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending sign-out blocks duplicates and a failure allows retry', (
    tester,
  ) async {
    final repository = MenuAuthRepository()..signOutGate = Completer<void>();
    await mountMenu(tester, repository);
    await selectMenuItem(tester, 'Настройки');
    await selectMenuItem(tester, 'Выйти');

    PopupMenuButton<String> menuButton() => tester
        .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>));
    expect(repository.signOutCalls, 1);
    expect(menuButton().enabled, isFalse);
    // Also exercise the handler guard, independent of the disabled UI.
    menuButton().onSelected!('sign-out');
    await tester.pump();
    expect(repository.signOutCalls, 1);

    repository.signOutGate!.completeError(StateError('Offline'));
    await settleMenu(tester);
    expect(repository.user?.id, 'menu-user');
    expect(menuButton().enabled, isTrue);
    expect(
      find.text('Не удалось выполнить действие. Попробуйте ещё раз.'),
      findsOneWidget,
    );
    repository.signOutGate = null;
    await selectMenuItem(tester, 'Выйти');
    expect(repository.signOutCalls, 2);
    expect(repository.user, isNull);
    expect(find.byKey(const ValueKey('page-/feed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
