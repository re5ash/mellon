import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/router/route_access.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/role_manager_dialog.dart';
import 'package:moy_prihod/features/community/role_manager_repository.dart';

const _globalCatalog = [
  RoleOption(key: 'super_admin', title: 'Суперадмин', assignable: true),
  RoleOption(
    key: 'user',
    title: 'Участник',
    baseline: 'authenticated',
    assignable: true,
  ),
  RoleOption(key: 'guest', title: 'Гость', baseline: 'guest', assignable: true),
];
const _clubCatalog = [
  RoleOption(key: 'youth_leader', title: 'Руководитель', assignable: true),
  RoleOption(key: 'youth_moderator', title: 'Модератор', assignable: true),
  RoleOption(
    key: 'user',
    title: 'Участник',
    baseline: 'authenticated',
    assignable: true,
  ),
];

class _Saved {
  _Saved(this.user, this.actor, this.request, this.global, this.clubs);
  final String user, actor, request;
  final String? global;
  final Map<String, String> clubs;
}

class _Roles extends RoleManagerRepository {
  final saves = <_Saved>[];
  int peopleCalls = 0;
  final clubRoles = <String, String>{'a': 'user', 'b': 'youth_moderator'};
  String global = 'user';
  List<RoleOption> globalOptions = [..._globalCatalog];
  final clubOptions = <String, List<RoleOption>>{
    'a': [..._clubCatalog],
    'b': [..._clubCatalog],
  };
  bool globalMultiple = false;
  final multipleClubs = <String>{};
  bool fail = false, canGlobal = true;
  Completer<void>? saving;
  Completer<List<RolePerson>>? slowSearch;
  static const peopleList = [
    RolePerson(id: 'anna', name: 'Анна Волкова', summary: 'Участник'),
    RolePerson(id: 'ivan', name: 'Иван Иванов', summary: 'Модератор'),
  ];
  @override
  Future<List<RolePerson>> people(String search, String? after) async {
    peopleCalls++;
    if (search == 'Ан' && slowSearch != null) return slowSearch!.future;
    return peopleList
        .where((p) => p.name.toLowerCase().contains(search.toLowerCase()))
        .toList();
  }

