import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../auth/application/auth_providers.dart';
import 'club_information_editor.dart';
import 'community_repository.dart';
import 'community_widgets.dart';

class ClubSettingsDialog extends ConsumerStatefulWidget {
  const ClubSettingsDialog({
    required this.club,
    required this.actor,
    super.key,
  });
  final String club, actor;
  @override
  ConsumerState<ClubSettingsDialog> createState() => _ClubSettingsDialogState();
}

class _ClubSettingsDialogState extends ConsumerState<ClubSettingsDialog> {
  bool _busy = false;
  String? _error;
  bool get _same =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actor;
  Future<void> _leave() async {
    if (_busy || !_same) return;
    if (!await confirmAction(
          context,
          'Вы точно хотите выйти?',
          'Доступ к чатам и внутренним разделам этого клуба будет закрыт. Вы сможете подать заявку снова.',
        ) ||
        !_same)
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('leave_youth_club', {
            'p_youth': widget.club,
            'p_expected_user': widget.actor,
          })
          .timeout(const Duration(seconds: 20));
      if (mounted && _same) Navigator.pop(context, true);
    } on Object catch (error) {
      if (_same) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final same = ref.watch(authUserProvider).asData?.value?.id == widget.actor;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: const Text('Настройки клуба'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ClubFieldLabel(
              'Участие в клубе',
              'Ваш аккаунт и участие в других клубах сохранятся.',
            ),
            OutlinedButton.icon(
              key: const ValueKey('leave-club'),
              onPressed: _busy || !same ? null : _leave,
              icon: const Icon(Icons.logout_rounded),
              label: Text(_busy ? 'Выходим…' : 'Покинуть клуб'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}
