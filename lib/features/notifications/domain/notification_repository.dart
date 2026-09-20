import 'app_notification.dart';

abstract interface class NotificationRepository {
  Stream<List<AppNotification>> watchInbox(String userId);
  Future<void> markRead(String id);
}
