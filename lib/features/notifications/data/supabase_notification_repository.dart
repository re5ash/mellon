import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this.client);
  final SupabaseClient client;
  @override
  Stream<List<AppNotification>> watchInbox(String userId) => client
      .from('notifications')
      .stream(primaryKey: ['id'])
      .eq('user_id', userId)
      .order('created_at', ascending: false)
      .limit(50)
      .map(
        (rows) => rows
            .where((row) => row['kind'] != 'review_legacy')
            .map(AppNotification.fromJson)
            .toList(growable: false),
      );
  @override
  Future<void> markRead(String id) async {
    await client.rpc<Object?>(
      'mark_notification_read',
      params: {'p_notification': id},
    );
  }
}
