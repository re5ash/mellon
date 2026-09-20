import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../administration/application/admin_providers.dart';
import '../../administration/domain/admin_models.dart';
import '../../administration/presentation/admin_components.dart';
import '../../auth/application/auth_providers.dart';
import '../application/chat_admin_providers.dart';
import '../domain/chat_administration.dart';
import 'chat_icon_badge.dart';

class AdminChatsPage extends ConsumerWidget {
  const AdminChatsPage({required this.parishId, super.key});
  final String parishId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Чаты и каналы')),
    body: SafeArea(
      child: AsyncContent<AdminParish?>(
        value: ref.watch(managedParishProvider(parishId)),
        onRetry: () => ref.invalidate(managedParishProvider(parishId)),
        builder: (parish) => parish?.allows('chats.manage') != true
            ? const EmptyState(
                title: 'Доступ ограничен',
                message: 'Нет права управлять чатами этого прихода.',
              )
            : _ChatList(
                key: ValueKey((
                  parishId,
                  ref.watch(authUserProvider).asData?.value?.id,
                )),
                parish: parish!,
              ),
      ),
    ),
  );
}

class _ChatList extends ConsumerStatefulWidget {
  const _ChatList({required this.parish, super.key});
  final AdminParish parish;
  @override
  ConsumerState<_ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<_ChatList> {
  final _history = <String?>[null];
  @override
  Widget build(BuildContext context) {
    final base = '/admin/parishes/${widget.parish.id}/chats';
    return ContentFrame(
      child: ListView(
        children: [
          Text(
            widget.parish.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('$base/new'),
                icon: const Icon(Icons.add),
                label: const Text('Создать чат или канал'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _history
                      ..clear()
                      ..add(null);
                  });
                  ref.read(refreshChatAdministrationProvider)();
                  ref.invalidate(managedParishProvider(widget.parish.id));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Обновить'),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          AsyncContent<ManagedChatBatch>(
            value: ref.watch(
              managedChatsProvider((
                parishId: widget.parish.id,
                after: _history.last,
              )),
            ),
            onRetry: () => ref.invalidate(managedChatsProvider),
            builder: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpace.md),
                    child: Text(
                      'Чатов на этой странице пока нет. Создайте первый чат, например «Болталка».',
                    ),
                  ),
                for (final chat in page.items)
                  Card(
                    child: ListTile(
                      leading: ChatIconBadge(
                        iconKey: chat.room.iconKey,
                        title: chat.room.title,
                        description: chat.room.description,
                        seed: chat.room.id,
                      ),
                      title: Text(chat.room.title),
                      subtitle: Text(
                        '${chat.room.kind == 'channel' ? 'Канал' : 'Групповой чат'} · ${chat.room.archived ? 'В архиве' : 'Активен'} · Порядок: ${chat.room.sortOrder}',
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => context.go('$base/${chat.room.id}'),
                    ),
                  ),
                AdminPager(
                  page: _history.length,
                  previous: _history.length > 1
                      ? () => setState(() {
                          _history.removeLast();
                        })
                      : null,
                  next: page.next == null
                      ? null
                      : () => setState(() {
                          _history.add(page.next);
                        }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
