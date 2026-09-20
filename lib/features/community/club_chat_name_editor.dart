import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../auth/application/auth_providers.dart';
import 'community_repository.dart';

class ClubChatNameEditor extends ConsumerStatefulWidget {
  const ClubChatNameEditor({
    required this.club,
    required this.actor,
    required this.room,
    super.key,
  });
  final String club, actor;
  final JsonRow room;
  @override
  ConsumerState<ClubChatNameEditor> createState() => _ClubChatNameEditorState();
}

class _ClubChatNameEditorState extends ConsumerState<ClubChatNameEditor> {
  late final _title = TextEditingController(
    text: widget.room['title'] as String,
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || ref.read(authUserProvider).asData?.value?.id != widget.actor)
      return;
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Введите название');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('edit_club_chat_meta', {
            'p_youth': widget.club,
            'p_room': widget.room['id'],
            'p_title': _title.text.trim(),
            'p_icon': null,
            'p_revision': widget.room['revision'],
            'p_expected_user': widget.actor,
          })
          .timeout(const Duration(seconds: 20));
      if (mounted &&
          ref.read(authUserProvider).asData?.value?.id == widget.actor)
        Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Переименовать чат'),
      scrollable: true,
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('rename-chat-title'),
          controller: _title,
          autofocus: true,
          enabled: !_busy,
          maxLength: 100,
          decoration: InputDecoration(labelText: 'Название', errorText: _error),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('save-chat-name'),
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
        ),
      ],
    ),
  );
}
