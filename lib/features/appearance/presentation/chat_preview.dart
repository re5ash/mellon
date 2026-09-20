import 'package:flutter/material.dart';

import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/chat_surface.dart';

class ChatPreview extends StatelessWidget {
  const ChatPreview({required this.settings, super.key});
  final AppearanceSettings settings;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: colors.surfaceContainerLow,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    Icons.church_outlined,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Чат прихода',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Пример оформления',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_horiz, color: colors.onSurfaceVariant),
              ],
            ),
          ),
          ChatBackdrop(
            settings: settings,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 10),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      'Сегодня',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ChatMessageCard(
                    settings: settings,
                    body: 'В воскресенье встречаемся после службы?',
                    author: 'Анна',
                    time: '10:24',
                    outgoing: false,
                  ),
                  ChatMessageCard(
                    settings: settings,
                    body: 'Да, буду. До встречи!',
                    author: 'Вы',
                    time: '10:25',
                    outgoing: true,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: colors.surfaceContainerLow,
            child: Row(
              children: [
                Icon(Icons.add_rounded, color: colors.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      child: Text(
                        'Сообщение',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primary,
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20,
                    color: colors.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
