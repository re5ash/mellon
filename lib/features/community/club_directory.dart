import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import 'club_applications_page.dart';
import 'club_dashboard.dart';
import 'club_directory_repository.dart';
import 'club_selection_store.dart';
import 'community_pages.dart';
import 'community_repository.dart';
import 'community_widgets.dart';

class ClubDirectory extends ConsumerStatefulWidget {
  const ClubDirectory({
    this.newsOnly = false,
    this.forceSelection = false,
    super.key,
  });
  final bool newsOnly, forceSelection;
  @override
  ConsumerState<ClubDirectory> createState() => _ClubDirectoryState();
}

class _ClubDirectoryState extends ConsumerState<ClubDirectory> {
  final _search = TextEditingController();
  String? _selected, _busy, _error;
  final _receipts = <String, String>{};
  final _pending = <String>{};
  final _left = <String>{};
  String? _scheduledSelection;

  void _select(String id, String actor) {
    if (!mounted || ref.read(authUserProvider).asData?.value?.id != actor)
      return;
    setState(() => _selected = id);
    unawaited(_remember(actor, id));
  }

  Future<void> _remember(String actor, String id) async {
    try {
      final store = ref.read(clubSelectionStoreProvider);
      await store.save(actor, id).timeout(const Duration(seconds: 2));
      if (mounted && ref.read(authUserProvider).asData?.value?.id == actor)
        ref.invalidate(savedClubSelectionProvider(actor));
    } on Object {
      // Keep the in-session choice if local persistence is unavailable.
    }
  }

  void _afterLeave(String id) {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    setState(() {
      _selected = id;
      _left.add(id);
      _pending.remove(id);
      _receipts.remove(id);
      _error = null;
    });
    unawaited(_confirmLeft(id, actor));
  }

  Future<void> _confirmLeft(String id, String actor) async {
    try {
      await ref
          .read(clubDirectoryProvider.future)
          .timeout(const Duration(seconds: 20));
      if (mounted && ref.read(authUserProvider).asData?.value?.id == actor)
        setState(() => _left.remove(id));
    } on Object catch (error) {
      if (mounted && ref.read(authUserProvider).asData?.value?.id == actor)
        setState(() => _error = userError(error));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _join(JsonRow club) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (_busy != null || actor == null) return;
    final id = club['id'] as String;
    setState(() {
      _busy = id;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('request_youth_club', {
            'p_youth': id,
            'p_receipt': _receipts.putIfAbsent(id, newUuid),
            'p_expected_user': actor,
          })
          .timeout(const Duration(seconds: 20));
      if (!mounted || actor != ref.read(authUserProvider).asData?.value?.id)
        return;
      setState(() {
        _pending.add(id);
        _left.remove(id);
      });
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(clubEntryProvider(id));
      ref.invalidate(myClubApplicationsProvider);
    } on Object catch (error) {
      if (mounted && actor == ref.read(authUserProvider).asData?.value?.id)
        setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _application(JsonRow club) {
    final id = club['id'] as String;
    final status = club['request_status'] as String?;
    return ClubIdentity(
      club: club,
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (status == 'pending' || status == null && _pending.contains(id))
            const CommunityTile(
              title: 'Заявка отправлена',
              subtitle:
                  'Статус: на рассмотрении. После одобрения откроются чаты и разделы клуба.',
              icon: Icons.schedule_rounded,
            )
          else if (status == 'rejected')
            const CommunityTile(
              title: 'Заявка отклонена',
              subtitle: 'Свяжитесь с руководителем клуба для уточнения.',
              icon: Icons.info_outline,
            )
          else
            FilledButton(
              key: ValueKey('join-club-$id'),
              onPressed: _busy == null ? () => _join(club) : null,
              child: Text(_busy == id ? 'Отправляем…' : 'Подать заявку'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(
      authUserProvider.select((value) => value.asData?.value?.id),
    );
    final saved = actor == null
        ? null
        : ref.watch(savedClubSelectionProvider(actor));
    return AsyncContent<List<JsonRow>>(
      value: ref.watch(clubDirectoryProvider),
      preserveOnRefresh: true,
      onRetry: () => ref.invalidate(clubDirectoryProvider),
      builder: (clubs) {
        final accessible = clubs.where((g) => g['can_open'] == true).toList();
        final preferred = [_selected, saved?.asData?.value]
            .whereType<String>()
            .where((id) => clubs.any((club) => club['id'] == id))
            .firstOrNull;
        if (preferred == null && clubs.length > 1 && saved?.isLoading == true)
          return const Center(child: CircularProgressIndicator());
        final selectedId =
            preferred ??
            (clubs.length == 1
                ? clubs.single['id'] as String
                : !widget.newsOnly && accessible.length == 1
                ? accessible.single['id'] as String
                : null);
        final selected = clubs.where((g) => g['id'] == selectedId).firstOrNull;
        if (selected != null) {
          final id = selected['id'] as String;
          if (actor != null && _selected != id && _scheduledSelection != id) {
            _scheduledSelection = id;
            final previousSelection = _selected;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selected == previousSelection) _select(id, actor);
            });
          }
          final status = selected['request_status'];
          if (status == 'rejected' || status == 'accepted') {
            _pending.remove(id);
            _receipts.remove(id);
          }
          if (selected['can_open'] == true && !_left.contains(id)) {
            _pending.remove(id);
            if (widget.newsOnly)
              return YouthDetail(
                key: ValueKey(id),
                group: selected,
                newsOnly: true,
              );
            return ClubDashboard(
              key: ValueKey(id),
              club: id,
              onChooseClub: () => _afterLeave(id),
            );
          }
          return AsyncContent<JsonRow>(
            value: ref.watch(clubEntryProvider(id)),
            preserveOnRefresh: true,
            onRetry: () => ref.invalidate(clubEntryProvider(id)),
            builder: (entry) => _application({
              ...entry,
              'request_status': _left.contains(id)
                  ? null
                  : selected['request_status'],
            }),
          );
        }
        final query = _search.text.trim().toLowerCase();
        final visible = clubs.where(
          (club) => '${club['name']} ${club['city_name'] ?? ''}'
              .toLowerCase()
              .contains(query),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Выберите молодёжный клуб',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('club-directory-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Поиск клуба',
              ),
            ),
            const SizedBox(height: 16),
            if (visible.isEmpty)
              CommunityTile(
                title: clubs.isEmpty ? 'Клубов пока нет' : 'Клуб не найден',
                icon: Icons.groups_outlined,
              ),
            for (final club in visible)
              CommunityTile(
                title: club['name'] as String,
                subtitle: club['description'] as String?,
                icon: Icons.groups_rounded,
                onTap: actor == null
                    ? null
                    : () => _select(club['id'] as String, actor),
                trailing: const Icon(Icons.chevron_right),
              ),
          ],
        );
      },
    );
  }
}
