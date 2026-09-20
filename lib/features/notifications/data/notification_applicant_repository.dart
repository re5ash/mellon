import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/notification_applicant.dart';

abstract interface class NotificationApplicantRepository {
  Future<NotificationApplicant?> getApplicant(String notificationId);
}

class SupabaseNotificationApplicantRepository
    implements NotificationApplicantRepository {
  const SupabaseNotificationApplicantRepository(this.client);
  final SupabaseClient client;
  @override
  Future<NotificationApplicant?> getApplicant(String notificationId) async {
    try {
      final json = await client
          .rpc<Map<String, dynamic>?>(
            'notification_applicant',
            params: {'p_notification': notificationId},
          )
          .timeout(const Duration(seconds: 15));
      return json == null ? null : NotificationApplicant.fromJson(json);
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST202' || error.code == '42883') {
        throw const AppFailure(
          'Карточки пользователей ещё не обновлены на сервере. Обратитесь к суперадминистратору.',
        );
      }
      if (error.code == '42501') return null;
      rethrow;
    }
  }
}
