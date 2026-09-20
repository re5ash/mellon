import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
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
import 'chat_icon_picker.dart';

class ChatEditorPage extends ConsumerWidget {
  const ChatEditorPage({required this.parishId, this.roomId, super.key});
  final String parishId;
  final String? roomId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authUserProvider).asData?.value?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          roomId == null ? 'Создать чат или канал' : 'Редактировать чат',
        ),
      ),
      body: SafeArea(
        child: AsyncContent<AdminParish?>(
          value: ref.watch(managedParishProvider(parishId)),
          preserveOnRefresh: true,
          onRetry: () => ref.invalidate(managedParishProvider(parishId)),
          builder: (parish) {
            if (actor == null || parish?.allows('chats.manage') != true) {
              return const EmptyState(
                title: 'Доступ ограничен',
                message: 'Нет права управлять чатами этого прихода.',
              );
            }
            Widget form(ManagedChat? chat) => ChatEditorForm(
              key: ValueKey((actor, parishId, roomId)),
              parishId: parishId,
              parishName: parish!.name,
              actorId: actor,
              chat: chat,
            );
            if (roomId == null) return form(null);
            final request = (parishId: parishId, id: roomId!);
            return AsyncContent<ManagedChat?>(
              value: ref.watch(managedChatProvider(request)),
              preserveOnRefresh: true,
              onRetry: () => ref.invalidate(managedChatProvider(request)),
              builder: (chat) => chat == null
                  ? const EmptyState(
                      title: 'Чат недоступен',
                      message: 'Вернитесь к списку чатов.',
                    )
                  : form(chat),
            );
          },
        ),
      ),
    );
  }
}

class ChatEditorForm extends ConsumerStatefulWidget {
  const ChatEditorForm({
    required this.parishId,
    required this.parishName,
    required this.actorId,
    this.chat,
    super.key,
  });
  final String parishId, parishName, actorId;
  final ManagedChat? chat;
  @override
  ConsumerState<ChatEditorForm> createState() => _ChatEditorFormState();
}

class _ChatEditorFormState extends ConsumerState<ChatEditorForm> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final int? _expectedRevision;
  late final TextEditingController _title, _description, _order;
  late String _kind, _icon;
  late bool _archived;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final room = widget.chat?.room;
    _id = room?.id ?? newUuid();
    _expectedRevision = widget.chat?.revision;
    _title = TextEditingController(text: room?.title ?? '');
    _description = TextEditingController(text: room?.description ?? '');
    _order = TextEditingController(text: '${room?.sortOrder ?? 100}');
    _kind = room?.kind ?? 'group';
    _icon = room?.iconKey ?? 'auto';
    _archived = room?.archived ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _order.dispose();
    super.dispose();
  }

  bool get _sameAccount =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actorId;
  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (!_sameAccount) {
      setState(() => _error = 'Аккаунт изменился. Откройте форму заново.');
      return;
    }
    final repository = ref.read(chatAdministrationRepositoryProvider);
    final refresh = ref.read(refreshChatAdministrationProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repository.save(
        ChatInput(
          id: _id,
          parishId: widget.parishId,
          actorId: widget.actorId,
          create: widget.chat == null,
          revision: _expectedRevision,
          title: _title.text.trim(),
          description: _description.text.trim(),
          kind: _kind,
          iconKey: _icon,
          sortOrder: int.parse(_order.text.trim()),
          archived: _archived,
        ),
      );
      if (!mounted) return;
      if (!_sameAccount) return;
      refresh();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Чат сохранён')));
      context.go('/admin/parishes/${widget.parishId}/chats');
    } on Object catch (error) {
      if (_sameAccount) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: ContentFrame(
        maxWidth: AppLayout.formMaxWidth,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.parishName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _title,
                onChanged: (_) {
                  if (_icon == 'auto') setState(() {});
                },
                enabled: !_busy,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Название чата'),
                validator: (v) => requiredText(v, 100),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _description,
                onChanged: (_) {
                  if (_icon == 'auto') setState(() {});
                },
                enabled: !_busy,
                minLines: 2,
                maxLines: 5,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                selectedItemBuilder: (context) => const [
                  Text(
                    'Групповой чат',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Канал объявлений',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'Тип'),
                items: const [
                  DropdownMenuItem(
                    value: 'group',
                    child: Text('Групповой чат'),
                  ),
                  DropdownMenuItem(
                    value: 'channel',
                    child: Text('Канал объявлений'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _kind = v);
                      },
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                _kind == 'channel'
                    ? 'Читают участники прихода. Пишут пользователи с правом публикации в каналах.'
                    : 'Участники прихода с правом отправки сообщений могут общаться здесь.',
              ),
              if (widget.chat?.access == 'restricted') ...[
                const SizedBox(height: AppSpace.sm),
                const Text('Для этого чата сохраняется доступ по приглашению.'),
              ],
              const SizedBox(height: AppSpace.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: ChatIconBadge(
                  iconKey: _icon,
                  title: _title.text,
                  description: _description.text,
                  seed: _id,
                ),
                title: const Text('Тематическая иконка'),
                subtitle: Text(
                  _icon == 'auto' ? 'Автоматически' : 'Выбрана вручную',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () async {
                        final icon = await showChatIconPicker(
                          context,
                          selected: _icon,
                          title: _title.text,
                          description: _description.text,
                          seed: _id,
                        );
                        if (mounted && icon != null)
                          setState(() => _icon = icon);
                      },
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _order,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Порядок в списке',
                  helperText: 'От 0 до 10000. Меньшее число — выше в списке.',
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  return n == null || n < 0 || n > 10000
                      ? 'Введите целое число от 0 до 10000'
                      : null;
                },
              ),
              const SizedBox(height: AppSpace.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _archived,
                onChanged: _busy ? null : (v) => setState(() => _archived = v),
                title: const Text('В архиве'),
                subtitle: const Text(
                  'Чат скрыт из меню, отправка отключена. История сообщений сохраняется.',
                ),
              ),
              if (_error != null) AdminError(_error!),
              const SizedBox(height: AppSpace.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Сохраняем…' : 'Сохранить чат'),
              ),
              const SizedBox(height: AppSpace.lg),
            ],
          ),
        ),
      ),
    ),
  );
}
