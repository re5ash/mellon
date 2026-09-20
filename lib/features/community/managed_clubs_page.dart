import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import '../auth/data/club_registration_repository.dart';
import 'club_directory_repository.dart';
import 'community_repository.dart';
import 'community_widgets.dart';
import 'registration_intake_card.dart';

class ManagedYouthPage extends ConsumerWidget {
  const ManagedYouthPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommunityScaffold(
    title: 'Молодёжные клубы',
    children: [
      AsyncContent<AccountAccess>(
        value: ref.watch(accountAccessProvider),
        onRetry: () => ref.read(accountAccessRefreshProvider).value++,
        builder: (access) => !access.superAdmin || access.restrictedGuest
            ? const CommunityTile(
                title: 'Доступ только для суперадмина',
                icon: Icons.lock_outline,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Молодёжные клубы',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text('Создание клубов, описание и архив.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('create-youth-club'),
                    onPressed: () =>
                        openCommunity(context, const YouthEditor()),
                    icon: const Icon(Icons.add),
                    label: const Text('Создать клуб'),
                  ),
                  const SizedBox(height: 16),
                  AsyncContent<List<JsonRow>>(
                    value: ref.watch(managedClubsProvider),
                    preserveOnRefresh: true,
                    onRetry: () => ref.invalidate(managedClubsProvider),
                    builder: (clubs) => Column(
                      children: [
                        RegistrationIntakeCard(clubs: clubs),
                        const SizedBox(height: 16),
                        if (clubs.isEmpty)
                          const CommunityTile(
                            title: 'Клубов пока нет',
                            icon: Icons.groups_outlined,
                          ),
                        for (final club in clubs)
                          CommunityTile(
                            title: club['name'] as String,
                            icon: Icons.groups_rounded,
                            subtitle: club['is_archived'] == true
                                ? 'В архиве'
                                : club['description'] as String,
                            onTap: () =>
                                openCommunity(context, YouthEditor(row: club)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    ],
  );
}

class YouthEditor extends ConsumerStatefulWidget {
  const YouthEditor({this.row, super.key});
  final JsonRow? row;
  @override
  ConsumerState<YouthEditor> createState() => _YouthEditorState();
}

class _YouthEditorState extends ConsumerState<YouthEditor> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _description = TextEditingController();
  late final String _id;
  late final String? _actor;
  String? _city, _error;
  bool _archived = false, _busy = false;
  @override
  void initState() {
    super.initState();
    _id = widget.row?['id'] as String? ?? newUuid();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _name.text = widget.row?['name'] as String? ?? '';
    _description.text = widget.row?['description'] as String? ?? '';
    _archived = widget.row?['is_archived'] == true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        _actor == null ||
        _actor != ref.read(authUserProvider).asData?.value?.id ||
        ref.read(accountAccessProvider).asData?.value.superAdmin != true ||
        !_form.currentState!.validate())
      return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(communityRepositoryProvider).call('save_youth_club', {
        'p_id': _id,
        'p_city': _city,
        'p_name': _name.text.trim(),
        'p_description': _description.text.trim(),
        'p_archived': _archived,
        'p_revision': widget.row?['revision'] ?? 0,
        'p_expected_user': _actor,
      });
      if (!mounted || _actor != ref.read(authUserProvider).asData?.value?.id)
        return;
      ref.invalidate(managedClubsProvider);
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(clubWorkspacesProvider);
      ref.invalidate(clubChoicesProvider);
      ref.invalidate(myYouthProvider);
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accountAccessProvider);
    return CommunityScaffold(
      title: widget.row == null ? 'Новый клуб' : 'Настройки клуба',
      children: [
        AsyncContent<AccountAccess>(
          value: access,
          onRetry: () => ref.read(accountAccessRefreshProvider).value++,
          builder: (value) => !value.superAdmin || value.restrictedGuest
              ? const CommunityTile(
                  title: 'Доступ только для суперадмина',
                  icon: Icons.lock_outline,
                )
              : Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.row == null)
                        AsyncContent<List<JsonRow>>(
                          value: ref.watch(clubCitiesProvider),
                          onRetry: () => ref.invalidate(clubCitiesProvider),
                          builder: (cities) => DropdownButtonFormField<String>(
                            key: const ValueKey('club-city'),
                            initialValue: _city,
                            isExpanded: true,
                            itemHeight: null,
                            decoration: const InputDecoration(
                              labelText: 'Город',
                            ),
                            items: [
                              for (final city in cities)
                                DropdownMenuItem(
                                  value: city['id'] as String,
                                  child: Text(city['name'] as String),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _city = value),
                            validator: (value) =>
                                value == null ? 'Выберите город' : null,
                          ),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _name,
                        enabled: !_busy,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Название клуба',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Укажите название'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _description,
                        enabled: !_busy,
                        minLines: 3,
                        maxLines: 12,
                        maxLength: 5000,
                        decoration: const InputDecoration(labelText: 'О клубе'),
                      ),
                      SwitchListTile.adaptive(
                        title: const Text('В архиве'),
                        subtitle: const Text(
                          'Архивный клуб недоступен для новых заявок и общения.',
                        ),
                        value: _archived,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _archived = value),
                      ),
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
