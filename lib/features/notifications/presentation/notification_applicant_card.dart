import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_access.dart';
import '../../../core/errors/app_failure.dart';
import '../../auth/application/auth_providers.dart';
import '../../community/role_manager_dialog.dart';
import '../application/notification_applicant_providers.dart';
import '../application/notification_providers.dart';
import '../domain/app_notification.dart';
import '../domain/notification_applicant.dart';

class NotificationApplicantCard extends ConsumerStatefulWidget {
  const NotificationApplicantCard({required this.notification, super.key});
  final AppNotification notification;
  @override
  ConsumerState<NotificationApplicantCard> createState() =>
      _NotificationApplicantCardState();
}

class _NotificationApplicantCardState
    extends ConsumerState<NotificationApplicantCard> {
  bool _busy = false;
  String? _error;

  Future<void> _open({required bool roles}) async {
    if (_busy) return;
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    final key = (actor: actor, notification: widget.notification.id);
    bool sameAccount() =>
        mounted && ref.read(authUserProvider).asData?.value?.id == actor;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Recheck the person and scope before opening the editor or application.
      final applicant = await ref
          .read(notificationApplicantRepositoryProvider)
          .getApplicant(widget.notification.id);
      if (!mounted || ref.read(authUserProvider).asData?.value?.id != actor)
        return;
      if (applicant == null || (roles && !applicant.canManageRoles)) {
        ref.invalidate(notificationApplicantProvider(key));
        throw const AppFailure(
          'Данные пользователя или управление правами больше недоступны.',
        );
      }
      if (applicant.notificationId != widget.notification.id ||
          (widget.notification.subjectUserId != null &&
              applicant.userId != widget.notification.subjectUserId)) {
        throw const AppFailure('Уведомление изменилось. Обновите карточку.');
      }
      await ref
          .read(notificationRepositoryProvider)
          .markRead(widget.notification.id);
      if (!mounted || ref.read(authUserProvider).asData?.value?.id != actor)
        return;
      if (roles) {
        await openRolesManager(context, userId: applicant.userId);
      } else if (applicant.clubId != null && applicant.requestId != null) {
        await context.push<void>(
          safeDestination(
            '/youth-requests/${applicant.clubId}?request=${applicant.requestId}',
          ),
        );
      } else {
        await context.push<void>('/admin/youth-clubs');
      }
      if (sameAccount()) ref.invalidate(notificationApplicantProvider(key));
    } on Object catch (error) {
      if (sameAccount()) setState(() => _error = userError(error));
    } finally {
      if (sameAccount()) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(authUserProvider).asData?.value?.id;
    if (actor == null) return const SizedBox.shrink();
    final provider = notificationApplicantProvider((
      actor: actor,
      notification: widget.notification.id,
    ));
    final value = ref.watch(provider);
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('notification-person-${widget.notification.id}'),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.primary.withValues(alpha: .14)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: value.when(
          skipLoadingOnReload: false,
          skipLoadingOnRefresh: false,
          loading: () => const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Загружаем данные пользователя…'),
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
          ),
          error: (error, stack) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(userError(error)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: const Text('Повторить'),
              ),
            ],
          ),
          data: (person) => person == null
              ? const Text('Данные пользователя сейчас недоступны.')
              : _content(context, person),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, NotificationApplicant person) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final heading = person.reviewStatus == null
        ? 'Заявка в молодёжный клуб'
        : 'Новый пользователь';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: colors.primary.withValues(alpha: .10),
              foregroundColor: colors.primary,
              child: Text(
                person.name.characters.firstOrNull?.toUpperCase() ?? '?',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    heading,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    person.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.notification.isRead)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 5),
                child: Icon(
                  Icons.circle,
                  size: 9,
                  color: colors.primary,
                  semanticLabel: 'Новое уведомление',
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              person.status,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _PersonField(
          icon: Icons.mail_outline_rounded,
          label: 'Email',
          value: person.email.isEmpty ? 'Не указан' : person.email,
        ),
        _PersonField(
          icon: Icons.cake_outlined,
          label: 'Дата рождения',
          value: person.birthDate == null
              ? 'Не указана'
              : _date(person.birthDate!),
        ),
        _PersonField(
          icon: Icons.phone_outlined,
          label: 'Телефон',
          value: person.phone.trim().isEmpty ? 'Не указан' : person.phone,
        ),
        if (person.registeredAt != null)
          _PersonField(
            icon: Icons.person_add_alt_1_outlined,
            label: 'Дата регистрации',
            value: _date(person.registeredAt!.toLocal()),
          ),
        _PersonField(
          icon: Icons.groups_outlined,
          label: 'Молодёжный клуб',
          value: person.clubName ?? 'Клуб для заявки пока не выбран',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (person.canManageRoles)
              FilledButton.icon(
                key: ValueKey('notification-roles-${widget.notification.id}'),
                onPressed: _busy ? null : () => _open(roles: true),
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Роли'),
              ),
            OutlinedButton.icon(
              key: ValueKey('notification-request-${widget.notification.id}'),
              onPressed: _busy ? null : () => _open(roles: false),
              icon: Icon(
                person.requestId == null
                    ? Icons.settings_outlined
                    : Icons.assignment_ind_outlined,
              ),
              label: Text(
                person.requestId == null
                    ? 'Настроить приём заявок'
                    : 'Открыть заявку',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';

class _PersonField extends StatelessWidget {
  const _PersonField({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 21,
            color: theme.colorScheme.primary.withValues(alpha: .8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
