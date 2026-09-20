import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/permission_providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/chat_surface.dart';
import '../../../design_system/theme_controller.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../application/chat_memory_cache.dart';
import '../application/chat_moderation.dart';
import '../application/chat_providers.dart';
import '../application/chat_read_store.dart';
import '../domain/chat.dart';
import '../domain/chat_interactions.dart';
import 'chat_icon_badge.dart';
import 'emoji_input.dart';
import 'emoji_picker.dart';
import 'message_interactions.dart';
import 'moderated_timeline.dart';

class ChatPage extends ConsumerWidget {
  const ChatPage({
    required this.roomId,
    this.initialRoom,
    this.embedded = false,
    this.onClose,
    super.key,
  });
  final bool embedded;
  final VoidCallback? onClose;
  final String roomId;
  // List metadata supplies the immediate title and description, never access.
  final ChatRoom? initialRoom;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(chatRoomProvider(roomId));
    final actor = ref.watch(authUserProvider).asData?.value?.id;
    final displayRoom =
        room.asData?.value ??
        (initialRoom?.id == roomId ? initialRoom : null) ??
        ChatRoom(id: roomId, title: 'Чат клуба', kind: 'group');
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'К списку чатов',
          onPressed: onClose ?? () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Row(
          children: [
            ChatIconBadge(
              iconKey: displayRoom.iconKey,
              title: displayRoom.title,
              description: displayRoom.description,
              seed: displayRoom.id,
              size: 34,
              animateOnMount: true,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                displayRoom.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (!embedded)
            IconButton(
              tooltip: 'Обновить чат',
              onPressed: () {
                ref.invalidate(chatRoomProvider(roomId));
                ref.invalidate(permissionsProvider);
                ref.invalidate(chatAccessProvider(roomId));
                ref.invalidate(chatMessagesProvider(roomId));
              },
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: actor == null
            ? const EmptyState(
                title: 'Чат недоступен',
                message: 'Проверьте членство в клубе и доступ к чату.',
              )
            : _ChatBody(
                key: ValueKey((roomId, actor)),
                room: displayRoom,
                roomState: room,
                actorId: actor,
              ),
      ),
    );
  }
}

class _ChatBody extends ConsumerStatefulWidget {
  const _ChatBody({
    required this.room,
    required this.roomState,
    required this.actorId,
    super.key,
  });
  final ChatRoom room;
  final AsyncValue<ChatRoom?> roomState;
  final String actorId;
  @override
  ConsumerState<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends ConsumerState<_ChatBody> {
  final _text = TextEditingController();
  final _textFocus = FocusNode();
  ChatMessage? _reply;
  String? _pendingReply;
  final _emojiMenu = MenuController();
  TextSelection? _emojiSelection;
  bool _busy = false;
  String? _nonce, _pendingBody, _sendError;
  VoidCallback? _releaseCache;

  @override
  void initState() {
    super.initState();
    _retainLoadedRoom();
  }

  @override
  void didUpdateWidget(_ChatBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_roomReady) {
      _releaseCache?.call();
      _releaseCache = null;
    } else if (_releaseCache == null) {
      _retainLoadedRoom();
    }
  }

