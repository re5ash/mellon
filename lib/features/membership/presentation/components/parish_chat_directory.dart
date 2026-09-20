import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens.dart';
import '../../../chats/domain/chat.dart';
import '../../../chats/presentation/chat_icon_badge.dart';

class ParishChatDirectory extends StatefulWidget {
  const ParishChatDirectory({required this.rooms, super.key});
  final List<ChatRoom> rooms;
  @override
  State<ParishChatDirectory> createState() => _ParishChatDirectoryState();
}

class _ParishChatDirectoryState extends State<ParishChatDirectory> {
  bool _searching = false;
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final filtered = widget.rooms
        .where((room) => room.title.toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Чаты прихода',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: _searching ? 'Закрыть поиск чатов' : 'Поиск чатов',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _query.clear();
              }),
              icon: Icon(_searching ? Icons.close : Icons.search),
            ),
          ],
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название чата',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text(
              query.isEmpty
                  ? 'Доступных чатов пока нет.'
                  : 'Чаты с таким названием не найдены.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final room in filtered)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppLayout.radius),
                onTap: () async {
                  await context.push<void>('/chats/${room.id}');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${widget.rooms.indexOf(room) + 1}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      ChatIconBadge(
                        iconKey: room.iconKey,
                        title: room.title,
                        description: room.description,
                        seed: room.id,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              room.description.isNotEmpty
                                  ? room.description
                                  : room.kind == 'channel'
                                  ? 'Канал прихода'
                                  : 'Общение прихожан',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
