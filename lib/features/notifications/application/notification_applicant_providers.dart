import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/notification_applicant_repository.dart';
import '../domain/notification_applicant.dart';
import 'notification_providers.dart';

final notificationApplicantRepositoryProvider =
    Provider<NotificationApplicantRepository>(
      (ref) =>
          SupabaseNotificationApplicantRepository(ref.watch(backendProvider)),
    );

// Account identity is part of the key: a late response must never appear
// after signing in as another user. Access changes also clear private data.
final notificationApplicantProvider = FutureProvider.autoDispose
    .family<NotificationApplicant?, ({String actor, String notification})>((
      ref,
      key,
    ) async {
      final actor = ref.watch(
        authUserProvider.select((v) => v.asData?.value?.id),
      );
      final access = ref.watch(
        accountAccessProvider.select((value) {
          final data = value.asData?.value;
          return (value.hasError, data?.restrictedGuest, data?.canManageRoles);
        }),
      );
      ref.watch(
        notificationsProvider.select(
          (value) => value.asData?.value
              .where((item) => item.id == key.notification)
              .map(
                (item) =>
                    '${item.isRead}:${item.youthRequestId}:${item.subjectUserId}',
              )
              .firstOrNull,
        ),
      );
      if (actor != key.actor || access.$1 || access.$2 != false) {
        return null;
      }
      return ref
          .watch(notificationApplicantRepositoryProvider)
          .getApplicant(key.notification);
    }, retry: (_, error) => null);