  @override
  Future<RolePersonDetails> person(String id) async => RolePersonDetails(
    person: peopleList.firstWhere((p) => p.id == id),
    email: '$id@example.test',
    globalRole: global,
    revision: 'revision-${saves.length}',
    canGlobal: canGlobal,
    globalRoles: globalOptions,
    globalMultipleRoles: globalMultiple,
    clubs: [
      RoleClub(
        id: 'a',
        name: 'Молодёжный клуб храма Александра Невского',
        role: clubRoles['a'],
        canEdit: true,
        roles: clubOptions['a']!,
        multipleRoles: multipleClubs.contains('a'),
      ),
      RoleClub(
        id: 'b',
        name: 'Молодёжный клуб Покровского храма',
        role: clubRoles['b'],
        canEdit: true,
        roles: clubOptions['b']!,
        multipleRoles: multipleClubs.contains('b'),
      ),
    ],
  );
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
    saves.add(_Saved(user, actor, request, globalRole, Map.of(clubs)));
    if (saving != null) await saving!.future;
    if (fail) throw const AppFailure('Нет соединения');
    if (globalRole != null) {
      global = globalRole;
      globalMultiple = false;
    }
    multipleClubs.removeAll(clubs.keys);
    clubRoles.addAll(clubs);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _Roles repo, {
  double width = 1120,
  double scale = 1,
  Stream<AppUser?>? users,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => users ?? Stream.value(const AppUser('admin')),
        ),
        accountAccessProvider.overrideWith(
          (ref) => Stream.value(
            const AccountAccess(superAdmin: true, canManageRoles: true),
          ),
        ),
        roleManagerRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: RolesEntry()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Роли'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('role-person-anna')));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _club(WidgetTester tester, String title) async {
  await _tap(tester, 'roles-club-select');
  await tester.tap(find.text(title).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cold modal waits for both session and access before loading people',
    (tester) async {
      final session = Completer<AppUser?>();
      final access = Completer<AccountAccess>();
      final repo = _Roles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.fromFuture(session.future),
            ),
            accountAccessProvider.overrideWith(
              (ref) => Stream.fromFuture(access.future),
            ),
            roleManagerRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RoleManagerDialog(),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repo.peopleCalls, 0);
      session.complete(const AppUser('admin'));
      await tester.pump();
      expect(repo.peopleCalls, 0);
      access.complete(
        const AccountAccess(superAdmin: true, canManageRoles: true),
      );
      await tester.pumpAndSettle();
      expect(repo.peopleCalls, 1);
      expect(find.byKey(const ValueKey('role-person-anna')), findsOneWidget);
      expect(find.byKey(const ValueKey('roles-search')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'account change during access loading cannot open the old session',
    (tester) async {
      final users = StreamController<AppUser?>.broadcast();
      addTearDown(users.close);
      final access = Completer<AccountAccess>();
      final repo = _Roles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith((ref) => users.stream),
            accountAccessProvider.overrideWith(
              (ref) => Stream.fromFuture(access.future),
            ),
            roleManagerRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RoleManagerDialog(),
          ),
        ),
      );
      users.add(const AppUser('admin'));
      await tester.pump();
      users.add(const AppUser('other'));
      await tester.pump();
      access.complete(
        const AccountAccess(superAdmin: true, canManageRoles: true),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Аккаунт изменился во время загрузки'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('role-person-anna')), findsNothing);
      expect(find.byKey(const ValueKey('roles-save')), findsNothing);
      expect(repo.peopleCalls, 0);
      expect(repo.saves, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test('guest routes exclude private screens', () {
    for (final path in [
      '/feed',
      '/feed?tab=events',
      '/feed?tab=help',
      '/events',
      '/help',
      '/map',
      '/my-youth',
      '/notifications',
      '/profile/details',
      '/more',
      '/auth/new-password',
    ]) {
      expect(allowedForRestrictedGuest(path), isTrue);
    }
    for (final path in [
      '/manage',
      '/admin',
      '/my-youth/private',
      '/youth-requests/f0000000-0000-0000-0000-000000000201',
      '/chats/room',
      '/my-parish',
    ]) {
      expect(allowedForRestrictedGuest(path), isFalse);
    }
  });
  test(
    'server catalog preserves arbitrary role keys, titles and club boundaries',
    () {
      final details = RolePersonDetails.fromJson({
        'user_id': 'anna',
        'display_name': 'Анна',
        'email': 'anna@example.test',
        'global_role': 'site_editor',
        'revision': 'v1',
        'can_global': true,
        'global_roles': [
          {
            'key': 'site_editor',
            'title': 'Редактор приложения',
            'assignable': true,
          },
        ],
        'clubs': [
          {
            'id': 'a',
            'name': 'Клуб А',
            'role': 'events_editor',
            'can_edit': true,
            'roles': [
              {
                'key': 'events_editor',
                'title': 'Редактор встреч',
                'assignable': true,
              },
            ],
          },
          {'id': 'b', 'name': 'Клуб Б', 'roles': <Map<String, dynamic>>[]},
        ],
      });
      expect(details.globalRoles.single.title, 'Редактор приложения');
      expect(details.clubs.first.roles.single.key, 'events_editor');
      expect(details.clubs.last.roles, isEmpty);
      expect(details.globalRoles.any((r) => r.key == 'events_editor'), isFalse);
    },
  );
  testWidgets(
    'catalog roles use exclusive radios and remain independent across clubs',
    (tester) async {
      final repo = _Roles();
      repo.globalOptions.add(
        const RoleOption(
          key: 'site_editor',
          title: 'Редактор приложения',
          assignable: true,
        ),
      );
      repo.clubOptions['a']!.add(
        const RoleOption(
          key: 'events_editor',
          title: 'Редактор встреч',
          assignable: true,
        ),
      );
      await _mount(tester, repo);
      await _open(tester);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byKey(const ValueKey('global-events_editor')), findsNothing);
      await _tap(tester, 'global-site_editor');
      expect(
        tester
            .widget<RadioGroup<String>>(
              find.byKey(const ValueKey('global-radios')),
            )
            .groupValue,
        'site_editor',
      );
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.byKey(const ValueKey('global-user')),
            )
            .selected,
        isFalse,
      );
      await _club(tester, 'Молодёжный клуб храма Александра Невского');
      expect(find.byKey(const ValueKey('club-site_editor')), findsNothing);
      await _tap(tester, 'club-events_editor');
      expect(
        tester
            .widget<RadioListTile<String>>(
              find.byKey(const ValueKey('club-user')),
            )
            .selected,
        isFalse,
      );
      await _club(tester, 'Молодёжный клуб Покровского храма');
      expect(find.byKey(const ValueKey('club-events_editor')), findsNothing);
      await _tap(tester, 'club-user');
      await _club(tester, 'Молодёжный клуб храма Александра Невского');
      expect(
        tester
            .widget<RadioGroup<String>>(
              find.byKey(const ValueKey('club-radios')),
            )
            .groupValue,
        'events_editor',
      );
      await _tap(tester, 'roles-save');
      expect(repo.saves.single.global, 'site_editor');
      expect(repo.saves.single.clubs, {'a': 'events_editor', 'b': 'user'});
    },
  );
  testWidgets(
    'legacy multiple roles require an explicit single choice before replacement',
    (tester) async {
      final repo = _Roles()..globalMultiple = true;
      repo.multipleClubs.add('a');
      await _mount(tester, repo);
      await _open(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('roles-save')))
            .onPressed,
        isNull,
      );
      await _tap(tester, 'global-user');
      await _club(tester, 'Молодёжный клуб храма Александра Невского');
      await _tap(tester, 'club-user');
      await _tap(tester, 'roles-save');
      expect(repo.saves.single.global, 'user');
      expect(repo.saves.single.clubs, {'a': 'user'});
      expect(repo.clubRoles['b'], 'youth_moderator');
    },
  );
  testWidgets('a disabled catalog role cannot be selected', (tester) async {
    final repo = _Roles();
    repo.clubOptions['a']!.add(
      const RoleOption(key: 'restricted_editor', title: 'Недоступные права'),
    );
    await _mount(tester, repo);
    await _open(tester);
    await _club(tester, 'Молодёжный клуб храма Александра Невского');
    await _tap(tester, 'club-restricted_editor');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byKey(const ValueKey('club-radios')))
          .groupValue,
      'user',
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('roles-save')))
          .onPressed,
      isNull,
    );
    expect(repo.saves, isEmpty);
  });
  testWidgets('club administrator is exclusive and preserves other scopes', (
    tester,
  ) async {
    final repo = _Roles();
    for (final roles in repo.clubOptions.values) {
      roles.add(
        const RoleOption(
          key: 'youth_admin',
          title: 'Администратор',
          assignable: true,
        ),
      );
    }
    await _mount(tester, repo);
    await _open(tester);
    expect(find.byKey(const ValueKey('global-youth_admin')), findsNothing);
    await _club(tester, 'Молодёжный клуб храма Александра Невского');
    await _tap(tester, 'club-youth_admin');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byKey(const ValueKey('club-radios')))
          .groupValue,
      'youth_admin',
    );
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.byKey(const ValueKey('club-user')),
          )
          .selected,
      isFalse,
    );
    await _club(tester, 'Молодёжный клуб Покровского храма');
    expect(
      tester
          .widget<RadioGroup<String>>(find.byKey(const ValueKey('club-radios')))
          .groupValue,
      'youth_moderator',
    );
    await _tap(tester, 'roles-save');
    expect(repo.saves.single.global, isNull);
    expect(repo.saves.single.clubs, {'a': 'youth_admin'});
    expect(repo.clubRoles, {'a': 'youth_admin', 'b': 'youth_moderator'});
    expect(repo.global, 'user');
  });
  testWidgets('one modal keeps independent club drafts until one save', (
    tester,
  ) async {
    final repo = _Roles();
    await _mount(tester, repo);
    await _open(tester);
    expect(find.byType(RoleManagerDialog), findsOneWidget);
    expect(find.text('Приход'), findsNothing);
    await _club(tester, 'Молодёжный клуб храма Александра Невского');
    await _tap(tester, 'club-youth_leader');
    await _club(tester, 'Молодёжный клуб Покровского храма');
    await _tap(tester, 'club-user');
    expect(repo.saves, isEmpty);
    await _club(tester, 'Молодёжный клуб храма Александра Невского');
    expect(
      tester
          .widget<RadioListTile<String>>(
            find.byKey(const ValueKey('club-youth_leader')),
          )
          .selected,
      isTrue,
    );
    await _tap(tester, 'roles-save');
    expect(repo.saves, hasLength(1));
    expect(repo.saves.single.clubs, {'a': 'youth_leader', 'b': 'user'});
    expect(repo.saves.single.global, isNull);
    expect(repo.saves.single.actor, 'admin');
    expect(find.byType(RoleManagerDialog), findsOneWidget);
  });
  testWidgets(
    'guest warns, requires confirmation, preserves clubs and retries safely',
    (tester) async {
      final repo = _Roles()..fail = true;
      await _mount(tester, repo);
      await _open(tester);
      await _tap(tester, 'global-guest');
      expect(find.textContaining('аккаунт не удаляется'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('roles-save')))
            .onPressed,
        isNull,
      );
      await _tap(tester, 'confirm-guest');
      await _tap(tester, 'roles-save');
      expect(repo.saves, hasLength(1));
      expect(repo.saves.single.clubs, isEmpty);
      expect(repo.saves.single.global, 'guest');
      expect(find.text('Нет соединения'), findsOneWidget);
      repo.fail = false;
      await _tap(tester, 'roles-save');
      expect(repo.saves, hasLength(2));
      expect(repo.saves.first.request, repo.saves.last.request);
      expect(repo.clubRoles, {'a': 'user', 'b': 'youth_moderator'});
    },
  );
  testWidgets('save cannot run twice while a request is in flight', (
    tester,
  ) async {
    final repo = _Roles()..saving = Completer<void>();
    await _mount(tester, repo);
    await _open(tester);
    await _tap(tester, 'global-super_admin');
    final save = find.byKey(const ValueKey('roles-save'));
    await tester.tap(save);
    await tester.pump();
    await tester.tap(save);
    await tester.pump();
    expect(repo.saves, hasLength(1));
    repo.saving!.complete();
    await tester.pumpAndSettle();
    expect(repo.saves, hasLength(1));
  });
  testWidgets(
    'phone with large text edits inside same window and confirms discard',
    (tester) async {
      final repo = _Roles();
      await _mount(tester, repo, width: 390, scale: 1.6);
      await _open(tester);
      final original = tester.getSize(
        find.byKey(const ValueKey('role-manager-dialog')),
      );
      await _tap(tester, 'global-guest');
      await _tap(tester, 'roles-back');
      expect(find.text('Есть несохранённые изменения'), findsOneWidget);
      expect(repo.saves, isEmpty);
      await _tap(tester, 'roles-discard');
      expect(find.byKey(const ValueKey('role-person-anna')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('role-manager-dialog'))),
        original,
      );
      expect(tester.takeException(), isNull);
      await _tap(tester, 'roles-close');
      expect(find.byType(RoleManagerDialog), findsNothing);
    },
  );
  testWidgets('late search cannot replace newer results', (tester) async {
    final repo = _Roles()..slowSearch = Completer<List<RolePerson>>();
    await _mount(tester, repo);
    await tester.tap(find.text('Роли'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('roles-search'));
    await tester.enterText(search, 'Ан');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(search, 'Иван');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    repo.slowSearch!.complete([_Roles.peopleList.first]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('role-person-ivan')), findsOneWidget);
    expect(find.byKey(const ValueKey('role-person-anna')), findsNothing);
  });
  testWidgets(
    'account switch hides the previous person and blocks saving their draft',
    (tester) async {
      final users = StreamController<AppUser?>.broadcast();
      addTearDown(users.close);
      final repo = _Roles();
      await _mount(tester, repo, users: users.stream);
      users.add(const AppUser('admin'));
      await tester.pumpAndSettle();
      await _open(tester);
      await _tap(tester, 'global-guest');
      users.add(const AppUser('other'));
      await tester.pumpAndSettle();
      expect(find.text('anna@example.test'), findsNothing);
      expect(find.byKey(const ValueKey('roles-save')), findsNothing);
      expect(repo.saves, isEmpty);
      await _tap(tester, 'roles-close');
      expect(find.byType(RoleManagerDialog), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
