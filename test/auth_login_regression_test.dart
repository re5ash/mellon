import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/features/auth/application/auth_controller.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/auth/domain/auth_repository.dart';
import 'package:moy_prihod/features/auth/presentation/auth_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginRepository implements AuthRepository {
  AppUser? user;
  bool reject = false;
  Completer<void>? pending;
  int calls = 0;

  // Snapshot only: deliberately omit a live signed-in notification.
  @override
  Stream<AppUser?> watchUser() => Stream.value(user);
  @override
  Future<void> signIn(String email, String password) async {
    calls++;
    if (pending != null) await pending!.future;
    if (reject) {
      throw const AuthException(
        'Invalid login credentials',
        code: 'invalid_credentials',
      );
    }
    user = const AppUser('test-user');
  }

  @override
  Future<bool> signUp(String email, String password) async => true;
  @override
  Future<void> signOut() async {
    user = null;
  }
}

void main() {
  testWidgets(
    'Enter retries after failure, refreshes session and leaves login without reload',
    (tester) async {
      final repository = LoginRepository()..reject = true;
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(authUserProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(authUserProvider.future);
      final router = GoRouter(
        initialLocation: '/auth?from=/my-parish',
        routes: [
          GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
          GoRoute(
            path: '/my-parish',
            builder: (_, _) => const Scaffold(body: Text('Приход открыт')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.at(1), 'a-long-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(container.read(authControllerProvider).hasError, isTrue);
      // The user can edit the password after an unsuccessful attempt.
      repository.reject = false;
      await tester.enterText(fields.at(1), 'a-new-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Приход открыт'), findsOneWidget);
      expect((await container.read(authUserProvider.future))?.id, 'test-user');
      expect(container.read(authControllerProvider).isLoading, isFalse);
    },
  );

  testWidgets(
    'stalled login unlocks the fields and rejects duplicate submission',
    (tester) async {
      final repository = LoginRepository()..pending = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          authRequestTimeoutProvider.overrideWithValue(
            const Duration(seconds: 1),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AuthPage()),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.at(1), 'a-long-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await container
          .read(authControllerProvider.notifier)
          .submit(
            email: 'test@example.com',
            password: 'duplicate',
            register: false,
          );
      expect(repository.calls, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider).isLoading, isFalse);
      await tester.enterText(fields.at(1), '');
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        isEmpty,
      );
      final stateAfterEdit = container.read(authControllerProvider);
      // Completing the old request must not overwrite the edited form state.
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(container.read(authControllerProvider), same(stateAfterEdit));
    },
  );
  for (final useEnter in [true, false]) {
    testWidgets(
      'delayed invalid credentials preserves native editing after ${useEnter ? 'Enter' : 'button'}',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = LoginRepository()
          ..reject = true
          ..pending = Completer<void>();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final router = GoRouter(
          initialLocation: '/auth',
          routes: [
            GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
            GoRoute(
              path: '/my-parish',
              builder: (_, _) => const Scaffold(body: Text('Приход открыт')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        final password = fields.at(1);
        await tester.enterText(fields.first, 'test@example.com');
        await tester.enterText(password, 'incorrect-password');
        if (useEnter) {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        } else {
          await tester.tap(
            find.widgetWithText(FilledButton, 'Войти'),
            kind: ui.PointerDeviceKind.mouse,
          );
        }
        // Render the loading frame BEFORE the asynchronous rejection.
        await tester.pump();
        expect(container.read(authControllerProvider).isLoading, isTrue);
        expect(tester.widget<TextFormField>(password).enabled, isNot(false));
        expect(repository.calls, 1);
        repository.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Неверная почта или пароль.'), findsOneWidget);
        expect(container.read(authControllerProvider).isLoading, isFalse);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(
                  of: password,
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(tester.testTextInput.hasAnyClients, isTrue);
        // Simulate deletion through the existing input connection. Unlike
        // enterText(), this does not re-focus or reconnect the field.
        tester.testTextInput.updateEditingValue(const TextEditingValue());
        await tester.pump();
        expect(
          tester.widget<TextFormField>(password).controller!.text,
          isEmpty,
        );
        expect(find.text('Неверная почта или пароль.'), findsNothing);
        repository
          ..reject = false
          ..pending = null;
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'correct-password',
            selection: TextSelection.collapsed(offset: 16),
          ),
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(repository.calls, 2);
        expect(find.text('Приход открыт'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'rapid clicks keep the login button stationary and input editable over six failures',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = LoginRepository()..reject = true;
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(path: '/auth', builder: (_, _) => const AuthPage()),
          GoRoute(
            path: '/my-parish',
            builder: (_, _) => const Scaffold(body: Text('Приход открыт')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'test@example.com');
      await tester.enterText(fields.at(1), '1');
      await tester.pumpAndSettle();
      final buttonPosition = tester.getCenter(
        find.widgetWithText(FilledButton, 'Войти'),
      );
      const attempts = [
        '1',
        '11111111111',
        'a',
        'abcdefghijk',
        '0',
        '123456789012',
      ];
      for (var round = 0; round < attempts.length; round++) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: attempts[round],
            selection: TextSelection.collapsed(offset: attempts[round].length),
          ),
        );
        await tester.pump();
        repository.pending = Completer<void>();
        // Keep the physical pointer location unchanged, like a rapid click burst.
        for (var click = 0; click < 6; click++) {
          await tester.tapAt(buttonPosition, kind: ui.PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(repository.calls, round + 1);
        expect(container.read(authControllerProvider).isLoading, isTrue);
        repository.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Неверная почта или пароль.'), findsOneWidget);
        expect(
          tester.getCenter(find.widgetWithText(FilledButton, 'Войти')),
          buttonPosition,
        );
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(tester.testTextInput.hasAnyClients, isTrue);
        // Delete through the existing connection, without re-focusing it.
        tester.testTextInput.updateEditingValue(const TextEditingValue());
        await tester.pump();
        expect(
          tester.widget<TextFormField>(fields.at(1)).controller!.text,
          isEmpty,
        );
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '123456789012',
            selection: TextSelection.collapsed(offset: 12),
          ),
        );
        await tester.pump();
        expect(
          tester.widget<TextFormField>(fields.at(1)).controller!.text,
          '123456789012',
        );
        expect(tester.takeException(), isNull);
      }
      repository
        ..reject = false
        ..pending = null;
      await tester.tapAt(buttonPosition, kind: ui.PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('Приход открыт'), findsOneWidget);
    },
  );

  testWidgets(
    'late rejection does not steal focus while email is being corrected',
    (tester) async {
      final repository = LoginRepository()
        ..reject = true
        ..pending = Completer<void>();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AuthPage()),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'wrong@example.com');
      await tester.enterText(fields.at(1), 'incorrect-password');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(fields.first);
      await tester.pump();
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'correct@example.com',
          selection: TextSelection.collapsed(offset: 19),
        ),
      );
      await tester.pump();
      repository.pending!.complete();
      await tester.pumpAndSettle();
      final editableEmail = tester.widget<EditableText>(
        find.descendant(of: fields.first, matching: find.byType(EditableText)),
      );
      expect(editableEmail.focusNode.hasFocus, isTrue);
      expect(editableEmail.controller.text, 'correct@example.com');
      tester.testTextInput.updateEditingValue(const TextEditingValue());
      await tester.pump();
      expect(editableEmail.controller.text, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final editEmail in [false, true]) {
    testWidgets(
      'silent native input loss recovers ${editEmail ? 'email' : 'password'} editing after mouse login',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = LoginRepository()
          ..reject = true
          ..pending = Completer<void>();
        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: AuthPage()),
          ),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.first, 'test@example.com');
        await tester.enterText(fields.at(1), '12345678901');
        final button = find.widgetWithText(FilledButton, 'Войти');
        final buttonPosition = tester.getCenter(button);
        final passwordBefore = tester.widget<EditableText>(
          find.descendant(
            of: fields.at(1),
            matching: find.byType(EditableText),
          ),
        );
        for (var click = 0; click < 5; click++) {
          await tester.tapAt(buttonPosition, kind: ui.PointerDeviceKind.mouse);
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(repository.calls, 1);
        expect(container.read(authControllerProvider).isLoading, isTrue);
        // Mouse clicks on the form's submit button must keep native editing
        // alive, including clicks while the button is disabled.
        expect(passwordBefore.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.hasAnyClients, isTrue);

        final editedField = editEmail ? fields.first : fields.at(1);
        if (editEmail) {
          await tester.tap(editedField, kind: ui.PointerDeviceKind.mouse);
          await tester.pump();
        }
        final editedValue = editEmail
            ? const TextEditingValue(
                text: 'correct@example.com',
                selection: TextSelection.collapsed(offset: 7),
              )
            : const TextEditingValue(
                text: '123456789012',
                selection: TextSelection.collapsed(offset: 12),
              );
        tester.testTextInput.updateEditingValue(editedValue);
        await tester.pump();
        final editableBefore = tester.widget<EditableText>(
          find.descendant(of: editedField, matching: find.byType(EditableText)),
        );
        // Simulate a browser-side editor disappearing without notifying Dart:
        // the keyboard backend has no client, but Flutter still has focus.
        // This is a protocol regression test, not a real DOM/Chrome test.
        tester.testTextInput.reset();
        expect(tester.testTextInput.hasAnyClients, isFalse);
        expect(editableBefore.focusNode.hasFocus, isTrue);
        repository.pending!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Неверная почта или пароль.'), findsOneWidget);
        expect(tester.testTextInput.hasAnyClients, isTrue);
        final editableAfter = tester.widget<EditableText>(
          find.descendant(of: editedField, matching: find.byType(EditableText)),
        );
        expect(editableAfter.focusNode.hasFocus, isTrue);
        expect(editableAfter.controller.text, editedValue.text);
        expect(editableAfter.controller.selection, editedValue.selection);
        // No enterText/showKeyboard/tap here: use only the recovered channel.
        tester.testTextInput.updateEditingValue(const TextEditingValue());
        await tester.pump();
        expect(editableAfter.controller.text, isEmpty);
        tester.testTextInput.updateEditingValue(editedValue);
        await tester.pump();
        expect(editableAfter.controller.text, editedValue.text);
        expect(tester.takeException(), isNull);
      },
      // testWidgets restores the platform before checking its invariants.
      variant: TargetPlatformVariant.only(foundation.TargetPlatform.macOS),
    );
  }
}
