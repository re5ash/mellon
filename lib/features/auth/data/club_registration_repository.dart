import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../core/errors/app_failure.dart';
import '../domain/club_registration.dart';

final clubChoicesProvider = FutureProvider.autoDispose<List<ClubChoice>>((
  ref,
) async {
  final rows = await ref
      .watch(backendProvider)
      .rpc<List<dynamic>>('available_youth_clubs')
      .timeout(const Duration(seconds: 15));
  return rows.map((value) {
    final row = value as Map<String, dynamic>;
    return ClubChoice(
      id: row['id'] as String,
      name: row['name'] as String,
      parishName: row['parish_name'] as String,
    );
  }).toList();
}, retry: (_, error) => null);

final clubRegistrationRepositoryProvider = Provider<ClubRegistrationRepository>(
  (ref) => SupabaseClubRegistrationRepository(
    ref.watch(backendProvider),
    ref.watch(configProvider).authRedirectUrl,
  ),
);

class SupabaseClubRegistrationRepository implements ClubRegistrationRepository {
  SupabaseClubRegistrationRepository(this.client, this.redirectUrl);
  final SupabaseClient client;
  final String redirectUrl;
  final _inFlight = <String, Future<bool>>{};

  @override
  Future<bool> register(ClubRegistration registration) => _inFlight.putIfAbsent(
    registration.receiptKey,
    () => _register(registration).whenComplete(() {
      _inFlight.remove(registration.receiptKey);
    }),
  );

  Future<bool> _hasReceipt(String key) async {
    final value = await client.rpc<dynamic>(
      'club_application_receipt',
      params: {'p_receipt': key},
    );
    if (value == null) return false;
    final receipt = value as Map<String, dynamic>;
    if (receipt['status'] != 'pending') {
      throw const AppFailure(
        'Эта заявка уже рассмотрена. Войдите в аккаунт, чтобы увидеть решение.',
      );
    }
    return true;
  }

  Future<bool> _register(ClubRegistration registration) async {
    // Retry the same receipt after a timeout instead of creating another request.
    if (registration.youthId != null &&
        await _hasReceipt(registration.receiptKey))
      return client.auth.currentSession == null;
    final response = await client.auth.signUp(
      email: registration.email.trim(),
      password: registration.password,
      data: registration.metadata,
      emailRedirectTo: redirectUrl,
    );
    if (registration.youthId == null) return response.session == null;
    if (!await _hasReceipt(registration.receiptKey)) {
      // Auth intentionally conceals whether an email is already registered.
      throw const AppFailure(
        'Заявка не подтверждена. Если аккаунт уже существует, нажмите «Войти». Проверьте также письмо подтверждения email.',
      );
    }
    return response.session == null;
  }
}

String clubChoicesError(Object error) {
  if (error is TimeoutException)
    return 'Подготовка отправки занимает слишком много времени. Проверьте соединение и повторите попытку.';
  if (error is PostgrestException &&
      const {'PGRST202', '42883'}.contains(error.code)) {
    return 'Приём заявок пока не настроен. Сообщите администратору приложения.';
  }
  return 'Не удалось подготовить отправку. Проверьте соединение и нажмите «Продолжить» ещё раз.';
}
