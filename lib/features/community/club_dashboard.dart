import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../design_system/components/async_content.dart';
import '../../design_system/components/club_glass_surface.dart';
import '../../design_system/components/record_card.dart';
import '../../design_system/mellon_theme.dart';
import '../../design_system/parish_menu_theme.dart';
import '../auth/application/auth_providers.dart';
import '../chats/application/chat_providers.dart';
import '../chats/domain/chat.dart';
import '../chats/presentation/chat_dates.dart';
import '../chats/presentation/chat_icon_badge.dart';
import '../chats/presentation/chat_icon_picker.dart';
import '../chats/presentation/chat_page.dart';
import '../chats/presentation/chat_route.dart';
import '../events/application/events_providers.dart';
import '../feed/application/feed_providers.dart';
import '../feed/domain/publication_icon.dart';
import '../feed/presentation/publication_photo.dart';
import '../map/application/map_providers.dart';
import 'club_chat_editor.dart';
import 'club_chat_name_editor.dart';
import 'club_dashboard_repository.dart';
import 'club_directory_repository.dart';
import 'club_information_editor.dart';
import 'club_photo_cache.dart';
import 'club_photo_editor.dart';
import 'club_settings_dialog.dart';
import 'club_temple_address.dart';
import 'community_repository.dart';
import 'community_widgets.dart';
import 'stories/story_avatar.dart';

class ClubDashboard extends ConsumerStatefulWidget {
  const ClubDashboard({
    required this.club,
    required this.onChooseClub,
    super.key,
  });
  final String club;
  final VoidCallback onChooseClub;
  @override
  ConsumerState<ClubDashboard> createState() => _ClubDashboardState();
}

class _ClubDashboardState extends ConsumerState<ClubDashboard> {
  final _chatScroll = ScrollController();
  bool _chatOpen = false;
  final _chatWidgets =
      <String, ({JsonRow row, bool busy, bool manage, Widget widget})>{};
  JsonRow? _identityData;
  Widget? _identityWidget;

  Widget _stableIdentity(JsonRow club) {
    if (_identityWidget == null || !mapEquals(_identityData, club)) {
      _identityData = Map<String, dynamic>.of(club);
      _identityWidget = RepaintBoundary(
        child: ClubIdentity(
          club: club,
          storiesEnabled: true,
          onEditPhoto: club['can_edit_photo'] == true
              ? () => _photo(club)
              : null,
          onSettings: club['is_member'] == true ? _settings : null,
        ),
      );
    }
    return _identityWidget!;
  }

  Widget _stableChat(JsonRow room, bool canManage) {
    final id = room['id'] as String;
    final busy = _busy == id;
    final manage = canManage && _busy == null;
    final previous = _chatWidgets[id];
    if (previous != null &&
        previous.busy == busy &&
        previous.manage == manage &&
        mapEquals(previous.row, room)) {
      return previous.widget;
    }
    final child = RepaintBoundary(
      child: _ChatSpacing(
        child: _ChatRow(
          key: ValueKey('club-chat-$id'),
          room: room,
          busy: busy,
          onTap: () => _openChat(room),
          onManage: manage ? () => _menu(room) : null,
        ),
      ),
    );
    _chatWidgets[id] = (
      row: Map<String, dynamic>.of(room),
      busy: busy,
      manage: manage,
      widget: child,
    );
    return child;
  }

