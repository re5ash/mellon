import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/membership/application/membership_providers.dart';
import 'package:moy_prihod/features/profile/application/profile_providers.dart';
import 'package:moy_prihod/features/profile/domain/profile_repository.dart';
import 'package:moy_prihod/features/profile/domain/user_profile.dart';
import 'package:moy_prihod/features/profile/presentation/profile_details_page.dart';
import 'package:moy_prihod/features/profile/presentation/profile_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

UserProfile profile({String id = 'account-a', String name = 'Анна'}) =>
    UserProfile(
      userId: id,
      displayName: name,
      givenName: 'Личное имя',
      familyName: 'Личная фамилия',
      birthDate: DateTime(1994, 8, 6),
      visibility: ProfileVisibility.private,
      profileRevision: 3,
      privateRevision: 4,
    );

class FakeProfileRepository implements ProfileRepository {
  UserProfile current = profile();
  final writes = <ProfileInput>[];
  int reads = 0;
  Completer<UserProfile>? pendingSave;
  Object? readError;

  @override
  Future<UserProfile> read() async {
    reads++;
    if (readError != null) throw readError!;
    return current;
  }

  @override
  Future<UserProfile> save(ProfileInput input) async {
    writes.add(input);
    if (pendingSave != null) return pendingSave!.future;
    current = UserProfile(
      userId: input.expectedUserId,
      displayName: input.displayName.trim(),
      givenName: input.givenName.trim(),
      familyName: input.familyName.trim(),
      birthDate: input.birthDate,
      visibility: input.visibility,
      profileRevision: input.profileRevision + 1,
      privateRevision: input.privateRevision + 1,
    );
    return current;
  }
}

Future<void> mount(
  WidgetTester tester,
  FakeProfileRepository repository, {
  Stream<AppUser?>? users,
  bool guest = false,
  ThemeData? theme,
  bool largeTextAndKeyboard = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWith(
          (ref) async => {'welcome_text': '', 'support_email': ''},
        ),
        profileRepositoryProvider.overrideWithValue(repository),
        authUserProvider.overrideWith(
          (ref) =>
              users ?? Stream.value(guest ? null : const AppUser('account-a')),
        ),
        currentMembershipProvider.overrideWith((ref) async => null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => largeTextAndKeyboard
            ? MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.8),
                  viewInsets: const EdgeInsets.only(bottom: 260),
                ),
                child: child!,
              )
            : child!,
        home: guest
            ? const Scaffold(body: ProfilePage())
            : const ProfileDetailsPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String key) => find.byKey(ValueKey('profile-$key'));
String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(field(key)).controller!.text;

