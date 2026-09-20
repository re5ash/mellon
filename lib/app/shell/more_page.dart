import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/account_access_provider.dart';
import '../../design_system/components/content_frame.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/community/club_directory_repository.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    final access = ref.watch(accountAccessProvider).asData?.value;
    final restricted = access?.restrictedGuest == true;
    final workspaces = user == null || restricted
        ? <Map<String, dynamic>>[]
        : ref.watch(clubWorkspacesProvider).asData?.value ?? [];
    final canManage =
        !restricted &&
        (access?.superAdmin == true ||
            access?.canManageRoles == true ||
            workspaces.isNotEmpty);
    final entries = <({String title, String route, IconData icon})>[
      (
        title: 'Молодёжные клубы',
        route: '/my-youth',
        icon: Icons.groups_rounded,
      ),
      (title: 'События', route: '/events', icon: Icons.event_outlined),
      (
        title: 'Помощь',
        route: '/help',
        icon: Icons.volunteer_activism_outlined,
      ),
      (
        title: 'Уведомления',
        route: '/notifications',
        icon: Icons.notifications_outlined,
      ),
      (
        title: 'Профиль и оформление',
        route: '/profile',
        icon: Icons.person_outline,
      ),
      if (canManage)
        (
          title: 'Управление',
          route: '/admin',
          icon: Icons.admin_panel_settings_outlined,
        ),
    ];
    return ContentFrame(
      child: ListView(
        children: entries
            .map(
              (entry) => ListTile(
                leading: Icon(entry.icon),
                title: Text(entry.title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(entry.route),
              ),
            )
            .toList(),
      ),
    );
  }
}
