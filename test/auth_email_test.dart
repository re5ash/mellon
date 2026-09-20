import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/features/auth/application/email_auth_controller.dart';
import 'package:moy_prihod/features/auth/domain/auth_link.dart';
import 'package:moy_prihod/features/auth/domain/email_auth_repository.dart';
import 'package:moy_prihod/features/auth/presentation/email_auth_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeEmailAuth implements EmailAuthRepository {
  @override
  String? currentUserId;
  int sent = 0;
  int verified = 0;
  int changed = 0;
  EmailPurpose? purpose;
  String? lastCode;
  String? lastHash;
  Object? sendError;
  Object? verifyError;
  Object? passwordError;
  Completer<void>? sending;
  @override
  Future<void> send(String email, EmailPurpose purpose) async {
    sent++;
    this.purpose = purpose;
    if (sending != null) await sending!.future;
    if (sendError != null) throw sendError!;
  }

  @override
  Future<String> verify({
    required EmailPurpose purpose,
    String? email,
    String? code,
    String? tokenHash,
  }) async {
    verified++;
    this.purpose = purpose;
    lastCode = code;
    lastHash = tokenHash;
    if (verifyError != null) throw verifyError!;
    currentUserId = 'verified-user';
    return currentUserId!;
  }

  @override
  Future<void> setPassword(String password, String expectedUserId) async {
    expect(expectedUserId, currentUserId);
    changed++;
    if (passwordError != null) throw passwordError!;
  }
}

