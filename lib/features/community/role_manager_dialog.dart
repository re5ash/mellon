import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../../core/access/permission_providers.dart';
import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../auth/application/auth_providers.dart';
import '../profile/application/profile_providers.dart';
import 'club_directory_repository.dart';
import 'community_repository.dart';
import 'community_widgets.dart';
import 'role_manager_repository.dart';

class RolesEntry extends ConsumerWidget {
  const RolesEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    final state = ref.watch(accountAccessProvider);
    if (state.hasError)
      return CommunityTile(
        title: 'Роли',
        subtitle: 'Не удалось проверить доступ. Нажмите, чтобы повторить.',
        icon: Icons.manage_accounts_rounded,
        onTap: () => ref.read(accountAccessRefreshProvider).value++,
      );
    final access = state.asData?.value;
    if (access?.canManageRoles != true) return const SizedBox.shrink();
    return CommunityTile(
      title: 'Роли',
      subtitle: 'Участники и права доступа',
      icon: Icons.manage_accounts_rounded,
      onTap: user == null ? null : () => openRolesManager(context),
    );
  }
}

Future<void> openRolesManager(BuildContext context, {String? userId}) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Закрыть управление ролями',
      barrierColor: const Color(0xFF19354C).withValues(alpha: .30),
      transitionDuration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 280,
      ),
      pageBuilder: (_, animation, secondary) =>
          RoleManagerDialog(initialUser: userId),
      transitionBuilder: (_, animation, secondary, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
    );

class RoleManagerDialog extends ConsumerStatefulWidget {
  const RoleManagerDialog({this.initialUser, super.key});
  final String? initialUser;
  @override
  ConsumerState<RoleManagerDialog> createState() => _RoleManagerDialogState();
}