void main() {
  test(
    'date-only RPC payload has no timezone conversion and pins expected account',
    () {
      final input = ProfileInput(
        expectedUserId: 'account-a',
        displayName: ' Анна ',
        givenName: '',
        familyName: '',
        visibility: ProfileVisibility.private,
        birthDate: DateTime.utc(2000, 2, 29),
        profileRevision: 3,
        privateRevision: 4,
      );
      expect(input.toRpc()['p_birth_date'], '2000-02-29');
      expect(input.toRpc()['p_display_name'], 'Анна');
      expect(input.toRpc()['p_expected_user_id'], 'account-a');
      expect(calendarDate(DateTime(2000, 2, 29)), '2000-02-29');
    },
  );

  testWidgets(
    'guest sees appearance and sign-in without fetching personal data',
    (tester) async {
      final repository = FakeProfileRepository();
      await mount(tester, repository, guest: true);
      expect(repository.reads, 0);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Войти'), findsOneWidget);
      expect(find.byKey(const ValueKey('open-appearance')), findsOneWidget);
    },
  );

  testWidgets(
    'required display name validates and save preserves private default',
    (tester) async {
      final repository = FakeProfileRepository();
      await mount(tester, repository);
      await tester.enterText(field('display-name'), ' ');
      await tapVisible(tester, find.text('Сохранить профиль'));
      expect(repository.writes, isEmpty);
      expect(find.text('Введите отображаемое имя'), findsOneWidget);
      await tester.enterText(field('display-name'), 'Анна новая');
      await tester.enterText(field('given-name'), 'Личное новое');
      await tapVisible(tester, find.text('Сохранить профиль'));
      expect(repository.writes.single.visibility, ProfileVisibility.private);
      expect(repository.writes.single.expectedUserId, 'account-a');
      expect(repository.current.givenName, 'Личное новое');
      expect(find.text('Профиль сохранён'), findsOneWidget);
      expect(
        repository.reads,
        1,
        reason:
            'The committed RPC response updates the cache without another read.',
      );
    },
  );

  testWidgets(
    'busy save blocks duplicate submission; network error retains input for retry',
    (tester) async {
      final repository = FakeProfileRepository()
        ..pendingSave = Completer<UserProfile>();
      await mount(tester, repository);
      await tester.enterText(field('family-name'), 'Новая фамилия');
      await tapVisible(tester, find.text('Сохранить профиль'));
      expect(repository.writes.length, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextFormField>(field('family-name')).enabled,
        isFalse,
      );
      repository.pendingSave!.completeError(StateError('network unavailable'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'family-name'), 'Новая фамилия');
      expect(find.textContaining('Проверьте соединение'), findsOneWidget);
      repository.pendingSave = null;
      await tapVisible(tester, find.text('Сохранить профиль'));
      expect(repository.writes.length, 2);
      expect(repository.writes.first.toRpc(), repository.writes.last.toRpc());
      expect(find.text('Профиль сохранён'), findsOneWidget);
    },
  );

  testWidgets(
    'conflict keeps draft; reload requires confirmation and supplies fresh versions',
    (tester) async {
      final repository = FakeProfileRepository()
        ..pendingSave = Completer<UserProfile>();
      await mount(tester, repository);
      await tester.enterText(field('display-name'), 'Мой черновик');
      await tapVisible(tester, find.text('Сохранить профиль'));
      repository.pendingSave!.completeError(
        const PostgrestException(
          message: 'profile_edit_conflict',
          code: '40001',
        ),
      );
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'display-name'), 'Мой черновик');
      expect(
        find.textContaining('Профиль изменён в другом окне'),
        findsOneWidget,
      );
      repository.pendingSave = null;
      repository.current = profile(name: 'Сохранено в другом окне');
      await tapVisible(tester, find.text('Загрузить сохранённое'));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'display-name'), 'Мой черновик');
      await tapVisible(tester, find.text('Загрузить сохранённое'));
      await tester.tap(find.text('Загрузить'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'display-name'), 'Сохранено в другом окне');
    },
  );

  testWidgets('date can be removed and visibility explicitly enabled', (
    tester,
  ) async {
    final repository = FakeProfileRepository();
    await mount(tester, repository);
    await tapVisible(tester, find.text('Убрать дату'));
    await tapVisible(tester, find.byType(SwitchListTile));
    await tapVisible(tester, find.text('Сохранить профиль'));
    expect(repository.writes.single.birthDate, isNull);
    expect(repository.writes.single.toRpc()['p_birth_date'], isNull);
    expect(repository.writes.single.visibility, ProfileVisibility.parish);
  });

  testWidgets(
    'date picker uses persisted birthday; cancel leaves date intact',
    (tester) async {
      final repository = FakeProfileRepository();
      await mount(tester, repository);
      await tapVisible(tester, find.text('Изменить дату'));
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(dialog.initialDate, DateTime(1994, 8, 6));
      expect(dialog.firstDate, DateTime(1900));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Сохранить профиль'));
      expect(repository.writes.single.birthDate, DateTime(1994, 8, 6));
    },
  );

  testWidgets(
    'token refresh retains draft, account switch and sign-out clear old personal fields',
    (tester) async {
      final repository = FakeProfileRepository();
      final users = StreamController<AppUser?>.broadcast();
      addTearDown(users.close);
      Stream<AppUser?> session() async* {
        yield const AppUser('account-a');
        yield* users.stream;
      }

      await mount(tester, repository, users: session());
      await tester.enterText(field('given-name'), 'Секрет первого аккаунта');
      final reads = repository.reads;
      users.add(AppUser(repository.current.userId));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'given-name'), 'Секрет первого аккаунта');
      expect(repository.reads, reads);
      repository.current = profile(id: 'account-b', name: 'Борис');
      users.add(const AppUser('account-b'));
      await tester.pumpAndSettle();
      expect(fieldText(tester, 'display-name'), 'Борис');
      expect(fieldText(tester, 'given-name'), isNot('Секрет первого аккаунта'));
      users.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Войти'), findsOneWidget);
    },
  );

  testWidgets(
    'failed profile load offers retry without exposing server error details',
    (tester) async {
      final repository = FakeProfileRepository()
        ..readError = StateError('Sensitive server payload');
      await mount(tester, repository);
      expect(find.textContaining('Sensitive'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      repository.readError = null;
      await tapVisible(tester, find.text('Повторить'));
      expect(fieldText(tester, 'display-name'), 'Анна');
    },
  );

  for (final size in [
    const Size(320, 640),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    testWidgets(
      'profile is scrollable at $size with large text, keyboard and dark theme',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FakeProfileRepository();
        await mount(
          tester,
          repository,
          theme: AppTheme.dark,
          largeTextAndKeyboard: true,
        );
        expect(tester.takeException(), isNull);
        await tapVisible(tester, find.text('Сохранить профиль'));
        expect(repository.writes.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