void main() {
  late FakeEmailAuth repository;
  late DateTime now;
  late ProviderContainer container;
  late EmailAuthController flow;
  setUp(() {
    repository = FakeEmailAuth();
    now = DateTime.utc(2026, 9, 11);
    container = ProviderContainer(
      overrides: [
        emailAuthRepositoryProvider.overrideWithValue(repository),
        authClockProvider.overrideWithValue(() => now),
      ],
    );
    flow = container.read(emailAuthControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test(
    'duplicate requests blocked while in flight and during cooldown; retry after 60s',
    () async {
      repository.sending = Completer<void>();
      final pending = flow.send('a@example.com', EmailPurpose.recovery);
      expect(await flow.send('a@example.com', EmailPurpose.recovery), isFalse);
      repository.sending!.complete();
      expect(await pending, isTrue);
      expect(
        await flow.send('b@example.com', EmailPurpose.confirmation),
        isFalse,
      );
      expect(repository.sent, 1);
      now = now.add(const Duration(seconds: 60));
      expect(await flow.send('a@example.com', EmailPurpose.recovery), isTrue);
      expect(repository.sent, 2);
    },
  );
  test('registration also starts resend cooldown', () {
    flow.noteRegistrationEmail();
    expect(flow.remainingSeconds, 60);
    now = now.add(const Duration(seconds: 61));
    expect(flow.remainingSeconds, 0);
  });
  test(
    'provider rate limit remains an error, never reports delivery',
    () async {
      repository.sendError = const AuthException(
        'redacted',
        code: 'over_email_send_rate_limit',
      );
      expect(await flow.send('a@example.com', EmailPurpose.recovery), isFalse);
      final state = container.read(emailAuthControllerProvider);
      expect(state.error, contains('лимит'));
      expect(state.message, isNull);
      expect(state.busy, isFalse);
    },
  );
  test(
    'expired or reused token grants no password access; fresh code succeeds',
    () async {
      repository.verifyError = const AuthException(
        'expired',
        code: 'otp_expired',
      );
      expect(
        await flow.verify(purpose: EmailPurpose.recovery, tokenHash: 'expired'),
        isFalse,
      );
      expect(flow.canSetPassword, isFalse);
      expect(
        container.read(emailAuthControllerProvider).error,
        contains('истёк'),
      );
      repository.verifyError = null;
      expect(
        await flow.verify(
          purpose: EmailPurpose.recovery,
          email: 'a@example.com',
          code: '12345678',
        ),
        isTrue,
      );
      expect(flow.canSetPassword, isTrue);
      expect(repository.lastCode, '12345678');
    },
  );
  test(
    'ordinary signed in user and email confirmation cannot open recovery form',
    () async {
      repository.currentUserId = 'ordinary-user';
      expect(await flow.setPassword('long-password-123'), isFalse);
      await flow.verify(
        purpose: EmailPurpose.confirmation,
        code: '12345678',
        email: 'a@example.com',
      );
      expect(flow.canSetPassword, isFalse);
      expect(await flow.setPassword('long-password-123'), isFalse);
      expect(repository.changed, 0);
    },
  );
  test(
    'account change or expired recovery grant blocks password update',
    () async {
      await flow.verify(
        purpose: EmailPurpose.recovery,
        code: '12345678',
        email: 'a@example.com',
      );
      repository.currentUserId = 'another-user';
      expect(await flow.setPassword('long-password-123'), isFalse);
      await flow.verify(
        purpose: EmailPurpose.recovery,
        code: '12345678',
        email: 'a@example.com',
      );
      now = now.add(const Duration(minutes: 15));
      expect(await flow.setPassword('long-password-123'), isFalse);
      expect(repository.changed, 0);
    },
  );
  test(
    'password server failure retains retry, success consumes UI grant',
    () async {
      await flow.verify(
        purpose: EmailPurpose.recovery,
        code: '12345678',
        email: 'a@example.com',
      );
      repository.passwordError = const AuthException(
        'same',
        code: 'same_password',
      );
      expect(await flow.setPassword('old-password-123'), isFalse);
      expect(flow.canSetPassword, isTrue);
      repository.passwordError = null;
      expect(await flow.setPassword('new-password-123'), isTrue);
      expect(flow.canSetPassword, isFalse);
      expect(await flow.setPassword('again-password-123'), isFalse);
      expect(repository.changed, 2);
    },
  );
  test(
    'failed new verification discards any previous recovery grant',
    () async {
      await flow.verify(
        purpose: EmailPurpose.recovery,
        code: '12345678',
        email: 'a@example.com',
      );
      repository.verifyError = const AuthException(
        'expired',
        code: 'otp_expired',
      );
      await flow.verify(
        purpose: EmailPurpose.recovery,
        code: '00000000',
        email: 'b@example.com',
      );
      expect(flow.canSetPassword, isFalse);
    },
  );
  test('disposed provider does not receive late send completion', () async {
    final scoped = ProviderContainer(
      overrides: [emailAuthRepositoryProvider.overrideWithValue(repository)],
    );
    repository.sending = Completer<void>();
    final pending = scoped
        .read(emailAuthControllerProvider.notifier)
        .send('a@example.com', EmailPurpose.recovery);
    scoped.dispose();
    repository.sending!.complete();
    expect(await pending, isFalse);
  });
  test(
    'link parser rejects malformed, duplicated and unsupported credentials',
    () {
      final token = List.filled(64, 'a').join();
      expect(
        AuthLink.parse(
          Uri.parse('/auth/verify?token_hash=$token&type=recovery'),
        )?.purpose,
        EmailPurpose.recovery,
      );
      expect(
        AuthLink.parse(
          Uri.parse('/auth/verify?token_hash=$token&type=email'),
        )?.purpose,
        EmailPurpose.confirmation,
      );
      for (final query in [
        'type=recovery',
        'token_hash=short&type=email',
        'token_hash=$token&type=invite',
        'token_hash=$token&type=email&type=recovery',
        'token_hash=$token&token_hash=$token&type=email',
        'error=access_denied',
      ]) {
        expect(AuthLink.parse(Uri.parse('/auth/verify?$query')), isNull);
      }
    },
  );
  test('auth errors do not leak raw provider text', () {
    expect(
      userError(const AuthException('secret-token', code: 'otp_expired')),
      isNot(contains('secret-token')),
    );
    expect(
      userError(const AuthException('secret-token')),
      isNot(contains('secret-token')),
    );
  });

  testWidgets(
    'opening link does not consume token; click verifies and navigates to reset',
    (tester) async {
      final token = List.filled(64, 'a').join();
      final router = GoRouter(
        initialLocation: '/auth/verify?type=recovery&token_hash=$token',
        routes: [
          GoRoute(
            path: '/auth/verify',
            builder: (_, state) => EmailLinkPage(uri: state.uri),
          ),
          GoRoute(
            path: '/auth/new-password',
            builder: (_, state) => const NewPasswordPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            emailAuthRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.verified, 0);
      await tester.tap(find.text('Подтвердить'));
      await tester.pumpAndSettle();
      expect(repository.verified, 1);
      expect(repository.lastHash, token);
      expect(find.text('Новый пароль'), findsWidgets);
      expect(
        router.routeInformationProvider.value.uri.queryParameters,
        isEmpty,
      );
    },
  );
  testWidgets('password mismatch prevents update, matching fields save', (
    tester,
  ) async {
    await flow.verify(
      purpose: EmailPurpose.recovery,
      code: '12345678',
      email: 'a@example.com',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: NewPasswordPage()),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'long-password-123',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'different-password',
    );
    await tester.tap(find.text('Сохранить новый пароль'));
    await tester.pumpAndSettle();
    expect(repository.changed, 0);
    expect(find.text('Пароли не совпадают'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'long-password-123',
    );
    await tester.tap(find.text('Сохранить новый пароль'));
    await tester.pumpAndSettle();
    expect(repository.changed, 1);
    expect(find.text('Открыть приложение'), findsOneWidget);
  });
  testWidgets(
    'recovery request fits narrow screen with keyboard and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.8),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: const EmailRequestPage(purpose: EmailPurpose.recovery),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final button = find.text('Подтвердить код');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
