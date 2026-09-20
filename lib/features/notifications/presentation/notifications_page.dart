import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_access.dart';
import '../../../core/errors/app_failure.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../auth/application/auth_providers.dart';
import '../application/notification_providers.dart';
import 'notification_applicant_card.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(
      authUserProvider.select((value) => value.asData?.value?.id),
    );
    return ContentFrame(
      child: AsyncContent(
        value: ref.watch(notificationsProvider),
        onRetry: () => ref.invalidate(notificationsProvider),
        builder: (items) => items.isEmpty
            ? const EmptyState(
                title: 'Новых уведомлений нет',
                message: 'Здесь будут новые пользователи, заявки и события.',
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => items[i].hasApplicant
                    ? NotificationApplicantCard(
                        key: ValueKey('$actor:${items[i].id}'),
                        notification: items[i],
                      )
                    : ListTile(
                        leading: Icon(
                          items[i].isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined,
                        ),
                        title: Text(items[i].title),
                        subtitle: Text(items[i].body),
                        onTap: () async {
                          final actor = ref
                              .read(authUserProvider)
                              .asData
                              ?.value
                              ?.id;
                          try {
                            await ref
                                .read(notificationRepositoryProvider)
                                .markRead(items[i].id);
                            if (context.mounted &&
                                actor != null &&
                                ref.read(authUserProvider).asData?.value?.id ==
                                    actor)
                              await context.push<void>(
                                safeDestination(items[i].targetPath),
                              );
                          } on Object catch (e) {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(userError(e))),
                              );
                          }
                        },
                      ),
              ),
      ),
    );
  }
}
