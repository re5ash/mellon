import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/notification_providers.dart';

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread =
        ref
            .watch(notificationsProvider)
            .asData
            ?.value
            .any((item) => !item.isRead) ??
        false;
    return IconButton(
      tooltip: unread ? 'Уведомления: есть новые' : 'Уведомления',
      onPressed: () => context.push<void>('/notifications'),
      icon: Badge(
        key: const ValueKey('notification-badge'),
        isLabelVisible: unread,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}
