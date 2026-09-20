import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import '../notifications/application/notification_providers.dart';
import 'community_repository.dart';
import 'community_widgets.dart';

final myClubApplicationsProvider = FutureProvider.autoDispose<List<JsonRow>>((
  ref,
) async {
  if (ref.watch(authUserProvider).asData?.value == null) return [];
  return ref.watch(communityRepositoryProvider).rows('my_club_applications');
}, retry: (_, error) => null);
final clubApplicationsProvider = FutureProvider.autoDispose
    .family<List<JsonRow>, String>((ref, youth) {
      ref.watch(authUserProvider);
      ref.listen(notificationsProvider, (_, next) {
        if (next.hasValue) ref.invalidateSelf();
      });
      return ref.watch(communityRepositoryProvider).rows(
        'youth_join_requests',
        {'p_youth': youth},
      );
    }, retry: (_, error) => null);

class MyClubApplicationStatus extends ConsumerWidget {
  const MyClubApplicationStatus({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => AsyncContent<List<JsonRow>>(
    value: ref.watch(myClubApplicationsProvider),
    onRetry: () => ref.invalidate(myClubApplicationsProvider),
    builder: (rows) => Column(
      children: [
        for (final row in rows.take(1))
          CommunityTile(
            title: row['youth_name'] as String,
            icon: Icons.mark_email_read_outlined,
            subtitle: switch (row['status']) {
              'accepted' =>
                'Заявка одобрена. Обновите раздел, чтобы открыть клуб.',
              'rejected' =>
                'Заявка отклонена. Свяжитесь с руководителем клуба для уточнения.',
              _ =>
                'Статус: на рассмотрении. После решения руководителя вы получите уведомление.',
            },
          ),
      ],
    ),
  );
}

class ClubApplicationsPage extends ConsumerStatefulWidget {
  const ClubApplicationsPage({required this.youth, this.requestId, super.key});
  final String youth;
  final String? requestId;
  @override
  ConsumerState<ClubApplicationsPage> createState() =>
      _ClubApplicationsPageState();
}

class _ClubApplicationsPageState extends ConsumerState<ClubApplicationsPage> {
  String? _busy;
  String? _error;
  Future<void> _review(JsonRow row, String decision) async {
    if (_busy != null) return;
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    setState(() {
      _busy = row['id'] as String;
      _error = null;
    });
    try {
      final accepted = decision == 'accepted';
      final confirmed = await confirmAction(
        context,
        accepted ? 'Принять участника?' : 'Отклонить заявку?',
        accepted
            ? 'Участник получит доступ к клубу и уведомление.'
            : 'Участник получит уведомление о решении.',
      );
      if (!mounted ||
          !confirmed ||
          ref.read(authUserProvider).asData?.value?.id != actor)
        return;
      await ref.read(communityRepositoryProvider).call(
        'review_youth_join_request',
        {
          'p_request': row['id'],
          'p_decision': decision,
          'p_expected_user': actor,
        },
      );
      if (!mounted) return;
      ref.invalidate(clubApplicationsProvider(widget.youth));
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Заявки в молодёжный клуб',
    actions: [
      IconButton(
        tooltip: 'Обновить',
        icon: const Icon(Icons.refresh),
        onPressed: () => ref.invalidate(clubApplicationsProvider(widget.youth)),
      ),
    ],
    children: [
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      AsyncContent<List<JsonRow>>(
        value: ref.watch(clubApplicationsProvider(widget.youth)),
        onRetry: () => ref.invalidate(clubApplicationsProvider(widget.youth)),
        builder: (rows) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rows.isEmpty)
              const CommunityTile(
                title: 'Новых заявок нет',
                icon: Icons.done_all,
              ),
            if (widget.requestId != null &&
                !rows.any((row) => row['id'] == widget.requestId))
              const CommunityTile(
                title: 'Эта заявка уже рассмотрена или недоступна',
                icon: Icons.task_alt,
              ),
            for (final row in [
              ...rows.where((row) => row['id'] == widget.requestId),
              ...rows.where((row) => row['id'] != widget.requestId),
            ])
              Card(
                key: ValueKey('application-${row['id']}'),
                color: row['id'] == widget.requestId
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        row['display_name'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      if (row['email_confirmed'] != true)
                        const Text('Ожидается подтверждение email участником.'),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed:
                                _busy != null || row['email_confirmed'] != true
                                ? null
                                : () => _review(row, 'accepted'),
                            child: const Text('Принять'),
                          ),
                          OutlinedButton(
                            onPressed:
                                _busy != null || row['email_confirmed'] != true
                                ? null
                                : () => _review(row, 'rejected'),
                            child: const Text('Отклонить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
