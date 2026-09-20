import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/application/email_auth_controller.dart';
import 'package:moy_prihod/features/auth/data/club_registration_repository.dart';
import 'package:moy_prihod/features/auth/domain/auth_repository.dart';
import 'package:moy_prihod/features/auth/domain/club_registration.dart';
import 'package:moy_prihod/features/auth/domain/email_auth_repository.dart';
import 'package:moy_prihod/features/auth/presentation/club_registration_dialog.dart';
import 'package:moy_prihod/features/auth/presentation/club_welcome_art.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecordingRegistration implements ClubRegistrationRepository {
  final requests = <ClubRegistration>[];
  Completer<bool> response = Completer<bool>();
  @override
  Future<bool> register(ClubRegistration registration) {
    requests.add(registration);
    return response.future;
  }
}

Future<void> mountRegistration(
  WidgetTester tester,
  RecordingRegistration repository, {
  double scale = 1,
  String? youthId,
  AuthRepository? login,
  EmailAuthRepository? mail,
  DateTime Function()? clock,
  bool reducedMotion = true,
  bool accountOnly = false,
  ValueNotifier<bool>? motion,
  Future<List<ClubChoice>> Function()? loadClubs,
  List<ClubChoice> clubs = const [
    ClubChoice(
      id: 'club-1',
      name: 'Молодёжный клуб',
      parishName: 'Тестовый приход',
    ),
  ],
  ValueChanged<ClubRegistrationResult?>? completed,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (login != null) authRepositoryProvider.overrideWithValue(login),
        if (mail != null) emailAuthRepositoryProvider.overrideWithValue(mail),
        if (clock != null) authClockProvider.overrideWithValue(clock),
        clubRegistrationRepositoryProvider.overrideWithValue(repository),
        clubChoicesProvider.overrideWith(
          (ref) async => loadClubs == null ? clubs : await loadClubs(),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          Widget media(bool reduced) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          );
          return motion == null
              ? media(reducedMotion)
              : ValueListenableBuilder<bool>(
                  valueListenable: motion,
                  builder: (context, reduced, _) => media(reduced),
                );
        },
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final result = await showDialog<ClubRegistrationResult>(
                  context: context,
                  builder: (_) => ClubRegistrationDialog(
                    youthId: youthId,
                    accountOnly: accountOnly,
                  ),
                );
                completed?.call(result);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Finder field(int index) => find.byType(TextFormField).at(index);
Future<void> enter(WidgetTester tester, int index, String value) async {
  await tester.ensureVisible(field(index));
  await tester.enterText(field(index), value);
  await tester.pump();
}

Future<void> fillRegistration(WidgetTester tester) async {
  await enter(tester, 0, ' Анна ');
  await enter(tester, 1, ' Иванова ');
  await tester.ensureVisible(field(2));
  await tester.tap(field(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Выбрать'));
  await tester.pumpAndSettle();
  await enter(tester, 3, 'anna@example.test');
  await enter(tester, 4, 'example-secret-123');
  await enter(tester, 5, 'example-secret-123');
}

Future<void> submit(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('club-register-submit'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  for (final emptyCatalogue in [false, true]) {
    for (final index in [4, 5]) {
      testWidgets(
        'password $index reconnects after repeated mouse submits with ${emptyCatalogue ? 'no clubs' : 'invalid fields'}',
        (tester) async {
          tester.view.physicalSize = const Size(1000, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = RecordingRegistration();
          await mountRegistration(
            tester,
            repo,
            clubs: emptyCatalogue
                ? []
                : const [
                    ClubChoice(
                      id: 'club-1',
                      name: 'Клуб',
                      parishName: 'Приход',
                    ),
                  ],
          );
          await enter(tester, 0, 'Анна');
          await enter(tester, 3, 'anna@example.test');
          await enter(tester, index, '1');
          final button = find.byKey(const ValueKey('club-register-submit'));
          await tester.ensureVisible(button);
          await tester.pump();
          EditableText editing() => tester.widget<EditableText>(
            find.descendant(
              of: field(index),
              matching: find.byType(EditableText),
            ),
          );
          for (var attempt = 0; attempt < 6; attempt++) {
            expect(editing().focusNode.hasFocus, isTrue);
            // Model a browser client vanishing silently while Flutter still
            // considers the field focused. Do not refocus it to repair the test.
            tester.testTextInput.reset();
            expect(tester.testTextInput.hasAnyClients, isFalse);
            await tester.tap(button, kind: ui.PointerDeviceKind.mouse);
            await tester.pumpAndSettle();
            expect(repo.requests, isEmpty);
            expect(tester.testTextInput.hasAnyClients, isTrue);
            expect(editing().focusNode.hasFocus, isTrue);
            expect(editing().controller.text, '1');
          }
          if (!emptyCatalogue) {
            expect(find.text('Минимум 12 символов'), findsOneWidget);
          }
          // Delete and type using the recovered native channel only.
          tester.testTextInput.updateEditingValue(const TextEditingValue());
          await tester.pump();
          expect(editing().controller.text, isEmpty);
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '123456789012',
              selection: TextSelection.collapsed(offset: 12),
            ),
          );
          await tester.pump();
          expect(editing().controller.text, '123456789012');
          expect(
            tester.widget<TextFormField>(field(0)).controller!.text,
            'Анна',
          );
          expect(
            tester.widget<TextFormField>(field(3)).controller!.text,
            'anna@example.test',
          );
          expect(find.text('Заявка отправлена'), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(foundation.TargetPlatform.macOS),
      );
    }
  }

  testWidgets(
    'Enter validation and password visibility keep the repeat field editable',
    (tester) async {
      final repo = RecordingRegistration();
      await mountRegistration(tester, repo);
      await enter(tester, 4, '1');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      EditableText repeat() => tester.widget<EditableText>(
        find.descendant(of: field(5), matching: find.byType(EditableText)),
      );
      expect(repeat().focusNode.hasFocus, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '1',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(repeat().focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        expect(repo.requests, isEmpty);
      }
      await tester.ensureVisible(field(5));
      await tester.tap(find.byTooltip('Показать Подтверждение пароля'));
      await tester.pump();
      expect(repeat().obscureText, isFalse);
      tester.testTextInput.updateEditingValue(const TextEditingValue());
      await tester.pump();
      expect(repeat().controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mouse submits preserve editing while waiting and recover the latest focused draft',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = RecordingRegistration();
      await mountRegistration(tester, repo);
      await fillRegistration(tester);
      final button = find.byKey(const ValueKey('club-register-submit'));
      await tester.ensureVisible(button);
      for (var attempt = 0; attempt < 6; attempt++) {
        await tester.tap(button, kind: ui.PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(repo.requests, hasLength(1));
      final repeat = tester.widget<EditableText>(
        find.descendant(of: field(5), matching: find.byType(EditableText)),
      );
      expect(repeat.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      // Users can correct another field while the original request is pending.
      await enter(tester, 3, 'corrected@example.test');
      const corrected = TextEditingValue(
        text: 'corrected@example.test',
        selection: TextSelection.collapsed(offset: 4),
      );
      tester.testTextInput.updateEditingValue(corrected);
      await tester.pump();
      tester.testTextInput.reset();
      repo.response.completeError(
        const AppFailure('Проверьте данные регистрации.'),
      );
      await tester.pumpAndSettle();
      final email = tester.widget<EditableText>(
        find.descendant(of: field(3), matching: find.byType(EditableText)),
      );
      expect(email.focusNode.hasFocus, isTrue);
      expect(email.controller.value, corrected);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.updateEditingValue(const TextEditingValue());
      await tester.pump();
      expect(email.controller.text, isEmpty);
      expect(repo.requests.single.email, 'anna@example.test');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(foundation.TargetPlatform.macOS),
  );

  test('missing catalogue and timeout have actionable messages', () {
    expect(
      clubChoicesError(
        const PostgrestException(message: 'missing function', code: 'PGRST202'),
      ),
      'Приём заявок пока не настроен. Сообщите администратору приложения.',
    );
    expect(
      clubChoicesError(TimeoutException('timeout')),
      contains('повторите попытку'),
    );
  });

  testWidgets(
    'continue responds during catalogue loading without duplicate loads or signup',
    (tester) async {
      final pending = Completer<List<ClubChoice>>();
      var loads = 0;
      final repo = RecordingRegistration();
      await mountRegistration(
        tester,
        repo,
        loadClubs: () {
          loads++;
          return pending.future;
        },
      );
      final button = find.byKey(const ValueKey('club-register-submit'));
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await submit(tester);
      await submit(tester);
      expect(
        find.text(
          'Подготавливаем отправку. Подождите немного и нажмите «Продолжить» снова.',
        ),
        findsOneWidget,
      );
      expect(loads, 1);
      expect(repo.requests, isEmpty);
      pending.complete(const [
        ClubChoice(id: 'ready', name: 'Клуб', parishName: 'Приход'),
      ]);
      await tester.pumpAndSettle();
      await fillRegistration(tester);
      await submit(tester);
      expect(repo.requests.single.youthId, 'ready');
      repo.response.complete(true);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'continue retries a failed catalogue and retains editable fields',
    (tester) async {
      var loads = 0;
      final repo = RecordingRegistration();
      await mountRegistration(
        tester,
        repo,
        loadClubs: () async {
          loads++;
          if (loads == 1) throw const AppFailure('catalogue unavailable');
          return const [
            ClubChoice(id: 'restored', name: 'Клуб', parishName: 'Приход'),
          ];
        },
      );
      await fillRegistration(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(repo.requests, isEmpty);
      expect(
        tester.widget<TextFormField>(field(0)).controller!.text.trim(),
        'Анна',
      );
      await submit(tester);
      expect(repo.requests.single.youthId, 'restored');
      repo.response.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Заявка отправлена'), findsOneWidget);
    },
  );

  testWidgets(
    'form fades out before receipt fades in without replacing background or modal',
    (tester) async {
      final repo = RecordingRegistration();
      final motion = ValueNotifier(true);
      addTearDown(motion.dispose);
      await mountRegistration(tester, repo, motion: motion);
      await fillRegistration(tester);
      await submit(tester);
      final surface = find.byKey(const ValueKey('club-scene-surface'));
      final bounds = tester.getRect(surface);
      final art = tester.state<State<ClubWelcomeArt>>(
        find.byType(ClubWelcomeArt),
      );
      motion.value = false;
      await tester.pump();
      repo.response.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(find.text('Заявка отправлена'), findsNothing);
      final fade = find.byKey(const ValueKey('club-scene-content'));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0.0, 1.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Заявка отправлена'), findsOneWidget);
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        closeTo(0, .01),
      );
      await tester.pump(const Duration(milliseconds: 190));
      expect(
        tester.widget<FadeTransition>(fade).opacity.value,
        inExclusiveRange(0.0, 1.0),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(tester.getRect(surface), bounds);
      expect(
        identical(
          tester.state<State<ClubWelcomeArt>>(find.byType(ClubWelcomeArt)),
          art,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Понятно'));
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
    },
  );

  for (final target in <String?>[null, 'second', 'unavailable']) {
    testWidgets('club names stay hidden and destination $target is validated', (
      tester,
    ) async {
      final repo = RecordingRegistration();
      await mountRegistration(
        tester,
        repo,
        youthId: target,
        clubs: const [
          ClubChoice(id: 'first', name: 'Первый', parishName: 'Приход А'),
          ClubChoice(id: 'second', name: 'Второй', parishName: 'Приход Б'),
        ],
      );
      expect(find.byKey(const ValueKey('club-choice')), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      for (final label in [
        'Первый',
        'Второй',
        'Приход А',
        'Приход Б',
        'Молодёжный клуб',
      ]) {
        expect(find.textContaining(label), findsNothing);
      }
      await fillRegistration(tester);
      await submit(tester);
      if (target == 'second') {
        expect(repo.requests.single.youthId, 'second');
        repo.response.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Заявка отправлена'), findsOneWidget);
      } else {
        expect(repo.requests, isEmpty);
        expect(
          find.text('Приём заявок временно недоступен. Попробуйте позже.'),
          findsOneWidget,
        );
      }
    });
  }

  testWidgets('no club prevents signup without claiming a request was sent', (
    tester,
  ) async {
    final repo = RecordingRegistration();
    await mountRegistration(tester, repo, clubs: []);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('club-register-submit')),
          )
          .onPressed,
      isNotNull,
    );
    await fillRegistration(tester);
    await submit(tester);
    expect(repo.requests, isEmpty);
    expect(find.text('Заявка отправлена'), findsNothing);
    expect(
      find.text('Приём заявок временно недоступен. Попробуйте позже.'),
      findsOneWidget,
    );
  });

  testWidgets('pending receipt remains scrollable with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = RecordingRegistration();
    await mountRegistration(tester, repo, scale: 1.8);
    await fillRegistration(tester);
    await submit(tester);
    repo.response.complete(true);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Понятно'));
    await tester.tap(find.text('Понятно'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ClubRegistrationDialog), findsNothing);
  });

  testWidgets(
    'invalid form never sends; successful signup carries personal fields and confirms email',
    (tester) async {
      final repo = RecordingRegistration();
      ClubRegistrationResult? result;
      await mountRegistration(
        tester,
        repo,
        completed: (value) => result = value,
      );
      await submit(tester);
      expect(repo.requests, isEmpty);
      await fillRegistration(tester);
      expect(find.textContaining('Молодёжный клуб:'), findsNothing);
      expect(find.textContaining('Тестовый приход'), findsNothing);
      expect(find.byKey(const ValueKey('club-choice')), findsNothing);
      await submit(tester);
      await submit(tester);
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.givenName, 'Анна');
      expect(repo.requests.single.familyName, 'Иванова');
      expect(
        repo.requests.single.metadata['club_registration'],
        containsPair('given_name', 'Анна'),
      );
      final background = tester.state<State<ClubWelcomeArt>>(
        find.byType(ClubWelcomeArt),
      );
      final bounds = tester.getRect(
        find.byKey(const ValueKey('club-scene-surface')),
      );
      repo.response.complete(true);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
        tester.getRect(find.byKey(const ValueKey('club-scene-surface'))),
        bounds,
      );
      expect(
        identical(
          tester.state<State<ClubWelcomeArt>>(find.byType(ClubWelcomeArt)),
          background,
        ),
        isTrue,
      );
      expect(find.text('Заявка отправлена'), findsOneWidget);
      expect(find.text('Статус: на рассмотрении'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(repo.requests.single.youthId, 'club-1');
      expect(repo.requests.single.receiptKey, isNotEmpty);
      await tester.ensureVisible(find.text('Понятно'));
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(find.byType(ClubRegistrationDialog), findsNothing);
      expect(result, isNull);
    },
  );

  testWidgets(
    'server rejection preserves draft and reconnects editable password for retry',
    (tester) async {
      final repo = RecordingRegistration();
      await mountRegistration(tester, repo);
      await fillRegistration(tester);
      await submit(tester);
      repo.response.completeError(
        const AppFailure('Проверьте данные регистрации.'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Проверьте данные регистрации.'), findsOneWidget);
      await tester.ensureVisible(field(4));
      await tester.tap(field(4));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('new-secret-45678');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(field(4)).controller!.text,
        'new-secret-45678',
      );
      await enter(tester, 5, 'new-secret-45678');
      repo.response = Completer<bool>();
      await submit(tester);
      expect(repo.requests, hasLength(2));
      expect(repo.requests.last.password, 'new-secret-45678');
      expect(repo.requests.last.givenName, 'Анна');
      expect(repo.requests.last.receiptKey, repo.requests.first.receiptKey);
      expect(find.text('Заявка отправлена'), findsNothing);
      repo.response.complete(true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing during signup leaves the public page and ignores late completion',
    (tester) async {
      final repo = RecordingRegistration();
      ClubRegistrationResult? result;
      await mountRegistration(
        tester,
        repo,
        completed: (value) => result = value,
      );
      await fillRegistration(tester);
      await submit(tester);
      await tester.tap(find.byTooltip('Закрыть регистрацию'));
      await tester.pumpAndSettle();
      repo.response.complete(true);
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('Открыть'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow enlarged registration scrolls to every field and login', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountRegistration(tester, RecordingRegistration(), scale: 1.8);
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.ensureVisible(field(i));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('club-show-sign-in')));
    await tester.tap(find.byKey(const ValueKey('club-show-sign-in')));
    await tester.pumpAndSettle();
    expect(find.byType(ClubRegistrationDialog), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.ensureVisible(
      find.byKey(const ValueKey('club-show-registration')),
    );
    await tester.tap(find.byKey(const ValueKey('club-show-registration')));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
