import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_branding.dart';
import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../auth/application/auth_providers.dart';
import '../map/application/map_providers.dart';
import '../map/presentation/event_map_field.dart';
import 'community_repository.dart';
import 'community_widgets.dart';

class ScopeContentPage extends ConsumerStatefulWidget {
  const ScopeContentPage({required this.scope, required this.kind, super.key});
  final CommunityScope scope;
  final String kind;
  @override
  ConsumerState<ScopeContentPage> createState() => _ScopeContentPageState();
}

class _ScopeContentPageState extends ConsumerState<ScopeContentPage> {
  late Future<List<JsonRow>> _data;
  final _history = <String?>[null];
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = ref
        .read(communityRepositoryProvider)
        .content(widget.scope, widget.kind, _history.last);
  }

  Future<void> _edit([JsonRow? row]) async {
    await openCommunity(
      context,
      ContentEditor(scope: widget.scope, kind: widget.kind, row: row),
    );
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final rights =
        ref.watch(scopePermissionsProvider(widget.scope)).asData?.value ??
        <String>{};
    return CommunityScaffold(
      title: contentLabel(widget.kind),
      actions: [
        IconButton(
          tooltip: 'Обновить',
          onPressed: () => setState(_load),
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        if (mayCreate(rights, widget.kind))
          FilledButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.add),
            label: const Text('Создать'),
          ),
        const SizedBox(height: 16),
        FutureBuilder<List<JsonRow>>(
          future: _data,
          builder: (c, s) {
            if (s.hasError) return Text(userError(s.error!));
            if (!s.hasData) return const LinearProgressIndicator();
            final rows = s.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rows.isEmpty) const Text('Здесь пока ничего нет.'),
                for (final row in rows.take(30))
                  CommunityTile(
                    title: row['title'] as String,
                    icon: widget.kind == 'events'
                        ? Icons.event_outlined
                        : widget.kind == 'chats'
                        ? Icons.forum_outlined
                        : Icons.article_outlined,
                    subtitle: widget.kind == 'chats'
                        ? '${row['is_archived'] == true ? 'В архиве' : 'Доступен'} · Порядок ${row['sort_order']}'
                        : widget.kind == 'events'
                        ? '${stateLabel(row['status'] as String?)}\n${DateTime.parse(row['starts_at'] as String).toLocal()}'
                        : stateLabel(row['status'] as String?),
                    onTap: mayEdit(rights, widget.kind)
                        ? () => _edit(row)
                        : null,
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    if (_history.length > 1)
                      TextButton(
                        onPressed: () => setState(() {
                          _history.removeLast();
                          _load();
                        }),
                        child: const Text('Назад'),
                      ),
                    if (rows.length > 30)
                      TextButton(
                        onPressed: () => setState(() {
                          _history.add(rows[29]['id'] as String);
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

class ContentEditor extends ConsumerStatefulWidget {
  const ContentEditor({
    required this.scope,
    required this.kind,
    this.row,
    super.key,
  });
  final CommunityScope scope;
  final String kind;
  final JsonRow? row;
  @override
  ConsumerState<ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends ConsumerState<ContentEditor> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _body = TextEditingController(),
      _location = TextEditingController(),
      _sort = TextEditingController();
  late String _id;
  late String? _actor;
  String _status = 'draft',
      _visibility = 'parish',
      _chatKind = 'group',
      _access = 'parish';
  bool _archived = false, _busy = false;
  String? _error;
  late DateTime _start, _end;
  late EventMapValue _mapValue;
  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _mapValue = EventMapValue.fromJson(r);
    _id = r?['id'] as String? ?? newUuid();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _title.text = r?['title'] as String? ?? '';
    _body.text =
        (r?[widget.kind == 'posts' ? 'body' : 'description'] as String?) ?? '';
    _location.text = r?['location_label'] as String? ?? '';
    _sort.text = '${r?['sort_order'] ?? 100}';
    _status = r?['status'] as String? ?? 'draft';
    _visibility = r?['visibility'] as String? ?? 'parish';
    _chatKind = r?['kind'] as String? ?? 'group';
    _access = r?['access'] == 'active' ? 'active' : 'parish';
    _archived = r?['is_archived'] == true;
    _start = r?['starts_at'] == null
        ? DateTime.now().add(const Duration(days: 1))
        : DateTime.parse(r!['starts_at'] as String).toLocal();
    _end = r?['ends_at'] == null
        ? _start.add(const Duration(hours: 1))
        : DateTime.parse(r!['ends_at'] as String).toLocal();
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _location, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _same =>
      _actor != null && _actor == ref.read(authUserProvider).asData?.value?.id;
  String? get _expected => widget
      .row?[widget.kind == 'chats' ? 'revision' : 'updated_at']
      ?.toString();
  Future<void> _date(bool start) async {
    final initial = start ? _start : _end;
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted || !_same) return;
    setState(() {
      final dt = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      if (start) {
        _start = dt;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = dt;
      }
    });
  }

  Future<void> _save() async {
    if (_busy || !_same || !_form.currentState!.validate()) return;
    if (widget.kind == 'events' && !_end.isAfter(_start)) {
      setState(() => _error = 'Окончание должно быть позже начала.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .saveContent(
            widget.scope,
            widget.kind,
            _id,
            {
              'title': _title.text,
              'body': _body.text,
              'status': _status,
              'visibility': _visibility,
              'starts_at': _start.toUtc().toIso8601String(),
              'ends_at': _end.toUtc().toIso8601String(),
              'location': _location.text,
              'sort_order': int.tryParse(_sort.text),
              'is_archived': _archived,
              'kind': _chatKind,
              'access': _access,
              if (widget.kind == 'events') ..._mapValue.payload,
            },
            _expected,
            _actor!,
          );
      if (mounted && _same) {
        if (widget.kind == 'events') ref.invalidate(mapEventsProvider);
        Navigator.pop(context);
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy || !_same) return;
    if (!await confirmAction(
          context,
          'Удалить запись?',
          'Запись будет удалена. Отменить удаление нельзя.',
        ) ||
        !mounted ||
        !_same)
      return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      await repo.call('delete_scope_content', {
        ...repo.args(widget.scope),
        'p_kind': widget.kind,
        'p_id': _id,
        'p_expected': _expected,
        'p_expected_user': _actor,
      });
      if (mounted && _same) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices(
    String title,
    String current,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in options.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: current == entry.key,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => change(entry.key)),
              ),
          ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final rights =
        ref.watch(scopePermissionsProvider(widget.scope)).asData?.value ??
        <String>{};
    return CommunityScaffold(
      title: widget.row == null ? 'Создание' : 'Редактирование',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                enabled: !_busy,
                maxLength: widget.kind == 'chats' ? 100 : 200,
                decoration: const InputDecoration(labelText: 'Название'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Введите название' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _body,
                enabled: !_busy,
                minLines: 3,
                maxLines: 16,
                maxLength: widget.kind == 'chats'
                    ? 300
                    : widget.kind == 'events'
                    ? 10000
                    : 30000,
                decoration: const InputDecoration(labelText: 'Текст'),
              ),
              if (widget.kind == 'chats') ...[
                _choices('Тип чата', _chatKind, {
                  'group': 'Общий чат',
                  'channel': 'Канал',
                }, (v) => _chatKind = v),
                if (widget.scope.youth != null)
                  _choices('Доступ', _access, {
                    'parish': 'Вся молодёжка',
                    'active': 'Актив и руководители',
                  }, (v) => _access = v),
                if (widget.row?['access'] == 'restricted')
                  const Text('Доступ по приглашениям сохранится.'),
                TextFormField(
                  controller: _sort,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Порядок в списке',
                    helperText: 'Меньшее число — выше в списке',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 0 || n > 10000
                        ? 'Укажите число от 0 до 10000'
                        : null;
                  },
                ),
                SwitchListTile.adaptive(
                  title: const Text('Архивировать чат'),
                  value: _archived,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _archived = v),
                ),
              ] else ...[
                _choices('Видимость', _visibility, {
                  'parish': widget.scope.youth == null
                      ? 'Участники прихода'
                      : 'Участники молодёжки',
                  'public': 'Все, включая гостей',
                }, (v) => _visibility = v),
                _choices('Состояние', _status, {
                  'draft': 'Черновик',
                  'published': 'Опубликовано',
                  if (widget.kind == 'events') 'cancelled': 'Отменено',
                  if (mayDelete(rights, widget.kind)) 'archived': 'В архиве',
                }, (v) => _status = v),
              ],
              if (widget.kind == 'events') ...[
                CommunityTile(
                  title: 'Начало',
                  subtitle: '${_start.toLocal()}'.substring(0, 16),
                  icon: Icons.event,
                  onTap: _busy ? null : () => _date(true),
                ),
                CommunityTile(
                  title: 'Окончание',
                  subtitle: '${_end.toLocal()}'.substring(0, 16),
                  icon: Icons.event_available,
                  onTap: _busy ? null : () => _date(false),
                ),
                TextField(
                  controller: _location,
                  enabled: !_busy,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Место встречи'),
                ),
                EventMapField(
                  value: _mapValue,
                  readOnly: _busy,
                  onChanged: (value) => setState(() => _mapValue = value),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
              ),
              if (widget.row != null &&
                  widget.kind != 'chats' &&
                  mayDelete(rights, widget.kind))
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: const Text('Удалить'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class GlobalSettingsPage extends ConsumerStatefulWidget {
  const GlobalSettingsPage({super.key});
  @override
  ConsumerState<GlobalSettingsPage> createState() => _GlobalSettingsPageState();
}

class _GlobalSettingsPageState extends ConsumerState<GlobalSettingsPage> {
  final _name = TextEditingController(),
      _welcome = TextEditingController(),
      _email = TextEditingController();
  bool _busy = false;
  int? _revision;
  String? _error;
  late String? _actor;
  @override
  void initState() {
    super.initState();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref.read(communityRepositoryProvider).configuration();
      if (!mounted) return;
      setState(() {
        _name.text = appDisplayName(r['app_name']);
        _welcome.text = r['welcome_text'] as String;
        _email.text = r['support_email'] as String;
        _revision = (r['revision'] as num).toInt();
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _welcome.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        _revision == null ||
        _actor != ref.read(authUserProvider).asData?.value?.id)
      return;
    setState(() => _busy = true);
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('save_app_configuration', {
            'p_name': _name.text,
            'p_welcome': _welcome.text,
            'p_email': _email.text,
            'p_revision': _revision,
          });
      ref.invalidate(appConfigurationProvider);
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Настройки приложения',
    children: [
      if (_revision == null && _error == null) const LinearProgressIndicator(),
      TextField(
        controller: _name,
        enabled: !_busy && _revision != null,
        maxLength: 80,
        decoration: const InputDecoration(labelText: 'Название приложения'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _welcome,
        enabled: !_busy && _revision != null,
        maxLength: 500,
        minLines: 2,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Приветствие'),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        enabled: !_busy && _revision != null,
        maxLength: 254,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Email поддержки'),
      ),
      if (_error != null) Text(_error!),
      FilledButton(
        onPressed: _busy || _revision == null ? null : _save,
        child: const Text('Сохранить'),
      ),
      TextButton(
        onPressed: _busy ? null : _load,
        child: const Text('Загрузить сохранённое'),
      ),
    ],
  );
}