class _RoleManagerDialogState extends ConsumerState<RoleManagerDialog> {
  final _search = TextEditingController();
  final _detailScroll = ScrollController();
  Timer? _debounce;
  String? _actor;
  bool _starting = true;
  bool _globalChosen = false;
  String? _startError;
  int _startVersion = 0;
  List<RolePerson> _people = [];
  RolePersonDetails? _details;
  String? _selected,
      _club,
      _global,
      _request,
      _listError,
      _detailError,
      _saveError,
      _notice;
  final Map<String, String> _clubDraft = {};
  bool _loadingPeople = true,
      _loadingDetails = false,
      _more = false,
      _saving = false,
      _guestConfirmed = false;
  bool _confirmDiscard = false, _allowClose = false;
  VoidCallback? _afterDiscard;
  int _listVersion = 0, _detailVersion = 0;
  bool get _same =>
      mounted &&
      _actor != null &&
      ref.read(authUserProvider).asData?.value?.id == _actor &&
      ref.read(accountAccessProvider).asData?.value.canManageRoles != false;
  bool get _dirty =>
      _details != null && (_globalChosen || _clubDraft.isNotEmpty);
  RoleOption? get _globalOption =>
      _details?.globalRoles.where((r) => r.key == _global).firstOrNull;
  bool get _guestChange =>
      _globalOption?.isGuest == true && _details?.globalRole != _global;
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _canvas =>
      _dark ? Theme.of(context).colorScheme.surface : const Color(0xFFF7F9FC);
  Color get _card =>
      _dark ? Theme.of(context).colorScheme.surfaceContainerLow : Colors.white;
  Color get _accent =>
      _dark ? Theme.of(context).colorScheme.primary : const Color(0xFF368ED5);
  Color get _line => _dark
      ? Theme.of(context).colorScheme.outlineVariant
      : const Color(0xFFE2EBF3);
  Color get _tint => _dark
      ? Theme.of(context).colorScheme.primaryContainer
      : const Color(0xFFEAF4FE);
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  // A cold route may open before the restored auth stream emits its first
  // value. Bind once after both session and access are ready; never adopt a
  // different account while loading the original account's management window.
  Future<void> _start() async {
    final version = ++_startVersion;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final user = await ref.read(authUserProvider.future);
      if (!mounted || version != _startVersion || user == null) return;
      final access = await ref.read(accountAccessProvider.future);
      if (!mounted || version != _startVersion) return;
      if (ref.read(authUserProvider).asData?.value?.id != user.id) {
        setState(
          () => _startError =
              'Аккаунт изменился во время загрузки. Закройте окно и откройте его заново.',
        );
        return;
      }
      _actor = user.id;
      if (!access.canManageRoles) return;
      unawaited(_loadPeople());
      if (widget.initialUser != null)
        unawaited(_loadPerson(widget.initialUser!));
    } on Object catch (e) {
      if (mounted && version == _startVersion)
        setState(() => _startError = userError(e));
    } finally {
      if (mounted && version == _startVersion)
        setState(() => _starting = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _detailScroll.dispose();
    super.dispose();
  }

  Future<void> _loadPeople({bool more = false}) async {
    final version = ++_listVersion;
    setState(() {
      _loadingPeople = true;
      _listError = null;
    });
    try {
      final rows = await ref
          .read(roleManagerRepositoryProvider)
          .people(
            _search.text.trim(),
            more && _people.isNotEmpty ? _people.last.id : null,
          );
      if (!_same || version != _listVersion) return;
      setState(() {
        _people = [...(more ? _people : <RolePerson>[]), ...rows.take(30)];
        _more = rows.length > 30;
      });
    } on Object catch (e) {
      if (_same && version == _listVersion)
        setState(() => _listError = userError(e));
    } finally {
      if (mounted && version == _listVersion)
        setState(() => _loadingPeople = false);
    }
  }

  Future<void> _loadPerson(String id) async {
    final version = ++_detailVersion;
    setState(() {
      _selected = id;
      _loadingDetails = true;
      _details = null;
      _clubDraft.clear();
      _global = null;
      _globalChosen = false;
      _club = null;
      _detailError = null;
      _saveError = null;
      _notice = null;
      _request = null;
      _guestConfirmed = false;
    });
    try {
      final details = await ref.read(roleManagerRepositoryProvider).person(id);
      if (!_same || version != _detailVersion || details.person.id != id)
        return;
      setState(() {
        _details = details;
        _global = details.globalRole;
        _globalChosen = false;
      });
    } on Object catch (e) {
      if (_same && version == _detailVersion)
        setState(() => _detailError = userError(e));
    } finally {
      if (mounted && version == _detailVersion)
        setState(() => _loadingDetails = false);
    }
  }

  void _change(VoidCallback action) {
    setState(() {
      action();
      _saveError = null;
      _notice = null;
      _request = null;
    });
  }

  void _navigate(VoidCallback action) {
    if (_saving) return;
    if (!_dirty) {
      action();
      return;
    }
    setState(() {
      _confirmDiscard = true;
      _afterDiscard = action;
    });
  }

  void _back() => _navigate(() {
    setState(() {
      _detailVersion++;
      _selected = null;
      _details = null;
      _clubDraft.clear();
      _global = null;
      _globalChosen = false;
      _saveError = null;
      _notice = null;
    });
  });
  void _pop() {
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _close() => _navigate(_pop);
  Future<void> _save() async {
    if (!_same ||
        _saving ||
        !_dirty ||
        _details == null ||
        (_guestChange && !_guestConfirmed))
      return;
    final details = _details!;
    final global = _globalChosen ? _global : null;
    final clubs = Map<String, String>.of(_clubDraft);
    final request = _request ??= newUuid();
    setState(() {
      _saving = true;
      _saveError = null;
      _notice = null;
    });
    try {
      await ref
          .read(roleManagerRepositoryProvider)
          .save(
            user: details.person.id,
            actor: _actor!,
            revision: details.revision,
            request: request,
            globalRole: global,
            clubs: clubs,
          )
          .timeout(const Duration(seconds: 25));
      if (!_same) return;
      setState(() {
        _clubDraft.clear();
        _global = details.globalRole;
        _globalChosen = false;
        _request = null;
      });
      ref.invalidate(accountAccessProvider);
      ref.invalidate(permissionsProvider);
      ref.invalidate(scopePermissionsProvider);
      ref.invalidate(myYouthProvider);
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(clubWorkspacesProvider);
      ref.invalidate(ownProfileProvider);
      if (details.person.id == _actor) {
        _pop();
        return;
      }
      final selectedClub = _club;
      await _loadPerson(details.person.id);
      if (!_same) return;
      setState(() {
        _club = selectedClub;
        _notice = 'Изменения сохранены';
      });
      unawaited(_loadPeople());
    } on Object catch (e) {
      if (_same)
        setState(
          () => _saveError = e is TimeoutException
              ? 'Ответ задерживается. Повторите сохранение: уже выполненные изменения не продублируются.'
              : userError(e),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _avatar(RolePerson person, {double radius = 23}) {
    final url = person.avatar == null
        ? null
        : ref.watch(roleAvatarProvider(person.avatar!)).asData?.value;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url),
      onForegroundImageError: url == null ? null : (_, stack) {},
      child: Text(
        person.name.isEmpty ? '?' : person.name.characters.first.toUpperCase(),
      ),
    );
  }

  Widget _peoplePane() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TextField(
          key: const ValueKey('roles-search'),
          controller: _search,
          enabled: !_saving,
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => unawaited(_loadPeople()),
            );
          },
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: _accent),
            hintText: 'Поиск по имени',
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide(color: _accent),
            ),
          ),
        ),
      ),
      if (_loadingPeople) const LinearProgressIndicator(),
      if (_listError != null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(_listError!),
              TextButton(
                onPressed: () => _loadPeople(),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      Expanded(
        child: ListView(
          key: const ValueKey('roles-people-list'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            if (!_loadingPeople && _people.isEmpty && _listError == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Участники не найдены'),
              ),
            for (final person in _people)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: _selected == person.id ? _tint : _card,
                  elevation: _selected == person.id ? 2 : 0,
                  shadowColor: _accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    key: ValueKey('role-person-${person.id}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: _saving
                        ? null
                        : () => _navigate(
                            () => unawaited(_loadPerson(person.id)),
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _avatar(person),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  person.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  person.summary,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_more)
              TextButton(
                onPressed: _loadingPeople || _saving
                    ? null
                    : () => _loadPeople(more: true),
                child: const Text('Показать ещё'),
              ),
          ],
        ),
      ),
    ],
  );
  Widget _block(
    String title,
    String subtitle,
    IconData icon,
    List<Widget> children,
  ) => Container(
    margin: const EdgeInsets.only(top: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: _line),
      boxShadow: [
        BoxShadow(
          color: _accent.withValues(alpha: .045),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _tint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: _accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );
  Widget _info(String text, {bool warning = false}) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: warning
          ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: .45)
          : _tint,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          warning ? Icons.info_outline_rounded : Icons.info_rounded,
          size: 20,
          color: warning ? Theme.of(context).colorScheme.error : _accent,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
  Widget _roleRadios({
    required String scope,
    required List<RoleOption> options,
    required String? selected,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    if (options.isEmpty)
      return const Text('В этой области пока нет доступных ролей.');
    return RadioGroup<String>(
      key: ValueKey('$scope-radios'),
      groupValue: selected,
      onChanged: (value) {
        if (value == null || !enabled || _saving) return;
        if (!options.any((r) => r.key == value && r.assignable)) return;
        onChanged(value);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns =
              constraints.maxWidth >= 440 &&
              MediaQuery.textScalerOf(context).scale(14) <= 18;
          final width = twoColumns
              ? (constraints.maxWidth - 10) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in options)
                SizedBox(
                  width: width,
                  child: Material(
                    color: selected == option.key ? _tint : _card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: selected == option.key
                            ? _accent.withValues(alpha: .55)
                            : _line,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RadioListTile<String>(
                      key: ValueKey('$scope-${option.key}'),
                      value: option.key,
                      enabled: enabled && !_saving && option.assignable,
                      selected: selected == option.key,
                      activeColor: _accent,
                      toggleable: false,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      title: Text(
                        option.title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _editor() {
    final d = _details;
    if (_loadingDetails)
      return const Center(child: CircularProgressIndicator());
    if (_detailError != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_detailError!),
              TextButton(
                onPressed: _saving ? null : () => _loadPerson(_selected!),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    if (d == null)
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Выберите человека, чтобы настроить права доступа.'),
        ),
      );
    final selected = d.clubs.where((c) => c.id == _club).firstOrNull;
    final selectedRole = selected == null
        ? null
        : _clubDraft[selected.id] ?? selected.role;
    final canEdit = selected != null && selected.canEdit;
    return SingleChildScrollView(
      key: const ValueKey('roles-person-editor'),
      controller: _detailScroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(d.person, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.person.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (d.email.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(d.email),
                    ],
                  ],
                ),
              ),
            ],
          ),
          _block(
            'Всё приложение',
            'Одна глобальная роль для аккаунта',
            Icons.public,
            [
              _roleRadios(
                scope: 'global',
                options: d.globalRoles,
                selected: d.globalMultipleRoles && !_globalChosen
                    ? null
                    : _global,
                enabled: d.canGlobal,
                onChanged: (key) => _change(() {
                  _global = key;
                  _globalChosen = key != d.globalRole || d.globalMultipleRoles;
                  _guestConfirmed = false;
                }),
              ),
              if (d.globalMultipleRoles)
                _info(
                  'Ранее назначено несколько глобальных ролей. Выберите одну, чтобы заменить их при сохранении. Настройки клубов сохранятся.',
                ),
              if (!d.canGlobal)
                _info('Глобальные права может изменять суперадмин.'),
              if (_globalOption?.isMember == true)
                _info(
                  'Обычный доступ к аккаунту. Права молодёжных клубов настраиваются ниже.',
                ),
              if (_global == 'super_admin')
                _info(
                  'Полное управление приложением и всеми молодёжными клубами.',
                ),
              if (_globalOption?.isGuest == true) ...[
                _info(
                  'Доступны только общая лента, карта и окно регистрации. Доступ будет ограничен, но аккаунт не удаляется. Настройки клубов сохраняются и снова действуют после снятия гостевого ограничения.',
                  warning: true,
                ),
                if (_guestChange)
                  SwitchListTile.adaptive(
                    key: const ValueKey('confirm-guest'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Подтверждаю ограничение доступа'),
                    value: _guestConfirmed,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _guestConfirmed = value),
                  ),
              ],
            ],
          ),
          _block(
            'Молодёжный клуб',
            'Роль действует только в выбранном клубе',
            Icons.groups_rounded,
            [
              if (d.clubs.isEmpty)
                const Text('Молодёжных клубов пока нет.')
              else
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const ValueKey('roles-club-select'),
                    isExpanded: true,
                    itemHeight: null,
                    value: _club,
                    hint: const Text('Выбрать молодёжный клуб'),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _club = value),
                    items: [
                      for (final c in d.clubs)
                        DropdownMenuItem(
                          value: c.id,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                              c.archived ? '${c.name} · В архиве' : c.name,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (selected != null) ...[
                const SizedBox(height: 12),
                if (selectedRole == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('Роль в этом клубе ещё не назначена.'),
                  ),
                _roleRadios(
                  scope: 'club',
                  options: selected.roles
                      .where((role) => !role.isGuest)
                      .toList(),
                  selected:
                      selected.multipleRoles &&
                          !_clubDraft.containsKey(selected.id)
                      ? null
                      : selectedRole,
                  enabled: canEdit,
                  onChanged: (key) => _change(() {
                    if (selected.role == key && !selected.multipleRoles) {
                      _clubDraft.remove(selected.id);
                    } else {
                      _clubDraft[selected.id] = key;
                    }
                  }),
                ),
                if (selected.multipleRoles)
                  _info(
                    'В этом клубе ранее назначено несколько ролей. Выберите одну для сохранения. Права в остальных клубах сохранятся.',
                  ),
                if (selected.inheritedRights)
                  _info(
                    'У человека есть дополнительные права, выданные ранее. Они сохраняются: здесь изменяется только роль выбранного клуба.',
                  ),
                if (!canEdit)
                  _info(
                    selected.archived
                        ? 'Клуб в архиве. Его роли сейчас доступны только для просмотра.'
                        : 'У вас нет прав изменять роль этого участника в выбранном клубе.',
                  ),
              ],
              if (_clubDraft.isNotEmpty)
                _info(
                  'Будут сохранены изменения: ${d.clubs.where((c) => _clubDraft.containsKey(c.id)).map((c) => '${c.name} — ${c.roleTitle(_clubDraft[c.id])}').join('; ')}.',
                ),
            ],
          ),
          _info(
            'Изменение роли в одном клубе не сбрасывает права в других клубах.',
          ),
          if (_saveError != null)
            Semantics(
              liveRegion: true,
              child: _info(_saveError!, warning: true),
            ),
          if (_saveError != null)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _navigate(() => unawaited(_loadPerson(d.person.id))),
              child: const Text('Загрузить актуальные права'),
            ),
          if (_notice != null)
            Semantics(liveRegion: true, child: _info(_notice!)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authUserProvider);
    ref.watch(accountAccessProvider);
    final same = _same;
    return PopScope(
      canPop: _allowClose || !same || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_saving) _close();
      },
      child: SafeArea(
        child: Dialog(
          key: const ValueKey('role-manager-dialog'),
          backgroundColor: _canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 18,
          shadowColor: const Color(0xFF24496C).withValues(alpha: .18),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 780;
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 10, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!wide && _selected != null && same)
                              IconButton(
                                key: const ValueKey('roles-back'),
                                onPressed: _saving ? null : _back,
                                tooltip: 'К списку людей',
                                icon: const Icon(Icons.arrow_back),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Управление ролями',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  const Text('Участники и права доступа'),
                                ],
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('roles-close'),
                              tooltip: 'Закрыть',
                              onPressed: _saving
                                  ? null
                                  : (same ? _close : _pop),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      if (_starting)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_startError != null)
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_startError!),
                                  TextButton(
                                    onPressed: _start,
                                    child: const Text('Повторить загрузку'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else if (!same)
                        const Expanded(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Аккаунт или права доступа изменились. Закройте это окно и откройте управление заново.',
                              ),
                            ),
                          ),
                        )
                      else if (_confirmDiscard)
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Есть несохранённые изменения'),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Остаться в карточке или отменить изменения перед выходом?',
                                  ),
                                  const SizedBox(height: 18),
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _confirmDiscard = false;
                                      _afterDiscard = null;
                                    }),
                                    child: const Text(
                                      'Вернуться к редактированию',
                                    ),
                                  ),
                                  TextButton(
                                    key: const ValueKey('roles-discard'),
                                    onPressed: () {
                                      final action = _afterDiscard;
                                      setState(() {
                                        _confirmDiscard = false;
                                        _afterDiscard = null;
                                        _clubDraft.clear();
                                        _global = _details?.globalRole;
                                        _globalChosen = false;
                                      });
                                      action?.call();
                                    },
                                    child: const Text('Отменить изменения'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: wide
                              ? Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(width: 300, child: _peoplePane()),
                                    const VerticalDivider(width: 1),
                                    Expanded(child: _editor()),
                                  ],
                                )
                              : AnimatedSwitcher(
                                  duration: Duration(
                                    milliseconds:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? 0
                                        : 220,
                                  ),
                                  child: _selected == null
                                      ? KeyedSubtree(
                                          key: const ValueKey('people'),
                                          child: _peoplePane(),
                                        )
                                      : KeyedSubtree(
                                          key: const ValueKey('person'),
                                          child: _editor(),
                                        ),
                                ),
                        ),
                        if (_details != null && !_loadingDetails)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                            child: FilledButton(
                              key: const ValueKey('roles-save'),
                              style: FilledButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: _dark
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Colors.white,
                                elevation: 2,
                                shadowColor: _accent.withValues(alpha: .22),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                  horizontal: 20,
                                ),
                              ),
                              onPressed:
                                  !_dirty ||
                                      _saving ||
                                      (_guestChange && !_guestConfirmed)
                                  ? null
                                  : _save,
                              child: Text(
                                _saving ? 'Сохраняем…' : 'Сохранить изменения',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