  int _tab = 0;
  String? _busy, _error;
  ({String actor, String club, ClubPhotoSaved photo})? _savedPhoto;
  @override
  void dispose() {
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _edit({JsonRow? room, int sort = 100}) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null || _busy != null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClubChatEditor(
        club: widget.club,
        actor: actor,
        room: room,
        sort: sort,
      ),
    );
    if (!mounted || actor != ref.read(authUserProvider).asData?.value?.id)
      return;
    if (saved == true) {
      ref.invalidate(clubDashboardProvider(widget.club));
      if (room != null) ref.invalidate(chatRoomProvider(room['id'] as String));
    }
  }

  Future<void> _delete(JsonRow room) async {
    if (_busy != null) return;
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    final confirmed = await confirmAction(
      context,
      'Удалить чат «${room['title']}»?',
      'Чат исчезнет из списка клуба, доступ к нему и его сообщениям будет закрыт для всех участников.',
    );
    if (!mounted ||
        !confirmed ||
        actor != ref.read(authUserProvider).asData?.value?.id)
      return;
    setState(() {
      _busy = room['id'] as String;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('delete_club_chat', {
            'p_youth': widget.club,
            'p_room': room['id'],
            'p_revision': room['revision'],
            'p_expected_user': actor,
          })
          .timeout(const Duration(seconds: 20));
      if (!mounted || actor != ref.read(authUserProvider).asData?.value?.id)
        return;
      ref.invalidate(clubDashboardProvider(widget.club));
      ref.invalidate(chatRoomProvider(room['id'] as String));
    } on Object catch (error) {
      if (mounted && actor == ref.read(authUserProvider).asData?.value?.id)
        setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openChat(JsonRow row) async {
    if (_chatOpen || ref.read(authUserProvider).asData?.value == null) return;
    _chatOpen = true;
    // A root route owns gestures and covers every shell bar. The list stays
    // mounted at the same scroll offset; no height or scroll restoration.
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        MellonChatRoute(
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          settings: RouteSettings(name: '/club-chat/${row['id']}'),
          builder: (_) => ChatPage(
            roomId: row['id'] as String,
            initialRoom: ChatRoom.fromJson(row),
          ),
        ),
      );
    } finally {
      _chatOpen = false;
    }
  }

  Future<void> _photo(JsonRow club) async {
    final targetClub = widget.club;
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null || club['can_edit_photo'] != true) return;
    final saved = await showDialog<ClubPhotoSaved>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClubPhotoEditor(
        club: targetClub,
        actor: actor,
        revision: (club['photo_revision'] as num?)?.toInt() ?? 0,
        path: club['photo_path'] as String?,
      ),
    );
    if (mounted &&
        widget.club == targetClub &&
        saved != null &&
        actor == ref.read(authUserProvider).asData?.value?.id) {
      setState(
        () => _savedPhoto = (actor: actor, club: targetClub, photo: saved),
      );
      ref.invalidate(clubDashboardProvider(widget.club));
      ref.invalidate(clubEntryProvider(widget.club));
    }
  }

  Future<void> _settings() async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    final left = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClubSettingsDialog(club: widget.club, actor: actor),
    );
    if (!mounted || actor != ref.read(authUserProvider).asData?.value?.id)
      return;
    if (left == true) {
      ref.invalidate(clubDashboardProvider(widget.club));
      ref.invalidate(clubEntryProvider(widget.club));
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(chatRoomProvider);
      ref.invalidate(chatMessagesProvider);
      widget.onChooseClub();
    }
  }

  Future<void> _information(String kind, {JsonRow? row}) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null ||
        ref
                .read(clubDashboardProvider(widget.club))
                .asData
                ?.value['can_manage_information'] !=
            true)
      return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClubInformationEditor(
        club: widget.club,
        actor: actor,
        kind: kind,
        row: row,
      ),
    );
    if (mounted &&
        saved == true &&
        actor == ref.read(authUserProvider).asData?.value?.id)
      ref.invalidate(clubDashboardProvider(widget.club));
  }

  Future<void> _removeInformation(String kind, JsonRow row) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null ||
        _busy != null ||
        ref
                .read(clubDashboardProvider(widget.club))
                .asData
                ?.value['can_manage_information'] !=
            true)
      return;
    if (!await confirmAction(
          context,
          'Удалить «${row['title']}»?',
          'Запись исчезнет из клуба и общей ленты, если была опубликована.',
        ) ||
        !mounted)
      return;
    if (actor != ref.read(authUserProvider).asData?.value?.id) return;
    setState(() {
      _busy = row['id'] as String;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('remove_club_information', {
            'p_youth': widget.club,
            'p_id': row['id'],
            'p_kind': kind,
            'p_expected': row['updated_at'],
            'p_expected_user': actor,
          })
          .timeout(const Duration(seconds: 20));
      if (mounted && actor == ref.read(authUserProvider).asData?.value?.id) {
        ref.invalidate(clubDashboardProvider(widget.club));
        ref.invalidate(feedPageProvider);
        ref.invalidate(eventsProvider);
        ref.invalidate(myParishEventsProvider);
        ref.invalidate(mapEventsProvider);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _rename(JsonRow room) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null || _busy != null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ClubChatNameEditor(club: widget.club, actor: actor, room: room),
    );
    if (!mounted ||
        ref.read(authUserProvider).asData?.value?.id != actor ||
        saved != true)
      return;
    ref.invalidate(clubDashboardProvider(widget.club));
    ref.invalidate(chatRoomProvider(room['id'] as String));
  }

  Future<void> _changeChatIcon(JsonRow room) async {
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null || _busy != null) return;
    final selected = await showChatIconPicker(
      context,
      selected: room['icon_key'] as String? ?? 'auto',
      title: room['title'] as String,
      description: room['description'] as String? ?? '',
      seed: room['id'] as String,
    );
    if (!mounted ||
        selected == null ||
        ref.read(authUserProvider).asData?.value?.id != actor)
      return;
    setState(() {
      _busy = room['id'] as String;
      _error = null;
    });
    try {
      await ref
          .read(communityRepositoryProvider)
          .call('edit_club_chat_meta', {
            'p_youth': widget.club,
            'p_room': room['id'],
            'p_title': null,
            'p_icon': selected,
            'p_revision': room['revision'],
            'p_expected_user': actor,
          })
          .timeout(const Duration(seconds: 20));
      if (mounted && ref.read(authUserProvider).asData?.value?.id == actor) {
        ref.invalidate(clubDashboardProvider(widget.club));
        ref.invalidate(chatRoomProvider(room['id'] as String));
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _menu(JsonRow room) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                room['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Переименовать'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Изменить иконку'),
              onTap: () => Navigator.pop(context, 'icon'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Удалить чат'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') await _rename(room);
    if (action == 'icon') await _changeChatIcon(room);
    if (action == 'delete') await _delete(room);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: ParishMenuTheme.from(Theme.of(context)),
    child: Builder(
      builder: (context) => AsyncContent<JsonRow>(
        value: ref.watch(clubDashboardProvider(widget.club)),
        preserveOnRefresh: true,
        onRetry: () => ref.invalidate(clubDashboardProvider(widget.club)),
        builder: (data) {
          final club = Map<String, dynamic>.from(
            data['club'] as Map<String, dynamic>,
          );
          final savedPhoto = _savedPhoto;
          if (savedPhoto != null &&
              savedPhoto.club == widget.club &&
              savedPhoto.actor ==
                  ref.read(authUserProvider).asData?.value?.id &&
              savedPhoto.photo.revision >
                  ((club['photo_revision'] as num?)?.toInt() ?? 0)) {
            club['photo_path'] = savedPhoto.photo.path;
            club['photo_revision'] = savedPhoto.photo.revision;
          }
          final chats = dashboardRows(data, 'chats');
          final chatIds = chats.map((r) => r['id']).toSet();
          _chatWidgets.removeWhere((id, _) => !chatIds.contains(id));
          final events = dashboardRows(data, 'events');
          final nearest = events
              .where(
                (row) =>
                    row['status'] == 'published' &&
                    (DateTime.tryParse(row['ends_at'] as String? ?? '')
                            ?.isAfter(DateTime.now()) ??
                        true),
              )
              .firstOrNull;
          final canManage = data['can_manage_chats'] == true;
          final canCreate = data['can_create_chats'] == true;
          final canInformation = data['can_manage_information'] == true;
          final kind = _tab == 1
              ? 'schedule'
              : _tab == 2
              ? 'events'
              : 'help';
          final rows = _tab == 3
              ? dashboardRows(data, 'help')
              : events
                    .where((row) => (row['club_section'] ?? 'events') == kind)
                    .toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stableIdentity(club),
              const SizedBox(height: 8),
              _Surface(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: nearest == null
                      ? null
                      : () => _detail(context, nearest, event: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        _NearestEventIcon(
                          startsAt: nearest?['starts_at'] as String?,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ближайшее событие',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                nearest?['title'] as String? ??
                                    'События пока не запланированы',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              if (nearest != null)
                                Text(
                                  _dateLabel(nearest['starts_at'] as String),
                                ),
                              if ((nearest?['location_label'] as String? ?? '')
                                  .isNotEmpty)
                                Text(nearest!['location_label'] as String),
                            ],
                          ),
                        ),
                        if (nearest != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ClubTabs(
                selected: _tab,
                onSelected: (value) => setState(() => _tab = value),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_tab == 0) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Чаты клуба',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (canCreate)
                      IconButton(
                        key: const ValueKey('add-club-chat'),
                        tooltip: 'Добавить чат',
                        onPressed: _busy == null
                            ? () => _edit(
                                sort:
                                    chats.fold<int>(
                                      0,
                                      (n, r) =>
                                          ((r['sort_order'] as num?)?.toInt() ??
                                                  0) >
                                              n
                                          ? (r['sort_order'] as num).toInt()
                                          : n,
                                    ) +
                                    1,
                              )
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                  ],
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 680;
                    final height = (MediaQuery.sizeOf(context).height * .65)
                        .clamp(320, 740)
                        .toDouble();
                    final list = wide
                        ? Scrollbar(
                            controller: _chatScroll,
                            child: ListView.builder(
                              key: const PageStorageKey('club-chat-list'),
                              controller: _chatScroll,
                              primary: false,
                              itemCount: chats.isEmpty ? 1 : chats.length,
                              itemBuilder: (context, index) => chats.isEmpty
                                  ? const _EmptyCard(text: 'Чатов пока нет')
                                  : _stableChat(chats[index], canManage),
                            ),
                          )
                        : Column(
                            key: const ValueKey('club-mobile-chat-list'),
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (chats.isEmpty)
                                const _EmptyCard(text: 'Чатов пока нет'),
                              for (final room in chats)
                                _stableChat(room, canManage),
                            ],
                          );
                    return ClubGlassSurface(
                      flat: !MellonThemeStyle.of(context).luminous,
                      radius: 22,
                      child: wide
                          ? SizedBox(height: height, child: list)
                          : list,
                    );
                  },
                ),
              ] else ...[
                _SectionTitle(
                  _tab == 1
                      ? 'Расписание'
                      : _tab == 2
                      ? 'События'
                      : 'Помощь',
                ),
                if (canInformation)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      key: ValueKey('add-club-$kind'),
                      onPressed: () => _information(kind),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(
                        _tab == 1
                            ? 'Добавить расписание'
                            : _tab == 2
                            ? 'Добавить событие'
                            : 'Добавить просьбу о помощи',
                      ),
                    ),
                  ),
                if (rows.isEmpty)
                  _EmptyCard(
                    text: _tab == 1
                        ? 'Расписание пока не добавлено'
                        : _tab == 2
                        ? 'События пока не запланированы'
                        : 'Сейчас нет открытых просьб о помощи',
                  ),
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    key: ValueKey('club-information-${row['id']}'),
                    child: _Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_tab == 3)
                            ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const Icon(
                                Icons.volunteer_activism,
                                color: ParishMenuTheme.pink,
                              ),
                              title: Text(row['title'] as String),
                              subtitle: Text(
                                row['description'] as String? ?? '',
                              ),
                              onTap: () => _detail(context, row),
                            )
                          else
                            _EventCard(row: row),
                          if (canInformation)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: _busy == null
                                        ? () => _information(kind, row: row)
                                        : null,
                                    icon: const Icon(Icons.edit_outlined),
                                    label: const Text('Редактировать'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _busy == null
                                        ? () => _removeInformation(kind, row)
                                        : null,
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Удалить'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class ClubIdentity extends StatelessWidget {
  const ClubIdentity({
    required this.club,
    this.onEditPhoto,
    this.onSettings,
    this.storiesEnabled = false,
    this.footer,
    super.key,
  });
  final JsonRow club;
  final Widget? footer;
  final bool storiesEnabled;
  final VoidCallback? onEditPhoto, onSettings;
  @override
  Widget build(BuildContext context) => ClubGlassSurface(
    flat: MellonThemeStyle.of(context).luminous,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final design = MellonThemeStyle.of(context);
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    club['name'] as String,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: design.enabled
                          ? FontWeight.w700
                          : FontWeight.w800,
                      fontSize: design.enabled
                          ? (design.luminous ? 19 : 17)
                          : null,
                      height: design.enabled ? 1.18 : null,
                    ),
                  ),
                  if (design.luminous && club['member_count'] is num)
                    Text(
                      "${club['member_count']} участников",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: design.enabled
                              ? const Size(0, 30)
                              : null,
                          padding: design.enabled
                              ? const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                )
                              : null,
                          visualDensity: design.enabled
                              ? VisualDensity.compact
                              : null,
                          backgroundColor: Theme.of(context).colorScheme.primary
                              .withValues(alpha: .07),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary
                                .withValues(alpha: .18),
                          ),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () => _detail(context, {
                          'title': club['temple_name'] ?? club['name'],
                          'description':
                              club['temple_description'] ?? club['description'],
                        }),
                        icon: const Icon(Icons.info_outline),
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('О храме'),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                      if (onSettings != null)
                        IconButton(
                          tooltip: 'Настройки клуба',
                          onPressed: onSettings,
                          icon: const Icon(Icons.settings_outlined),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClubTempleAddress(
                    parishId: club['parish_id'] as String?,
                    fallbackAddress: club['address'] as String? ?? '',
                  ),
                  if ((club['leaders'] as String? ?? '').isNotEmpty)
                    _MetaLine(
                      Icons.person_outline,
                      'Руководитель: ${club['leaders']}',
                    ),
                ],
              );
              if (constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(14) > 22)
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClubStoryAvatar(
                      club: club['id'] as String,
                      enabled: storiesEnabled,
                      halo: true,
                      path: club['photo_path'] as String?,
                      onEdit: onEditPhoto,
                    ),
                    const SizedBox(height: 14),
                    details,
                  ],
                );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: design.enabled
                        ? (design.luminous
                              ? 80
                              : design.classical
                              ? 92
                              : 108)
                        : constraints.maxWidth < 420
                        ? 112
                        : 152,
                    child: ClubStoryAvatar(
                      club: club['id'] as String,
                      enabled: storiesEnabled,
                      halo: true,
                      path: club['photo_path'] as String?,
                      onEdit: onEditPhoto,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(flex: 6, child: details),
                ],
              );
            },
          ),
          if (footer != null) ...[const SizedBox(height: 14), footer!],
        ],
      ),
    ),
  );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ClubTabs extends StatelessWidget {
  const _ClubTabs({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  static const tabs = [
    (label: 'Чаты', icon: Icons.chat_rounded, color: ParishMenuTheme.blue),
    (
      label: 'Расписание',
      icon: Icons.calendar_month_rounded,
      color: ParishMenuTheme.green,
    ),
    (
      label: 'События',
      icon: Icons.event_available_rounded,
      color: ParishMenuTheme.orange,
    ),
    (
      label: 'Помощь',
      icon: Icons.volunteer_activism,
      color: ParishMenuTheme.pink,
    ),
  ];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final design = MellonThemeStyle.of(context);
      if (design.enabled)
        return _ThemedClubTabs(selected: selected, onSelected: onSelected);
      final count =
          MediaQuery.textScalerOf(context).scale(14) > 21 || box.maxWidth < 280
          ? 2
          : 4;
      final width = (box.maxWidth - (count - 1) * 7) / count;
      final style = DefaultTextStyle.of(context).style.merge(
        Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontSize: 13, height: 1.2),
      );
      var labelHeight = 0.0;
      for (final tab in tabs) {
        final measure = TextPainter(
          text: TextSpan(text: tab.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: (width - 8).clamp(1.0, double.infinity).toDouble());
        if (measure.height > labelHeight) labelHeight = measure.height;
        measure.dispose();
      }
      return Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (var i = 0; i < tabs.length; i++)
            SizedBox(
              width: width,
              height: 32 + 6 + labelHeight.ceilToDouble() + 20,
              child: Semantics(
                selected: selected == i,
                button: true,
                child: ClubGlassSurface(
                  radius: 18,
                  selected: selected == i,
                  child: InkWell(
                    key: ValueKey('club-tab-$i'),
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(11),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color.lerp(tabs[i].color, Colors.white, .22)!,
                                  tabs[i].color,
                                ],
                              ),
                            ),
                            child: Icon(
                              tabs[i].icon,
                              color: Colors.white,
                              size: 23,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Expanded(
                            child: Center(
                              child: Text(
                                tabs[i].label,
                                textAlign: TextAlign.center,
                                style: style,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.room,
    required this.onTap,
    required this.busy,
    this.onManage,
    super.key,
  });
  final JsonRow room;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onManage;
  @override
  Widget build(BuildContext context) {
    final key = room['icon_key'] as String? ?? 'auto';
    final unread = (room['unread_count'] as num?)?.toInt() ?? 0;
    final time = _shortDate(room['last_message_at'] as String?);
    final style = Theme.of(context);
    final design = MellonThemeStyle.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        return ClubGlassSurface(
          flat: design.luminous,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: busy ? null : onTap,
            onLongPress: onManage,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: design.enabled ? 9 : 12,
                vertical: design.luminous
                    ? 12
                    : design.enabled
                    ? 5
                    : 9,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ChatIconBadge(
                    iconKey: key,
                    title: room['title'] as String,
                    description: room['description'] as String? ?? '',
                    seed: room['id'] as String,
                    size: design.luminous
                        ? 52
                        : design.enabled
                        ? 36
                        : 46,
                    unread: unread,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LayoutBuilder(
                          builder: (context, titleBox) => Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  room['title'] as String,
                                  style: style.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontFamily: design.enabled
                                        ? design.headingFamily
                                        : null,
                                    fontSize: design.enabled
                                        ? (design.luminous ? 16 : 14)
                                        : 16,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              if (time.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: titleBox.maxWidth * .42,
                                  ),
                                  child: Text(
                                    time,
                                    textAlign: TextAlign.right,
                                    style: style.textTheme.labelSmall?.copyWith(
                                      color: unread > 0
                                          ? style.colorScheme.primary
                                          : style.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          (room['last_message'] as String? ?? '').isNotEmpty
                              ? '${room['last_author'] ?? 'Участник'}: ${room['last_message']}'
                              : (room['description'] as String? ??
                                    'Сообщений пока нет'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style.textTheme.bodySmall?.copyWith(
                            color: style.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (busy) const Text('Сохраняем…'),
                      ],
                    ),
                  ),
                  if (unread > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Semantics(
                        label: 'Непрочитанных сообщений: $unread',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: style.colorScheme.primary,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            '$unread',
                            style: style.textTheme.labelMedium?.copyWith(
                              color: style.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onManage != null)
                    IconButton(
                      tooltip: 'Управление чатом «${room['title']}»',
                      onPressed: onManage,
                      icon: const Icon(Icons.more_vert, size: 20),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: style.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClubGlassSurface(child: child);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => _Surface(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.row});
  final JsonRow row;
  @override
  Widget build(BuildContext context) {
    final title = row['title'] as String;
    final body = row['description'] as String? ?? '';
    final icon =
        publicationIconById(row['icon_id'] as String?) ??
        suggestPublicationIcon(title, body, seed: row['id'] as String);
    final path = row['photo_path'] as String?;
    return RecordCard(
      key: ValueKey('club-publication-${row['id']}'),
      title: title,
      body: body,
      icon: icon.icon,
      category: row['status'] == 'cancelled'
          ? 'Отменено'
          : row['club_section'] == 'schedule'
          ? 'Расписание'
          : icon.group,
      date: DateTime.tryParse(row['starts_at'] as String? ?? ''),
      showTime: true,
      location: row['location_label'] as String?,
      photo: path == null ? null : PublicationPhoto(path: path),
    );
  }
}

String _dateLabel(String source, {bool time = true}) {
  final date = DateTime.parse(source).toLocal();
  const days = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  return '${days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}${time ? ', ${TimeOfDay.fromDateTime(date).hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}' : ''}';
}

String _shortDate(String? source) =>
    chatListTimestamp(source == null ? null : DateTime.tryParse(source));

Future<void> _detail(BuildContext context, JsonRow row, {bool event = false}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(row['title'] as String),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (event) ...[
              Text(_dateLabel(row['starts_at'] as String)),
              if ((row['location_label'] as String? ?? '').isNotEmpty)
                Text(row['location_label'] as String),
              const SizedBox(height: 12),
            ],
            Text(
              (row['description'] as String? ?? '').isEmpty
                  ? 'Описание пока не добавлено.'
                  : row['description'] as String,
            ),
            if (row['status'] == 'cancelled') const Text('Событие отменено'),
            if (row['status'] == 'fulfilled') const Text('Помощь оказана'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );

class _ChatSpacing extends StatelessWidget {
  const _ChatSpacing({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: design.luminous ? 0 : 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: design.luminous
              ? Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .08),
                  ),
                )
              : null,
        ),
        child: child,
      ),
    );
  }
}

class _NearestEventIcon extends StatelessWidget {
  const _NearestEventIcon({this.startsAt});
  final String? startsAt;
  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    final date = DateTime.tryParse(startsAt ?? '')?.toLocal();
    if (design.classical && date != null) {
      const days = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];
      const months = [
        'ЯНВ',
        'ФЕВ',
        'МАР',
        'АПР',
        'МАЙ',
        'ИЮН',
        'ИЮЛ',
        'АВГ',
        'СЕН',
        'ОКТ',
        'НОЯ',
        'ДЕК',
      ];
      return Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              days[date.weekday - 1],
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              '${date.day}',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 27),
            ),
            Text(
              months[date.month - 1],
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      );
    }
    if (design.enabled)
      return MellonFeatureIcon(
        icon: Icons.calendar_month_rounded,
        color: design.accent,
        size: 28,
      );
    return const ParishColorIcon(
      icon: Icons.calendar_month_outlined,
      color: ParishMenuTheme.blue,
      solid: true,
    );
  }
}

class _ThemedClubTabs extends StatelessWidget {
  const _ThemedClubTabs({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final design = MellonThemeStyle.of(context);
      final scaler = MediaQuery.textScalerOf(context);
      final count = scaler.scale(13) > 20 || box.maxWidth < 280 ? 2 : 4;
      final width = (box.maxWidth - (count - 1) * 6) / count;
      final horizontal =
          design.luminous && width >= 82 && scaler.scale(13) <= 16;
      final labelStyle = Theme.of(context).textTheme.labelMedium!.copyWith(
        fontSize: horizontal ? 11 : 12,
        height: 1.15,
        fontWeight: FontWeight.w500,
      );
      var textHeight = 0.0;
      for (final item in _ClubTabs.tabs) {
        final painter =
            TextPainter(
              text: TextSpan(text: item.label, style: labelStyle),
              textDirection: Directionality.of(context),
              textScaler: scaler,
            )..layout(
              maxWidth: (width - (horizontal ? 34 : 8))
                  .clamp(1.0, double.infinity)
                  .toDouble(),
            );
        if (painter.height > textHeight) textHeight = painter.height;
        painter.dispose();
      }
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < _ClubTabs.tabs.length; i++)
            SizedBox(
              width: width,
              height: horizontal
                  ? (textHeight + 16).clamp(44.0, double.infinity).toDouble()
                  : 40 + textHeight + 14,
              child: Semantics(
                button: true,
                selected: selected == i,
                child: ClubGlassSurface(
                  radius: design.luminous ? 18 : 15,
                  selected: selected == i,
                  child: InkWell(
                    key: ValueKey('club-tab-$i'),
                    borderRadius: BorderRadius.circular(15),
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: horizontal
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                MellonFeatureIcon(
                                  icon: _ClubTabs.tabs[i].icon,
                                  color: _color(design, i),
                                  size: 18,
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    _ClubTabs.tabs[i].label,
                                    style: labelStyle,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                MellonFeatureIcon(
                                  icon: _ClubTabs.tabs[i].icon,
                                  color: _color(design, i),
                                  size: 25,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _ClubTabs.tabs[i].label,
                                  style: labelStyle,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  Color _color(MellonThemeStyle design, int index) => design.luminous
      ? const [
          Color(0xff178cff),
          Color(0xffffa221),
          Color(0xffff564e),
          Color(0xfffa4c58),
        ][index]
      : const [
          Color(0xff167dff),
          Color(0xff00bcae),
          Color(0xffff7625),
          Color(0xfff52e97),
        ][index];
}
