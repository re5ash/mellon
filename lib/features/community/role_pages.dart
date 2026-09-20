import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/permission_providers.dart';
import '../../core/errors/app_failure.dart';
import '../auth/application/auth_providers.dart';
import 'community_repository.dart';
import 'community_widgets.dart';
import 'role_manager_dialog.dart';

class ScopeMembersPage extends ConsumerStatefulWidget {
  const ScopeMembersPage({required this.scope, super.key});
  final CommunityScope scope;
  @override
  ConsumerState<ScopeMembersPage> createState() => _ScopeMembersPageState();
}

class _ScopeMembersPageState extends ConsumerState<ScopeMembersPage> {
  final _search = TextEditingController();
  final _history = <String?>[null];
  late Future<List<JsonRow>> _data;
  late String? _actor;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _load() {
    _data = ref
        .read(communityRepositoryProvider)
        .members(widget.scope, _search.text, _history.last);
  }

  bool get _same =>
      mounted &&
      _actor != null &&
      _actor == ref.read(authUserProvider).asData?.value?.id;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_same) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (_same) setState(_load);
      ref.invalidate(scopePermissionsProvider);
      ref.invalidate(permissionsProvider);
      ref.invalidate(myYouthProvider);
    } on Object catch (e) {
      if (_same) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _member(JsonRow row, bool member, bool active) async {
    if (_busy || !_same) return;
    if (!member &&
        !await confirmAction(
          context,
          'Убрать участника?',
          'Доступ к молодёжке, её чатам и назначенные здесь роли будут сняты.',
        ))
      return;
    if (!mounted || !_same) return;
    await _run(() async {
      await ref.read(communityRepositoryProvider).call('set_youth_member', {
        'p_youth': widget.scope.youth,
        'p_user': row['user_id'],
        'p_member': member,
        'p_activist': active,
        'p_revision': row['member_revision'],
      });
    });
  }

  Future<void> _assign(JsonRow row) async {
    if (_busy || !_same) return;
    await openRolesManager(context, userId: row['user_id'] as String);
    if (_same) setState(_load);
  }

  Future<void> _revoke(JsonRow a) async {
    if (_busy ||
        !_same ||
        !await confirmAction(
          context,
          'Снять роль «${a['title']}»?',
          'Права этой роли перестанут действовать.',
        ))
      return;
    if (!mounted || !_same) return;
    await _run(() async {
      await ref.read(communityRepositoryProvider).call('revoke_role', {
        'p_assignment': a['id'],
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final rights =
        ref.watch(scopePermissionsProvider(widget.scope)).asData?.value ??
        <String>{};
    return CommunityScaffold(
      title: widget.scope.youth == null
          ? 'Участники прихода'
          : 'Участники и актив',
      children: [
        TextField(
          controller: _search,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'Поиск по имени или ID',
            suffixIcon: IconButton(
              tooltip: 'Найти',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _history
                        ..clear()
                        ..add(null);
                      _load();
                    }),
              icon: const Icon(Icons.search),
            ),
          ),
          onSubmitted: (_) {
            if (!_busy)
              setState(() {
                _history
                  ..clear()
                  ..add(null);
                _load();
              });
          },
        ),
        if (widget.scope.youth != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '«Актив» — статус участника с доступом к закрытому чату. Роли настраиваются в разделе «Роли».',
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FutureBuilder<List<JsonRow>>(
          future: _data,
          builder: (c, s) {
            if (s.hasError) return Text(userError(s.error!));
            if (!s.hasData) return const LinearProgressIndicator();
            final rows = s.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rows.isEmpty) const Text('Участники не найдены.'),
                for (final row in rows.take(30))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            row['display_name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SelectableText(
                            row['user_id'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (widget.scope.youth != null &&
                              rights.contains('youth.members.manage'))
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Участник молодёжки'),
                              value: row['is_youth_member'] == true,
                              onChanged: _busy
                                  ? null
                                  : (v) => _member(
                                      row,
                                      v,
                                      v && row['is_activist'] == true,
                                    ),
                            ),
                          if (widget.scope.youth != null &&
                              row['is_youth_member'] == true &&
                              rights.contains('youth.active.manage'))
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Актив'),
                              subtitle: const Text(
                                'Открыть закрытый чат актива',
                              ),
                              value: row['is_activist'] == true,
                              onChanged: _busy
                                  ? null
                                  : (v) => _member(row, true, v),
                            ),
                          for (final raw in row['assignments'] as List<dynamic>)
                            Builder(
                              builder: (c) {
                                final a = raw as JsonRow;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified_user_outlined),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(a['title'] as String),
                                      ),
                                      if (a['can_revoke'] == true)
                                        IconButton(
                                          tooltip: 'Снять роль',
                                          onPressed: _busy
                                              ? null
                                              : () => _revoke(a),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          if (widget.scope.youth == null ||
                              row['is_youth_member'] == true)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : () => _assign(row),
                              icon: const Icon(Icons.add_moderator_outlined),
                              label: const Text('Назначить роль'),
                            ),
                        ],
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    if (_history.length > 1)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _history.removeLast();
                                _load();
                              }),
                        child: const Text('Назад'),
                      ),
                    if (rows.length > 30)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _history.add(rows[29]['user_id'] as String);
                                _load();
                              }),
                        child: const Text('Далее'),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class RoleCatalogPage extends ConsumerStatefulWidget {
  const RoleCatalogPage({super.key});
  @override
  ConsumerState<RoleCatalogPage> createState() => _RoleCatalogPageState();
}

class _RoleCatalogPageState extends ConsumerState<RoleCatalogPage> {
  late Future<List<JsonRow>> _data;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref.read(communityRepositoryProvider).rows('role_catalog');
  }

  Future<void> _edit([JsonRow? row]) async {
    await openCommunity(context, RoleEditor(row: row));
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Роли и права',
    children: [
      FilledButton.icon(
        onPressed: _edit,
        icon: const Icon(Icons.add),
        label: const Text('Создать роль'),
      ),
      FutureBuilder<List<JsonRow>>(
        future: _data,
        builder: (c, s) {
          if (s.hasError) return Text(userError(s.error!));
          if (!s.hasData) return const LinearProgressIndicator();
          return Column(
            children: [
              for (final row in s.data!)
                CommunityTile(
                  title: row['title'] as String,
                  subtitle:
                      '${scopeLabel(row['scope'] as String)} · ${(row['permissions'] as List<dynamic>).length} прав',
                  icon: Icons.policy_outlined,
                  onTap: () => _edit(row),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class RoleEditor extends ConsumerStatefulWidget {
  const RoleEditor({this.row, super.key});
  final JsonRow? row;
  @override
  ConsumerState<RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends ConsumerState<RoleEditor> {
  final _key = TextEditingController(), _title = TextEditingController();
  String _scope = 'youth';
  final _selected = <String>{};
  late Future<List<JsonRow>> _permissions;
  late String? _actor;
  bool _busy = false;
  String? _error;
  bool get _protected => const {
    'guest',
    'user',
    'super_admin',
    'parish_admin',
    'youth_admin',
    'youth_leader',
    'youth_moderator',
  }.contains(widget.row?['role_key']);
  @override
  void initState() {
    super.initState();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _key.text = widget.row?['role_key'] as String? ?? '';
    _title.text = widget.row?['title'] as String? ?? '';
    _scope = widget.row?['scope'] as String? ?? 'youth';
    _selected.addAll(
      (widget.row?['permissions'] as List<dynamic>? ?? []).cast<String>(),
    );
    _permissions = ref
        .read(communityRepositoryProvider)
        .rows('permission_catalog');
  }

  @override
  void dispose() {
    _key.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        _protected ||
        _actor != ref.read(authUserProvider).asData?.value?.id)
      return;
    setState(() => _busy = true);
    try {
      await ref.read(communityRepositoryProvider).call('define_role', {
        'p_key': _key.text.trim(),
        'p_title': _title.text.trim(),
        'p_scope': _scope,
        'p_permissions': _selected.toList(),
      });
      ref.invalidate(scopePermissionsProvider);
      ref.invalidate(permissionsProvider);
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Права роли',
    children: [
      if (_protected)
        const Text(
          'Встроенная роль. Для другого набора прав создайте свою роль.',
        ),
      TextField(
        controller: _title,
        enabled: !_busy && !_protected,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Название'),
      ),
      TextField(
        controller: _key,
        enabled: !_busy && widget.row == null,
        maxLength: 64,
        decoration: const InputDecoration(
          labelText: 'Ключ роли',
          helperText: 'Латинские буквы, цифры и подчёркивание; от 3 символов',
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final s in ['global', 'parish', 'youth'])
            ChoiceChip(
              label: Text(scopeLabel(s)),
              selected: _scope == s,
              onSelected: _busy || widget.row != null
                  ? null
                  : (_) => setState(() {
                      _scope = s;
                      _selected.clear();
                    }),
            ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<JsonRow>>(
        future: _permissions,
        builder: (c, s) {
          if (s.hasError) return Text(userError(s.error!));
          if (!s.hasData) return const LinearProgressIndicator();
          return Column(
            children: [
              for (final p in s.data!)
                if (_scope == 'global' || p['scope'] != 'global')
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(p['description'] as String),
                    subtitle: Text(p['key'] as String),
                    value: _selected.contains(p['key']),
                    onChanged: _busy || _protected
                        ? null
                        : (v) => setState(() {
                            if (v == true) {
                              _selected.add(p['key'] as String);
                            } else {
                              _selected.remove(p['key']);
                            }
                          }),
                  ),
            ],
          );
        },
      ),
      if (_error != null) Text(_error!),
      if (!_protected)
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить роль'),
        ),
    ],
  );
}
