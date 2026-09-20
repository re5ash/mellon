import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../application/chat_providers.dart';
import 'chat_icon_badge.dart';

class ChatsPage extends ConsumerWidget {
  const ChatsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ContentFrame(
    child: AsyncContent(
      value: ref.watch(chatRoomsProvider),
      onRetry: () => ref.invalidate(chatRoomsProvider),
      builder: (rooms) => rooms.isEmpty
          ? const EmptyState(
              title: 'Пока нет доступных чатов',
              message:
                  'Чаты появятся после вступления в приход, когда администратор их создаст.',
            )
          : ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, i) => ListTile(
                leading: ChatIconBadge(
                  iconKey: rooms[i].iconKey,
                  title: rooms[i].title,
                  description: rooms[i].description,
                  seed: rooms[i].id,
                ),
                title: Text(rooms[i].title),
                onTap: () => context.push('/chats/${rooms[i].id}'),
              ),
            ),
    ),
  );
}
