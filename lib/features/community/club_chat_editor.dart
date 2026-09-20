import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../auth/application/auth_providers.dart';
import '../chats/presentation/chat_icon_badge.dart';
import '../chats/presentation/chat_icon_picker.dart';
import 'community_repository.dart';

class ClubChatEditor extends ConsumerStatefulWidget {
  const ClubChatEditor({
    required this.club,
    required this.actor,
    this.room,
    this.sort = 100,
    super.key,
  });
  final String club, actor;
  final JsonRow? room;
  final int sort;
  @override
  ConsumerState<ClubChatEditor> createState() => _ClubChatEditorState();
}

class _ClubChatEditorState extends ConsumerState<ClubChatEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _description;
  late final String _id;
  late String _icon, _kind;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _id = widget.room?['id'] as String? ?? newUuid();
    _title = TextEditingController(
      text: widget.room?['title'] as String? ?? '',
    );
    _description = TextEditingController(
      text: widget.room?['description'] as String? ?? '',
    );
    _icon = widget.room?['icon_key'] as String? ?? 'auto';
    _kind = widget.room?['kind'] as String? ?? 'group';
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (ref.read(authUserProvider).asData?.value?.id != widget.actor) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('save_club_chat', {
            'p_youth': widget.club,
            'p_id': _id,
            'p_title': _title.text.trim(),
            'p_description': _description.text.trim(),
            'p_icon': _icon,
            'p_kind': _kind,
            'p_access': widget.room?['access'] == 'active'
                ? 'active'
                : 'parish',
            'p_sort': widget.room?['sort_order'] ?? widget.sort,
            'p_revision': widget.room?['revision'],
            'p_expected_user': widget.actor,
          })
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (ref.read(authUserProvider).asData?.value?.id != widget.actor) return;
      Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameAccount =
        ref.watch(authUserProvider).asData?.value?.id == widget.actor;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.room == null ? 'Добавить чат' : 'Изменить чат'),
        scrollable: true,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: !sameAccount
              ? const Text('Аккаунт изменился. Откройте настройки чата заново.')
              : Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('club-chat-title'),
                        controller: _title,
                        onChanged: (_) {
                          if (_icon == 'auto') setState(() {});
                        },
                        maxLength: 100,
                        readOnly: _busy,
                        decoration: const InputDecoration(
                          labelText: 'Название',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Введите название чата'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _description,
                        onChanged: (_) {
                          if (_icon == 'auto') setState(() {});
                        },
                        readOnly: _busy,
                        minLines: 2,
                        maxLines: 4,
                        maxLength: 300,
                        decoration: const InputDecoration(
                          labelText: 'Описание',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _kind,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Тип чата',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'group',
                            child: Text('Общий чат'),
                          ),
                          DropdownMenuItem(
                            value: 'channel',
                            child: Text('Канал объявлений'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _kind = value!),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Иконка',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
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
                                final selected = await showChatIconPicker(
                                  context,
                                  selected: _icon,
                                  title: _title.text,
                                  description: _description.text,
                                  seed: _id,
                                );
                                if (mounted && selected != null)
                                  setState(() => _icon = selected);
                              },
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('save-club-chat'),
            onPressed: _busy || !sameAccount ? null : _save,
            child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}
