import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../community/club_directory_repository.dart';
import '../../community/community_pages.dart';
import '../../community/community_repository.dart';
import '../../community/community_widgets.dart';
import '../../community/content_pages.dart';
import '../../community/role_manager_dialog.dart';

class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ContentFrame(
    child: ListView(
      children: [
        Text('Управление', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        const Text('Участники, права и работа молодёжных клубов.'),
        const SizedBox(height: 20),
        AsyncContent<AccountAccess>(
          value: ref.watch(accountAccessProvider),
          onRetry: () => ref.read(accountAccessRefreshProvider).value++,
          builder: (access) => access.restrictedGuest
              ? const CommunityTile(
                  title: 'Доступ ограничен',
                  icon: Icons.lock_outline,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const RolesEntry(),
                    if (access.superAdmin) ...[
                      CommunityTile(
                        key: const ValueKey('manage-youth-clubs'),
                        title: 'Молодёжные клубы',
                        subtitle: 'Создание и настройки клубов',
                        icon: Icons.groups_rounded,
                        onTap: () => context.push('/admin/youth-clubs'),
                      ),
                      CommunityTile(
                        title: 'Настройки приложения',
                        icon: Icons.settings_outlined,
                        onTap: () =>
                            openCommunity(context, const GlobalSettingsPage()),
                      ),
                    ],
                    AsyncContent<List<JsonRow>>(
                      value: ref.watch(clubWorkspacesProvider),
                      preserveOnRefresh: true,
                      onRetry: () => ref.invalidate(clubWorkspacesProvider),
                      builder: (clubs) => Column(
                        children: [
                          if (clubs.isEmpty &&
                              !access.superAdmin &&
                              !access.canManageRoles)
                            const CommunityTile(
                              title: 'Нет доступных инструментов управления',
                              icon: Icons.lock_outline,
                            ),
                          for (final club in clubs)
                            CommunityTile(
                              title: club['name'] as String,
                              subtitle: 'Чаты, события и участники',
                              icon: Icons.tune_rounded,
                              onTap: () => openCommunity(
                                context,
                                ScopeHome(
                                  scope: (
                                    parish: club['parish_id'] as String?,
                                    youth: club['id'] as String?,
                                  ),
                                  title: club['name'] as String,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    ),
  );
}
