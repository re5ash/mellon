import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../parishes/application/parish_providers.dart';
import '../application/membership_providers.dart';
import '../domain/membership.dart';
import 'parish_dashboard.dart';

class MyParishPage extends ConsumerWidget {
  const MyParishPage({super.key});
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => AsyncContent<Membership?>(
    value: ref.watch(currentMembershipProvider),
    onRetry: () => ref.invalidate(currentMembershipProvider),
    builder: (membership) {
      if (membership == null)
        return SingleChildScrollView(
          child: ContentFrame(
            maxWidth: AppLayout.formMaxWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.church_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  'Выберите свой приход',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpace.md),
                const Text(
                  'Найдите приход, к которому хотите присоединиться. Вместе — новости, встречи и добрые дела.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpace.lg),
                FilledButton(
                  onPressed: () => context.go('/parishes'),
                  child: const Text('Найти свой приход'),
                ),
              ],
            ),
          ),
        );
      if (!membership.isActive)
        return PendingParishPage(parishId: membership.parishId);
      return AsyncContent(
        value: ref.watch(parishProvider(membership.parishId)),
        onRetry: () => ref.invalidate(parishProvider(membership.parishId)),
        builder: (parish) =>
            ParishDashboard(key: ValueKey(parish.id), parish: parish),
      );
    },
  );
}

class PendingParishPage extends ConsumerWidget {
  const PendingParishPage({required this.parishId, super.key});
  final String parishId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    child: ContentFrame(
      maxWidth: AppLayout.formMaxWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Заявка отправлена',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.md),
          const Text(
            'После одобрения администратором вы получите доступ к материалам и чатам своего прихода.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Chip(label: Text('На рассмотрении')),
                  AsyncContent(
                    value: ref.watch(parishProvider(parishId)),
                    onRetry: () => ref.invalidate(parishProvider(parishId)),
                    builder: (parish) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          parish.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (parish.address.isNotEmpty) Text(parish.address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: () => ref.invalidate(currentMembershipProvider),
            child: const Text('Проверить статус'),
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton(
            onPressed: () => context.go('/feed'),
            child: const Text('Смотреть общую ленту'),
          ),
          TextButton(
            onPressed: () => context.go('/map'),
            child: const Text('Смотреть карту'),
          ),
          TextButton(
            onPressed: () => context.go('/profile'),
            child: const Text('Настройки и отмена заявки'),
          ),
        ],
      ),
    ),
  );
}
