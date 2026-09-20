import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/pagination/cursor_page.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../community/community_pages.dart';
import '../../community/community_widgets.dart';
import '../application/admin_providers.dart';
import '../domain/admin_models.dart';
import 'admin_components.dart';

class AdminParishPage extends ConsumerStatefulWidget {
  const AdminParishPage({required this.parishId, super.key});
  final String parishId;
  @override
  ConsumerState<AdminParishPage> createState() => _AdminParishPageState();
}

class _AdminParishPageState extends ConsumerState<AdminParishPage> {
  final _history = <PageCursor?>[null];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Управление приходом')),
    body: SafeArea(
      child: AsyncContent<AdminParish?>(
        value: ref.watch(managedParishProvider(widget.parishId)),
        onRetry: () => ref.invalidate(managedParishProvider(widget.parishId)),
        builder: (parish) {
          if (parish == null)
            return const EmptyState(
              title: 'Доступ ограничен',
              message: 'Приход недоступен для управления.',
            );
          return ContentFrame(
            child: ListView(
              children: [
                Text(
                  parish.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '${parish.cityName} · ${parish.isPublished ? 'В каталоге' : 'Скрыт из каталога'}',
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => openCommunity(
                        context,
                        ScopeHome(
                          scope: (parish: parish.id, youth: null),
                          title: parish.name,
                        ),
                      ),
                      icon: const Icon(Icons.groups_outlined),
                      label: const Text('Роли, молодёжки и события'),
                    ),
                    if (parish.allows('parish.manage'))
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/admin/parishes/${parish.id}/edit'),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Редактировать приход'),
                      ),
                    if (parish.allows('memberships.manage'))
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/admin/parishes/${parish.id}/requests'),
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Заявки участников'),
                      ),
                    if (parish.allows('chats.manage'))
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.go('/admin/parishes/${parish.id}/chats'),
                        icon: const Icon(Icons.forum_outlined),
                        label: const Text('Чаты и каналы'),
                      ),
                    if (parish.allows('posts.manage'))
                      FilledButton.icon(
                        onPressed: () => context.go(
                          '/admin/parishes/${parish.id}/posts/new',
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Создать публикацию'),
                      ),
                    IconButton(
                      tooltip: 'Обновить',
                      onPressed: () {
                        setState(() {
                          _history
                            ..clear()
                            ..add(null);
                        });
                        ref.read(refreshAdminDataProvider)();
                      },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
                if (parish.allows('posts.manage')) ...[
                  Text(
                    'Публикации',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  AsyncContent<CursorPage<AdminPost>>(
                    value: ref.watch(
                      adminPostsProvider((
                        parishId: parish.id,
                        before: _history.last,
                      )),
                    ),
                    onRetry: () => ref.invalidate(adminPostsProvider),
                    builder: (page) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (page.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpace.md,
                            ),
                            child: Text(
                              'На этой странице пока нет публикаций.',
                            ),
                          ),
                        for (final post in page.items)
                          Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(AppSpace.md),
                              title: Text(post.title),
                              subtitle: Text(
                                '${postStatusLabel(post.status)} · ${post.visibility == 'public' ? 'Общая лента' : 'Только приход'}',
                              ),
                              trailing: const Icon(Icons.edit_outlined),
                              onTap: () => context.go(
                                '/admin/parishes/${parish.id}/posts/${post.id}',
                              ),
                            ),
                          ),
                        AdminPager(
                          page: _history.length,
                          previous: _history.length > 1
                              ? () => setState(() {
                                  _history.removeLast();
                                })
                              : null,
                          next: page.next != null
                              ? () => setState(() {
                                  _history.add(page.next);
                                })
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
