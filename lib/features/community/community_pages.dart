import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../../core/errors/app_failure.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import '../auth/presentation/club_registration_dialog.dart';
import '../chats/presentation/chat_page.dart';
import '../chats/presentation/chat_route.dart';
import 'club_applications_page.dart';
import 'club_directory.dart';
import 'club_live_updates.dart';
import 'community_repository.dart';
import 'community_widgets.dart';
import 'content_pages.dart';
import 'managed_clubs_page.dart';
import 'role_manager_dialog.dart';
import 'role_pages.dart';

class MyYouthPage extends ConsumerWidget {
  const MyYouthPage({
    this.embedded = false,
    this.newsOnly = false,
    this.forceSelection = false,
    super.key,
  });
  final bool embedded, newsOnly, forceSelection;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authUserProvider);
    final access = ref.watch(accountAccessProvider);
    return CommunityScaffold(
      title: 'Молодёжные клубы',
      maxWidth: 1200,
      embedded: embedded,
      clubBackground: !newsOnly,
      protectSession: false,
      children: [
        if (auth.isLoading)
          const LinearProgressIndicator()
        else if (auth.asData?.value == null) ...[
          const CommunityTile(
            title: 'Молодёжный клуб',
            icon: Icons.groups_rounded,
            subtitle: 'Войдите или зарегистрируйтесь, чтобы выбрать клуб и подать заявку.',
          ),
          FilledButton(
            onPressed: () => openClubRegistration(context),
            child: const Text('Присоединиться'),
          ),
        ] else
          AsyncContent<AccountAccess>(
            value: access,
            onRetry: () => ref.read(accountAccessRefreshProvider).value++,
            builder: (value) => value.restrictedGuest
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CommunityTile(
                        title: 'Молодёжный клуб',
                        icon: Icons.groups_rounded,
                        subtitle: 'Посмотрите статус заявки и доступ к клубу.',
                      ),
                      FilledButton(
                        onPressed: () =>
                            openClubRegistration(context, reviewOnly: true),
                        child: const Text('Статус заявки'),
                      ),
                    ],
                  )
                : ClubLiveScope(
                    child: ClubDirectory(
                      key: ValueKey(auth.asData!.value!.id),
                      newsOnly: newsOnly,
                      forceSelection: forceSelection,
                    ),
                  ),
          ),
      ],
    );
  }
}

class YouthDetail extends ConsumerWidget {
  const YouthDetail({required this.group, this.newsOnly = false, super.key});
  final bool newsOnly;
  final JsonRow group;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = (
      parish: group['parish_id'] as String?,
      youth: group['id'] as String?,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          group['name'] as String,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if ((group['description'] as String).isNotEmpty)
          Text(group['description'] as String),
        YouthContent(scope: s, initialKind: newsOnly ? 'posts' : 'chat_rooms'),
      ],
    );
  }
}

class YouthContent extends ConsumerStatefulWidget {
  const YouthContent({
    required this.scope,
    this.initialKind = 'chat_rooms',
    super.key,
  });
  final String initialKind;
  final CommunityScope scope;
  @override
  ConsumerState<YouthContent> createState() => _YouthContentState();
}