  void _retainLoadedRoom() {
    if (!_roomReady || _releaseCache != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_sameAccount && _roomReady && _releaseCache == null) {
        _releaseCache = ref
            .read(chatMemoryCacheProvider)
            .retain(widget.room.id);
      }
    });
  }

  @override
  void dispose() {
    _releaseCache?.call();
    _textFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _sameAccount =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actorId;

  bool get _roomReady => widget.roomState.asData?.value != null;

  void _insertEmoji(String emoji) {
    if (!_sameAccount ||
        !_roomReady ||
        ref.read(chatAccessProvider(widget.room.id)).asData?.value['send'] !=
            true ||
        widget.room.archived)
      return;
    final value = _text.value.copyWith(
      selection: _emojiSelection ?? _text.selection,
    );
    final inserted = insertChatEmoji(value, emoji);
    _text.value = inserted;
    _emojiSelection = inserted.selection;
  }

  bool _canSend(Set<String> permissions) =>
      !widget.room.archived &&
      permissions.contains(
        widget.room.kind == 'channel' ? 'channels.publish' : 'chat.send',
      );
  Future<void> _send() async {
    if (!_sameAccount || !_roomReady) return;
    final body = _text.text.trim();
    final caps = ref.read(chatAccessProvider(widget.room.id)).asData?.value;
    final permissions = caps?['send'] == true
        ? <String>{'chat.send', 'channels.publish'}
        : <String>{};
    if (body.isEmpty || _busy || !_sameAccount || !_canSend(permissions))
      return;
    final reply = _reply;
    if (body != _pendingBody || reply?.id != _pendingReply) {
      _nonce = newUuid();
      _pendingBody = body;
      _pendingReply = reply?.id;
    }
    setState(() {
      _busy = true;
      _sendError = null;
    });
    try {
      if (reply == null) {
        await ref
            .read(chatRepositoryProvider)
            .send(roomId: widget.room.id, body: body, nonce: _nonce!)
            .timeout(const Duration(seconds: 20));
      } else {
        final Object repo = ref.read(chatModerationProvider);
        if (repo is! ChatInteractionRepository)
          throw const AppFailure('Ответы пока недоступны.');
        await repo
            .sendReply(
              room: widget.room.id,
              body: body,
              replyTo: reply.id,
              nonce: _nonce!,
              actor: widget.actorId,
            )
            .timeout(const Duration(seconds: 20));
      }
      if (!_sameAccount) return;
      if (_text.text.trim() == body) _text.clear();
      _nonce = null;
      _pendingBody = null;
      _pendingReply = null;
      if (_reply?.id == reply?.id) _reply = null;
    } on Object catch (e) {
      if (mounted && _sameAccount) setState(() => _sendError = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = _roomReady
        ? ref.watch(chatAccessProvider(widget.room.id))
        : const AsyncLoading<Map<String, dynamic>>();
    final canSend =
        _roomReady &&
        !widget.room.archived &&
        permissions.asData?.value['send'] == true;
    final pending = !_roomReady
        ? widget.roomState.isLoading
        : permissions.isLoading && !permissions.hasValue;
    final appearance = ref.watch(appearanceControllerProvider);
    return ChatBackdrop(
      settings: appearance,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          children: [
            if (widget.room.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text(widget.room.description),
              ),
            Expanded(
              child: AsyncContent<ChatRoom?>(
                value: widget.roomState,
                preserveOnRefresh: true,
                // The stable chat backdrop is the loading surface. A spinner
                // here flashes on every room selection, then again for messages.
                loading: Semantics(
                  label: 'Загрузка чата',
                  child: const SizedBox.expand(),
                ),
                onRetry: () => ref.invalidate(chatRoomProvider(widget.room.id)),
                builder: (room) => room == null
                    ? const EmptyState(
                        title: 'Чат недоступен',
                        message: 'Проверьте членство в клубе и доступ к чату.',
                      )
                    : permissions.hasError
                    ? const Center(
                        child: Text(
                          'Доступ к чату закрыт или соединение потеряно. Обновите чат.',
                        ),
                      )
                    : ModeratedTimeline(
                        room: widget.room.id,
                        actor: widget.actorId,
                        onReply: canSend
                            ? (message) {
                                setState(() => _reply = message);
                                _textFocus.requestFocus();
                              }
                            : null,
                        onRead: (message) async {
                          if (!_sameAccount) return;
                          await ref
                              .read(chatReadStoreProvider)
                              .mark(
                                widget.actorId,
                                widget.room.id,
                                message.createdAt,
                                messageId: message.id,
                              );
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            if (canSend && _reply != null)
              Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    Expanded(
                      child: MessageReplyBlock(
                        reply: MessageReply(
                          id: _reply!.id,
                          author: _reply!.authorId == widget.actorId
                              ? 'Вы'
                              : _reply!.authorName,
                          excerpt: _reply!.body,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('cancel-chat-reply'),
                      tooltip: 'Отменить ответ',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _reply = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (canSend && _sendError != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  key: const ValueKey('chat-send-error'),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Text(
                    _sendError!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (canSend || pending)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .3),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MenuAnchor(
                        controller: _emojiMenu,
                        consumeOutsideTap: false,
                        useRootOverlay: true,
                        onClose: () => _emojiSelection = null,
                        style: const MenuStyle(
                          padding: WidgetStatePropertyAll(EdgeInsets.zero),
                        ),
                        menuChildren: [
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width - 32)
                                .clamp(220, 380)
                                .toDouble(),
                            height:
                                (MediaQuery.sizeOf(context).height -
                                        MediaQuery.viewInsetsOf(
                                          context,
                                        ).bottom -
                                        160)
                                    .clamp(190, 340)
                                    .toDouble(),
                            child: ChatEmojiPicker(
                              onSelected: _insertEmoji,
                              onClose: _emojiMenu.close,
                            ),
                          ),
                        ],
                        builder: (context, controller, child) => IconButton(
                          key: const ValueKey('chat-emoji-button'),
                          tooltip: 'Эмодзи',
                          onPressed: !canSend
                              ? null
                              : () {
                                  if (controller.isOpen) {
                                    controller.close();
                                  } else {
                                    _emojiSelection = _text.selection;
                                    controller.open();
                                  }
                                },
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('chat-message-input'),
                          controller: _text,
                          focusNode: _textFocus,
                          onTap: _emojiMenu.close,
                          enabled: canSend,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 4000,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontSize: 16,
                                height: 1.25,
                                fontFamilyFallback: const ['MellonEmoji'],
                              ),
                          decoration: const InputDecoration(
                            hintText: 'Сообщение',
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Отправить',
                        onPressed: _busy || !canSend ? null : _send,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Text(
                  !_roomReady
                      ? 'Отправка недоступна, пока чат не загружен.'
                      : widget.room.archived
                      ? 'Чат в архиве. Доступно только чтение.'
                      : permissions.isLoading
                      ? 'Проверяем доступ к отправке…'
                      : permissions.hasError
                      ? 'Не удалось проверить права. Обновите чат.'
                      : widget.room.kind == 'channel'
                      ? 'Канал объявлений. У вас доступ только к чтению.'
                      : 'У вас нет права отправлять сообщения в этот чат.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
