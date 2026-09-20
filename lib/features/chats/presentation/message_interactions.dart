import 'package:flutter/material.dart';

import '../domain/chat.dart';
import '../domain/chat_interactions.dart';
import 'emoji_picker.dart';

class MessageReplyBlock extends StatelessWidget {
  const MessageReplyBlock({required this.reply, this.onTap, super.key});
  final MessageReply reply;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: !reply.deleted && onTap != null,
    label: 'Ответ на сообщение ${reply.author}',
    child: InkWell(
      key: ValueKey('reply-${reply.id}'),
      onTap: reply.deleted ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              width: 3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reply.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Text(
              reply.deleted ? 'Сообщение удалено' : reply.excerpt,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class MessageReactions extends StatelessWidget {
  const MessageReactions({
    required this.message,
    required this.reactions,
    required this.onToggle,
    super.key,
  });
  final String message;
  final List<ChatReaction> reactions;
  final ValueChanged<ChatReaction>? onToggle;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 5,
    runSpacing: 4,
    children: [
      for (final reaction in reactions)
        Semantics(
          selected: reaction.mine,
          label: '${reaction.emoji}: ${reaction.count}',
          button: true,
          enabled: onToggle != null,
          child: InkWell(
            key: ValueKey('reaction-$message-${reaction.emoji}'),
            onTap: onToggle == null ? null : () => onToggle!(reaction),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: reaction.mine ? .18 : .07,
                ),
                border: Border.all(
                  color: reaction.mine
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Text(
                '${reaction.emoji} ${reaction.count}',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamilyFallback: ['MellonEmoji'],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

Future<String?> chooseReaction(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: (MediaQuery.sizeOf(context).height * .6)
              .clamp(220, 440)
              .toDouble(),
          child: ChatEmojiPicker(
            onSelected: (emoji) => Navigator.pop(context, emoji),
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    );
