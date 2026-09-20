import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import 'auth_providers.dart';

final authRequestTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 30),
);

final authControllerProvider = AsyncNotifierProvider<AuthController, String?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<String?> {
  @override
  String? build() => null;
  void clearMessage() {
    if (!state.isLoading && (state.hasError || state.asData?.value != null)) {
      state = const AsyncData(null);
    }
  }

  Future<void> submit({
    required String email,
    required String password,
    required bool register,
  }) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final timeout = ref.read(authRequestTimeoutProvider);
    final result = await AsyncValue.guard<String?>(() async {
      final repository = ref.read(authRepositoryProvider);
      if (register) {
        final needsConfirmation = await repository
            .signUp(email, password)
            .timeout(timeout);
        return needsConfirmation
            ? 'Проверьте почту и подтвердите адрес. Затем войдите в приложение.'
            : null;
      }
      await repository.signIn(email, password).timeout(timeout);
      return null;
    });
    if (!ref.mounted) return;
    state = result.error is TimeoutException
        ? const AsyncError(
            AppFailure(
              'Вход занял слишком много времени. Проверьте соединение и повторите попытку.',
            ),
            StackTrace.empty,
          )
        : result;
    // Re-read the persisted session even when the auth event was missed.
    // A timeout does not imply that the server rejected the credentials.
    if (!result.hasError || result.error is TimeoutException) {
      ref.invalidate(authUserProvider);
    }
  }
}
