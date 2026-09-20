import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/account_access_provider.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/club_registration_dialog.dart';
import '../../features/community/club_directory_repository.dart';

class AccountMenu extends ConsumerStatefulWidget {
  const AccountMenu({this.parishStyle = false, super.key});
  final bool parishStyle;
  @override
  ConsumerState<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends ConsumerState<AccountMenu> {
  bool _opening = false;

  void _showActionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Не удалось выполнить действие. Попробуйте ещё раз.'),
      ),
    );
  }

  Future<void> _openPage(String location) async {
    try {
      // This future completes when the page is popped. The shared shell menu
      // must stay usable while Settings or Management is still on the stack.
      await context.push<void>(location);
    } on Object {
      _showActionError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).asData?.value;
    final access = ref.watch(accountAccessProvider).asData?.value;
    final restricted = access?.restrictedGuest == true;
    final workspaces = user == null || restricted
        ? <Map<String, dynamic>>[]
        : ref.watch(clubWorkspacesProvider).asData?.value ?? [];
    final canManage =
        !restricted &&
        (access?.superAdmin == true ||
            access?.canManageRoles == true ||
            workspaces.isNotEmpty);
    return PopupMenuButton<String>(
      enabled: !_opening,
      tooltip: 'Профиль и меню',
      icon: Icon(
        widget.parishStyle ? Icons.more_vert : Icons.account_circle_outlined,
      ),
      onSelected: (action) async {
        if (_opening) return;
        setState(() => _opening = true);
        try {
          if (action == 'sign-in') {
            await openClubRegistration(context, startWithSignIn: true);
          } else if (action == 'sign-out') {
            await ref.read(authRepositoryProvider).signOut();
            if (context.mounted) context.go('/feed');
          } else {
            unawaited(_openPage(action));
          }
        } on Object {
          _showActionError();
        } finally {
          if (mounted) setState(() => _opening = false);
        }
      },
      itemBuilder: (context) => [
        if (!restricted)
          const PopupMenuItem(value: '/profile', child: Text('Настройки')),
        if (canManage)
          const PopupMenuItem(value: '/admin', child: Text('Управление')),
        if (user == null)
          const PopupMenuItem(value: 'sign-in', child: Text('Войти'))
        else
          const PopupMenuItem(value: 'sign-out', child: Text('Выйти')),
      ],
    );
  }
}
