import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/features/auth/data/club_registration_repository.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/domain/auth_repository.dart';
import 'package:moy_prihod/features/auth/domain/email_auth_repository.dart';
import 'package:moy_prihod/features/auth/presentation/club_registration_dialog.dart';
import 'package:moy_prihod/features/auth/presentation/club_sky_scene.dart';
import 'package:moy_prihod/features/auth/presentation/club_welcome_art.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'club_registration_test.dart' as registration;

class ModalLogin implements AuthRepository {
  int calls = 0;
  bool reject = false;
  Completer<void>? pending;
  String? email;
  String? password;
  AppUser? user;
  @override
  Stream<AppUser?> watchUser() => Stream.value(user);
  @override
  Future<void> signIn(String email, String password) async {
    calls++;
    this.email = email;
    this.password = password;
    if (pending != null) await pending!.future;
    if (reject)
      throw const AuthException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );
    user = const AppUser('member');
  }

  @override
  Future<bool> signUp(String email, String password) =>
      throw StateError('Login must not register');
  @override
  Future<void> signOut() async {
    user = null;
  }
}

class RecordingRecovery implements EmailAuthRepository {
  final requests = <({String email, EmailPurpose purpose})>[];
  Completer<void>? pending;
  Object? failure;
  @override
  String? get currentUserId => null;
  @override
  Future<void> send(String email, EmailPurpose purpose) async {
    requests.add((email: email, purpose: purpose));
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<String> verify({
    required EmailPurpose purpose,
    String? email,
    String? code,
    String? tokenHash,
  }) => throw StateError('Only send is expected');
  @override
  Future<void> setPassword(String password, String expectedUserId) =>
      throw StateError('Only send is expected');
}

Finder keyed(String key) => find.byKey(ValueKey(key));
Animation<double> cloudDrift(WidgetTester tester) =>
    (tester.widget<CustomPaint>(keyed('club-sky-clouds')).painter!
            as SkyCloudsPainter)
        .drift;
Future<void> showLogin(WidgetTester tester) async {
  await tester.ensureVisible(keyed('club-show-sign-in'));
  await tester.tap(keyed('club-show-sign-in'));
  await tester.pumpAndSettle();
}

Future<void> showRecovery(WidgetTester tester) async {
  await tester.ensureVisible(keyed('club-forgot-password'));
  await tester.tap(keyed('club-forgot-password'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'same modal fades between forms, retains draft and keeps sky animation uninterrupted',
    (tester) async {
      final motion = ValueNotifier(true);
      addTearDown(motion.dispose);
      var closed = 0;
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        motion: motion,
        completed: (_) => closed++,
      );
      await registration.fillRegistration(tester);
      final draft = [
        for (var i = 0; i < 6; i++)
          tester.widget<TextFormField>(registration.field(i)).controller!.text,
      ];
      final background = tester.state<State<ClubWelcomeArt>>(
        find.byType(ClubWelcomeArt),
      );
      final animation = cloudDrift(tester);
      final bounds = tester.getRect(keyed('club-scene-surface'));
      await tester.ensureVisible(keyed('club-show-sign-in'));
      motion.value = false;
      await tester.pump();
      final start = animation.value;
      await tester.tap(keyed('club-show-sign-in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect(
        tester
            .widget<FadeTransition>(keyed('club-scene-content'))
            .opacity
            .value,
        inExclusiveRange(0.0, 1.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        tester
            .widget<FadeTransition>(keyed('club-scene-content'))
            .opacity
            .value,
        closeTo(0, .01),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(closed, 0);
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(identical(cloudDrift(tester), animation), isTrue);
      expect(animation.value, greaterThan(start));
      expect(
        identical(
          tester.state<State<ClubWelcomeArt>>(find.byType(ClubWelcomeArt)),
          background,
        ),
        isTrue,
      );
      expect(
        tester.widget<TextFormField>(registration.field(0)).controller!.text,
        draft[3],
      );
      // A newly created password is never silently used for logging in.
      expect(
        tester.widget<TextFormField>(registration.field(1)).controller!.text,
        isEmpty,
      );
      await registration.enter(tester, 1, 'existing-password');
      final beforeRecovery = animation.value;
      await tester.ensureVisible(keyed('club-forgot-password'));
      await tester.tap(keyed('club-forgot-password'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(
        tester
            .widget<FadeTransition>(keyed('club-scene-content'))
            .opacity
            .value,
        inExclusiveRange(0.0, 1.0),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(keyed('club-recovery-form'), findsOneWidget);
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(identical(cloudDrift(tester), animation), isTrue);
      expect(animation.value, greaterThan(beforeRecovery));
      expect(
        tester.widget<TextFormField>(registration.field(0)).controller!.text,
        draft[3],
      );
      expect(closed, 0);
      await tester.ensureVisible(keyed('club-recovery-back'));
      await tester.tap(keyed('club-recovery-back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(keyed('club-sign-in-form'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(registration.field(1)).controller!.text,
        'existing-password',
      );
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(identical(cloudDrift(tester), animation), isTrue);
      final beforeReturn = animation.value;
      await tester.ensureVisible(keyed('club-show-registration'));
      await tester.tap(keyed('club-show-registration'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(TextFormField), findsNWidgets(6));
      expect([
        for (var i = 0; i < 6; i++)
          tester.widget<TextFormField>(registration.field(i)).controller!.text,
      ], draft);
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(identical(cloudDrift(tester), animation), isTrue);
      expect(animation.value, greaterThan(beforeReturn));
      expect(closed, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mouse login keeps editor alive, deduplicates and reconnects after rejection',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final login = ModalLogin()
        ..pending = Completer<void>()
        ..reject = true;
      final signup = registration.RecordingRegistration();
      ClubRegistrationResult? result;
      await registration.mountRegistration(
        tester,
        signup,
        login: login,
        clubs: [],
        completed: (value) => result = value,
      );
      await showLogin(tester);
      await registration.enter(tester, 0, 'member@example.test');
      await registration.enter(tester, 1, 'wrong');
      final passwordField = registration.field(1);
      EditableText editor() => tester.widget<EditableText>(
        find.descendant(of: passwordField, matching: find.byType(EditableText)),
      );
      await tester.ensureVisible(keyed('club-sign-in-submit'));
      for (var i = 0; i < 6; i++) {
        await tester.tap(
          keyed('club-sign-in-submit'),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(login.calls, 1);
      expect(editor().focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(
        tester.widget<TextButton>(keyed('club-show-registration')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(keyed('club-forgot-password')).onPressed,
        isNull,
      );
      tester.testTextInput.reset();
      login.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Неверная почта или пароль.'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(editor().focusNode.hasFocus, isTrue);
      // Exercise deletion using the existing connection, not enterText/refocus.
      tester.testTextInput.updateEditingValue(const TextEditingValue());
      await tester.pump();
      expect(editor().controller.text, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'correct-password',
          selection: TextSelection.collapsed(offset: 16),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Показать Пароль'));
      await tester.pump();
      expect(editor().obscureText, isFalse);
      login
        ..pending = null
        ..reject = false;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(login.calls, 2);
      expect(login.email, 'member@example.test');
      expect(login.password, 'correct-password');
      expect(signup.requests, isEmpty);
      expect(result?.next, ClubRegistrationNext.club);
      expect(find.byType(ClubRegistrationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(foundation.TargetPlatform.macOS),
  );

  testWidgets(
    'reduced motion switches instantly and keeps login usable without a catalogue',
    (tester) async {
      final login = ModalLogin();
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        login: login,
        loadClubs: () async => throw StateError('catalogue offline'),
      );
      final sky = cloudDrift(tester);
      final before = sky.value;
      await showLogin(tester);
      expect(
        tester
            .widget<FadeTransition>(keyed('club-scene-content'))
            .opacity
            .value,
        1,
      );
      expect(cloudDrift(tester).value, before);
      await tester.ensureVisible(keyed('club-sign-in-submit'));
      await tester.tap(keyed('club-sign-in-submit'));
      await tester.pumpAndSettle();
      expect(login.calls, 0);
      expect(find.text('Введите корректный email'), findsOneWidget);
      await registration.enter(tester, 0, 'a@example.test');
      await registration.enter(tester, 1, 'short');
      await tester.ensureVisible(keyed('club-sign-in-submit'));
      await tester.tap(keyed('club-sign-in-submit'));
      await tester.pumpAndSettle();
      expect(login.calls, 1);
      expect(find.byType(ClubRegistrationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'closing during a form fade cancels safely and does not open another route',
    (tester) async {
      var closed = 0;
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        reducedMotion: false,
        completed: (_) => closed++,
      );
      await tester.ensureVisible(keyed('club-show-sign-in'));
      await tester.tap(keyed('club-show-sign-in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byTooltip('Закрыть регистрацию'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(ClubRegistrationDialog), findsNothing);
      expect(find.text('Открыть'), findsOneWidget);
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'forgot password stays inside the same modal with the entered email',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => openClubRegistration(context),
                child: const Text('Открыть'),
              ),
            ),
          ),
          GoRoute(
            path: '/auth/forgot-password',
            builder: (context, state) =>
                const Scaffold(body: Text('Unexpected page')),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [clubChoicesProvider.overrideWith((ref) async => [])],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ru'),
            supportedLocales: const [Locale('ru')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();
      await showLogin(tester);
      await registration.enter(tester, 0, '  member@example.test  ');
      await tester.ensureVisible(keyed('club-forgot-password'));
      await tester.tap(keyed('club-forgot-password'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/');
      expect(find.byType(ClubRegistrationDialog), findsOneWidget);
      expect(keyed('club-recovery-form'), findsOneWidget);
      expect(find.text('Unexpected page'), findsNothing);
      expect(find.text('Восстановление пароля'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        '  member@example.test  ',
      );
      expect(find.text('Отправить ссылку'), findsOneWidget);
      await tester.ensureVisible(keyed('club-recovery-back'));
      await tester.tap(keyed('club-recovery-back'));
      await tester.pumpAndSettle();
      expect(keyed('club-sign-in-form'), findsOneWidget);
      expect(router.state.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  test('clouds travel across the scene and wrap only offscreen', () {
    const size = Size(520, 173);
    for (var cloud = 0; cloud < 4; cloud++) {
      for (var step = 1; step <= 100; step++) {
        final previous = skyCloudPosition((step - 1) / 100, size, cloud).dx;
        final next = skyCloudPosition(step / 100, size, cloud).dx;
        if (next < previous) {
          expect(previous - size.width * .11, greaterThan(size.width));
          expect(next + size.width * .11, lessThan(0));
        } else {
          expect(next, greaterThan(previous));
        }
      }
    }
  });
  testWidgets(
    'recovery sends once and keeps its resend limit across form switches',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var now = DateTime.utc(2026, 9, 12, 10);
      final mail = RecordingRecovery()..pending = Completer<void>();
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        mail: mail,
        clock: () => now,
        clubs: [],
      );
      await showLogin(tester);
      await registration.enter(tester, 0, '  member@example.test  ');
      await showRecovery(tester);
      final bounds = tester.getRect(keyed('club-scene-surface'));
      expect(mail.requests, isEmpty);
      await tester.ensureVisible(keyed('club-recovery-submit'));
      for (var attempt = 0; attempt < 6; attempt++) {
        await tester.tap(
          keyed('club-recovery-submit'),
          kind: ui.PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(mail.requests, [
        (email: 'member@example.test', purpose: EmailPurpose.recovery),
      ]);
      expect(
        tester.widget<TextButton>(keyed('club-recovery-back')).onPressed,
        isNull,
      );
      mail.pending!.complete();
      await tester.pumpAndSettle();
      expect(keyed('club-recovery-feedback'), findsOneWidget);
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(find.text('Отправить снова через 60 с'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(keyed('club-recovery-submit')).onPressed,
        isNull,
      );
      await tester.ensureVisible(keyed('club-recovery-back'));
      await tester.tap(keyed('club-recovery-back'));
      await tester.pumpAndSettle();
      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      await showRecovery(tester);
      expect(find.text('Отправить снова через 30 с'), findsOneWidget);
      expect(mail.requests.length, 1);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Отправить ссылку'), findsOneWidget);
      mail.pending = null;
      await tester.ensureVisible(registration.field(0));
      await tester.showKeyboard(registration.field(0));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(mail.requests.length, 2);
      expect(find.byType(ClubRegistrationDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recovery validation and request failure preserve editable email',
    (tester) async {
      final mail = RecordingRecovery()
        ..pending = Completer<void>()
        ..failure = const AppFailure('Не удалось отправить ссылку.');
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        mail: mail,
      );
      await showLogin(tester);
      await showRecovery(tester);
      EditableText editor() => tester.widget<EditableText>(
        find.descendant(
          of: registration.field(0),
          matching: find.byType(EditableText),
        ),
      );
      await tester.showKeyboard(registration.field(0));
      tester.testTextInput.reset();
      await tester.ensureVisible(keyed('club-recovery-submit'));
      await tester.tap(
        keyed('club-recovery-submit'),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(mail.requests, isEmpty);
      expect(find.text('Введите корректный email'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      await registration.enter(tester, 0, 'member@example.test');
      await tester.ensureVisible(keyed('club-recovery-submit'));
      await tester.tap(
        keyed('club-recovery-submit'),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(mail.requests.length, 1);
      tester.testTextInput.reset();
      mail.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Не удалось отправить ссылку.'), findsOneWidget);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(editor().focusNode.hasFocus, isTrue);
      tester.testTextInput.updateEditingValue(const TextEditingValue());
      await tester.pump();
      expect(editor().controller.text, isEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'correct@example.test',
          selection: TextSelection.collapsed(offset: 20),
        ),
      );
      await tester.pump();
      expect(editor().controller.text, 'correct@example.test');
      await tester.tap(find.byTooltip('Закрыть регистрацию'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 61));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(foundation.TargetPlatform.macOS),
  );

  testWidgets(
    'recovery remains scrollable with large text on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await registration.mountRegistration(
        tester,
        registration.RecordingRegistration(),
        scale: 1.8,
      );
      await showLogin(tester);
      final bounds = tester.getRect(keyed('club-scene-surface'));
      await showRecovery(tester);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ClubWelcomeArt),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      await tester.ensureVisible(keyed('club-recovery-submit'));
      await tester.ensureVisible(keyed('club-recovery-back'));
      await tester.tap(keyed('club-recovery-back'));
      await tester.pumpAndSettle();
      expect(keyed('club-sign-in-form'), findsOneWidget);
      expect(tester.getRect(keyed('club-scene-surface')), bounds);
      expect(tester.takeException(), isNull);
    },
  );
}
