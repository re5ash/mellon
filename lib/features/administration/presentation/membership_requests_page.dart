import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/pagination/cursor_page.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/admin_providers.dart';
import '../domain/admin_models.dart';
import 'admin_components.dart';

class MembershipRequestsPage extends ConsumerWidget {
  const MembershipRequestsPage({required this.parishId, super.key});
  final String parishId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Заявки участников')),
    body: SafeArea(
      child: AsyncContent<AdminParish?>(
        value: ref.watch(managedParishProvider(parishId)),
        onRetry: () => ref.invalidate(managedParishProvider(parishId)),
        builder: (parish) =>
            parish != null && parish.allows('memberships.manage')
            ? MembershipRequestList(parishId: parishId, parishName: parish.name)
            : const EmptyState(
                title: 'Доступ ограничен',
                message: 'Нет права рассматривать заявки этого прихода.',
              ),
      ),
    ),
  );
}

class MembershipRequestList extends ConsumerStatefulWidget {
  const MembershipRequestList({
    required this.parishId,
    required this.parishName,
    super.key,
  });
  final String parishId, parishName;
  @override
  ConsumerState<MembershipRequestList> createState() =>
      _MembershipRequestListState();
}

class _MembershipRequestListState extends ConsumerState<MembershipRequestList> {
  final _history = <PageCursor?>[null];
  String? _busyId, _error;
  Future<void> _review(PendingMembership item, bool approve) async {
    if (_busyId != null) return;
    final repository = ref.read(adminRepositoryProvider);
    final refresh = ref.read(refreshAdminDataProvider);
    setState(() {
      _busyId = item.id;
      _error = null;
    });
    try {
      if (!approve) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Отклонить заявку?'),
            content: Text(item.displayName),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Отклонить'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await repository.review(item.id, approve: approve);
      refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Заявка одобрена' : 'Заявка отклонена'),
        ),
      );
    } on Object catch (error) {
      if (mounted)
        setState(() {
          _error = userError(error);
        });
    } finally {
      if (mounted)
        setState(() {
          _busyId = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _busyId == null,
    child: ContentFrame(
      child: ListView(
        children: [
          Text(
            widget.parishName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpace.sm),
          const Text('Ожидают решения администратора.'),
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busyId != null
                  ? null
                  : () {
                      setState(() {
                        _history
                          ..clear()
                          ..add(null);
                        _error = null;
                      });
                      ref.invalidate(pendingMembershipsProvider);
                      ref.invalidate(managedParishProvider(widget.parishId));
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('Обновить'),
            ),
          ),
          if (_error != null) AdminError(_error!),
          AsyncContent<CursorPage<PendingMembership>>(
            value: ref.watch(
              pendingMembershipsProvider((
                parishId: widget.parishId,
                before: _history.last,
              )),
            ),
            onRetry: () => ref.invalidate(pendingMembershipsProvider),
            builder: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
                    child: Text('Нет заявок на этой странице.'),
                  ),
                for (final item in page.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            item.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(item.requestedAt.toLocal()),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.sm,
                            children: [
                              FilledButton(
                                onPressed: _busyId == null
                                    ? () => _review(item, true)
                                    : null,
                                child: Text(
                                  _busyId == item.id
                                      ? 'Сохраняем…'
                                      : 'Одобрить',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _busyId == null
                                    ? () => _review(item, false)
                                    : null,
                                child: const Text('Отклонить'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                AdminPager(
                  page: _history.length,
                  previous: _busyId == null && _history.length > 1
                      ? () => setState(() {
                          _history.removeLast();
                        })
                      : null,
                  next: _busyId == null && page.next != null
                      ? () => setState(() {
                          _history.add(page.next);
                        })
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
