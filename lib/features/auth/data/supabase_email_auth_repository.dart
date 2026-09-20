import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/email_auth_repository.dart';

class SupabaseEmailAuthRepository implements EmailAuthRepository {
  SupabaseEmailAuthRepository(this.client, this.redirectUrl);
  final SupabaseClient client;
  final String redirectUrl;

  @override
  String? get currentUserId => client.auth.currentUser?.id;

  @override
  Future<void> send(String email, EmailPurpose purpose) async {
    if (purpose == EmailPurpose.recovery) {
      await client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: redirectUrl,
      );
    } else {
      await client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: redirectUrl,
      );
    }
  }

  @override
  Future<String> verify({
    required EmailPurpose purpose,
    String? email,
    String? code,
    String? tokenHash,
  }) async {
    final response = await client.auth.verifyOTP(
      type: purpose == EmailPurpose.recovery ? OtpType.recovery : OtpType.email,
      email: tokenHash == null ? email?.trim() : null,
      token: tokenHash == null ? code?.trim() : null,
      tokenHash: tokenHash,
    );
    final session = response.session;
    if (session == null || session.isExpired) {
      throw const AppFailure(
        'Не удалось подтвердить доступ. Запросите новое письмо.',
      );
    }
    return session.user.id;
  }

  @override
  Future<void> setPassword(String password, String expectedUserId) async {
    if (currentUserId != expectedUserId) {
      throw const AppFailure(
        'Аккаунт изменился. Запросите новое письмо для восстановления.',
      );
    }
    // Revalidate the session with the server before changing credentials.
    final user = await client.auth.getUser();
    if (user.user?.id != expectedUserId || currentUserId != expectedUserId) {
      throw const AppFailure(
        'Сеанс завершён. Запросите новое письмо для восстановления.',
      );
    }
    await client.auth.updateUser(UserAttributes(password: password));
  }
}