class _YouthContentState extends ConsumerState<YouthContent> {
  late String _kind;
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  String? _after;
  final List<String?> _history = [];
  late Future<List<JsonRow>> _data;
  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _load();
  }

  void _load() {
    final c = ref.read(communityRepositoryProvider).client;
    var q = c.from(_kind).select().eq('youth_id', widget.scope.youth!);
    if (_kind == 'chat_rooms')
      q = q.eq('is_archived', false);
    else if (_kind == 'posts')
      q = q.eq('status', 'published');
    else
      q = q
          .inFilter('status', ['published', 'cancelled'])
          .gte('ends_at', _day.toUtc().toIso8601String())
          .lt(
            'starts_at',
            DateTime(
              _day.year,
              _day.month,
              _day.day + 1,
            ).toUtc().toIso8601String(),
          );
    if (_after != null) q = q.gt('id', _after!);
    _data = q.order('id').limit(31);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final k in ['chat_rooms', 'posts', 'events'])
            ChoiceChip(
              label: Text(
                k == 'chat_rooms'
                    ? 'Чаты'
                    : k == 'posts'
                    ? 'Новости'
                    : 'Календарь',
              ),
              selected: _kind == k,
              onSelected: (_) => setState(() {
                _kind = k;
                _after = null;
                _history.clear();
                _load();
              }),
            ),
        ],
      ),
      if (_kind == 'events')
        Card(
          child: CalendarDatePicker(
            initialDate: _day,
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
            onDateChanged: (value) => setState(() {
              _day = value;
              _after = null;
              _history.clear();
              _load();
            }),
          ),
        ),
      const SizedBox(height: 12),
      FutureBuilder<List<JsonRow>>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(userError(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          final rows = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Пока ничего нет.'),
                ),
              for (final row in rows.take(30))
                CommunityTile(
                  title: row['title'] as String,
                  icon: _kind == 'chat_rooms'
                      ? Icons.forum_outlined
                      : _kind == 'posts'
                      ? Icons.article_outlined
                      : Icons.event_outlined,
                  subtitle: _kind == 'events'
                      ? '${DateTime.parse(row['starts_at'] as String).toLocal()}\n${row['location_label'] ?? ''}\n${row['description']}'
                      : _kind == 'posts'
                      ? row['body'] as String
                      : row['description'] as String?,
                  onTap: _kind == 'chat_rooms'
                      ? () => Navigator.of(context, rootNavigator: true)
                            .push<void>(
                              MellonChatRoute(
                                reducedMotion: MediaQuery.disableAnimationsOf(
                                  context,
                                ),
                                builder: (_) =>
                                    ChatPage(roomId: row['id'] as String),
                              ),
                            )
                      : null,
                ),
              Wrap(
                spacing: 12,
                children: [
                  if (_history.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(() {
                        _after = _history.removeLast();
                        _load();
                      }),
                      child: const Text('Назад'),
                    ),
                  if (rows.length > 30)
                    TextButton(
                      onPressed: () => setState(() {
                        _history.add(_after);
                        _after = rows[29]['id'] as String;
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

class ScopeHome extends ConsumerWidget {
  const ScopeHome({required this.scope, required this.title, super.key});
  final CommunityScope scope;
  final String title;
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommunityScaffold(
    title: title,
    children: [
      AsyncContent<Set<String>>(
        value: ref.watch(scopePermissionsProvider(scope)),
        onRetry: () => ref.invalidate(scopePermissionsProvider(scope)),
        builder: (rights) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (scope.youth != null && rights.contains('youth.requests.review'))
              CommunityTile(
                title: 'Заявки в клуб',
                icon: Icons.mark_email_unread_outlined,
                onTap: () => openCommunity(
                  context,
                  ClubApplicationsPage(youth: scope.youth!),
                ),
              ),
            const RolesEntry(),
            if (scope.parish == null && rights.contains('settings.manage'))
              CommunityTile(
                title: 'Настройки приложения',
                icon: Icons.settings_outlined,
                onTap: () => openCommunity(context, const GlobalSettingsPage()),
              ),
            if (scope.parish != null &&
                (rights.contains('roles.assign') ||
                    rights.contains('youth.members.manage') ||
                    rights.contains('youth.roles.manage')))
              CommunityTile(
                title: 'Участники и актив',
                icon: Icons.people_outline,
                onTap: () =>
                    openCommunity(context, ScopeMembersPage(scope: scope)),
              ),
            if (scope.parish != null)
              for (final kind in ['posts', 'chats', 'events'])
                if (mayEdit(rights, kind) || mayCreate(rights, kind))
                  CommunityTile(
                    title: contentLabel(kind),
                    icon: kind == 'events'
                        ? Icons.calendar_month
                        : kind == 'chats'
                        ? Icons.forum_outlined
                        : Icons.article_outlined,
                    onTap: () => openCommunity(
                      context,
                      ScopeContentPage(scope: scope, kind: kind),
                    ),
                  ),
            if (scope.parish == null &&
                ref.watch(accountAccessProvider).asData?.value.superAdmin ==
                    true)
              CommunityTile(
                title: 'Молодёжные клубы',
                icon: Icons.groups_rounded,
                onTap: () => openCommunity(context, const ManagedYouthPage()),
              ),
          ],
        ),
      ),
    ],
  );
}
