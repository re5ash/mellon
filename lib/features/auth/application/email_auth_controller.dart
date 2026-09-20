import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../core/errors/app_failure.dart';
import '../data/supabase_email_auth_repository.dart';
import '../domain/email_auth_repository.dart';

final emailAuthRepositoryProvider = Provider<EmailAuthRepository>(
  (ref) => SupabaseEmailAuthRepository(
    ref.watch(backendProvider),
    ref.watch(configProvider).authRedirectUrl,
  ),
);
final authClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
final emailAuthControllerProvider =
    NotifierProvider<EmailAuthController, EmailAuthState>(
      EmailAuthController.new,
    );

class EmailAuthState {
  const EmailAuthState({
    this.busy = false,
    this.message,
    this.error,
    this.resendAt,
    this.recoveryUserId,
    this.recoveryUntil,
  });
  final bool busy;
  final String? message;
  final String? error;
  final DateTime? resendAt;
  final String? recoveryUserId;
  final DateTime? recoveryUntil;
}

class EmailAuthController extends Notifier<EmailAuthState> {
  @override
  EmailAuthState build() => const EmailAuthState();

  DateTime get _now => ref.read(authClockProvider)();
  int get remainingSeconds {
    final milliseconds = state.resendAt?.difference(_now).inMilliseconds ?? 0;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  bool get canSetPassword =>
      state.recoveryUserId != null &&
      state.recoveryUntil != null &&
      _now.isBefore(state.recoveryUntil!) &&
      ref.read(emailAuthRepositoryProvider).currentUserId ==
          state.recoveryUserId;

  void clearFeedback() {
    if (state.busy) return;
    state = EmailAuthState(
      resendAt: state.resendAt,
      recoveryUserId: state.recoveryUserId,
      recoveryUntil: state.recoveryUntil,
    );
  }

  void noteRegistrationEmail() {
    state = EmailAuthState(resendAt: _now.add(const Duration(seconds: 60)));
  }

  Future<bool> send(String email, EmailPurpose purpose) async {
    if (state.busy || remainingSeconds > 0) return false;
    final until = _now.add(const Duration(seconds: 60));
    state = EmailAuthState(busy: true, resendAt: until);
    try {
      await ref.read(emailAuthRepositoryProvider).send(email, purpose);
      if (!ref.mounted) return false;
      state = EmailAuthState(
        resendAt: until,
        message:
            'Если для этого адреса доступно действие, письмо будет отправлено. Проверьте входящие и спам. Можно открыть ссылку или ввести код из письма.',
      );
      return true;
    } on Object catch (error) {
      if (ref.mounted)
        state = EmailAuthState(resendAt: until, error: userError(error));
      return false;
    }
  }

  Future<bool> verify({
    required EmailPurpose purpose,
    String? email,
    String? code,
    String? tokenHash,
  }) async {
    if (state.busy) return false;
    final resendAt = state.resendAt;
    state = EmailAuthState(busy: true, resendAt: resendAt);
    try {
      final id = await ref
          .read(emailAuthRepositoryProvider)
          .verify(
            purpose: purpose,
            email: email,
            code: code,
            tokenHash: tokenHash,
          );
      if (!ref.mounted) return false;
      state = EmailAuthState(
        resendAt: resendAt,
        recoveryUserId: purpose == EmailPurpose.recovery ? id : null,
        recoveryUntil: purpose == EmailPurpose.recovery
            ? _now.add(const Duration(minutes: 15))
            : null,
        message: purpose == EmailPurpose.confirmation
            ? 'Почта подтверждена.'
            : null,
      );
      return true;
    } on Object catch (error) {
      if (ref.mounted)
        state = EmailAuthState(resendAt: resendAt, error: userError(error));
      return false;
    }
  }

  Future<bool> setPassword(String password) async {
    if (state.busy) return false;
    if (!canSetPassword) {
      state = EmailAuthState(
        resendAt: state.resendAt,
        error:
            'Доступ к смене пароля истёк или аккаунт изменился. Запросите новое письмо.',
      );
      return false;
    }
    final previous = state;
    state = EmailAuthState(
      busy: true,
      resendAt: previous.resendAt,
      recoveryUserId: previous.recoveryUserId,
      recoveryUntil: previous.recoveryUntil,
    );
    try {
      await ref
          .read(emailAuthRepositoryProvider)
          .setPassword(password, previous.recoveryUserId!);
      if (!ref.mounted) return false;
      state = EmailAuthState(
        resendAt: previous.resendAt,
        message: 'Новый пароль сохранён.',
      );
      return true;
    } on Object catch (error) {
      if (ref.mounted)
        state = EmailAuthState(
          resendAt: previous.resendAt,
          recoveryUserId: previous.recoveryUserId,
          recoveryUntil: previous.recoveryUntil,
          error: userError(error),
        );
      return false;
    }
  }
}
