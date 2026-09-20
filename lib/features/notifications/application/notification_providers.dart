import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_notification_repository.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(ref.watch(backendProvider)),
);
final notificationsProvider = StreamProvider.autoDispose<List<AppNotification>>(
  (ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    return user == null
        ? Stream.value([])
        : ref.watch(notificationRepositoryProvider).watchInbox(user.id);
  },
);
