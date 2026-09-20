import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import '../notifications/application/notification_providers.dart';
import 'community_repository.dart';

final registrationIntakeProvider = FutureProvider.autoDispose<JsonRow>((
  ref,
) async {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  return Map<String, dynamic>.from(
    await ref
            .watch(communityRepositoryProvider)
            .call('registration_intake_settings')
        as Map<String, dynamic>,
  );
}, retry: (_, error) => null);

class RegistrationIntakeCard extends ConsumerStatefulWidget {
  const RegistrationIntakeCard({required this.clubs, super.key});
  final List<JsonRow> clubs;
  @override
  ConsumerState<RegistrationIntakeCard> createState() =>
      _RegistrationIntakeCardState();
}

class _RegistrationIntakeCardState
    extends ConsumerState<RegistrationIntakeCard> {
  bool _busy = false;
  String? _error;
  Future<void> _select(String? youth) async {
    if (_busy || youth == null) return;
    final actor = ref.read(authUserProvider).asData?.value?.id;
    if (actor == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(communityRepositoryProvider).call(
        'set_registration_intake',
        {'p_youth': youth, 'p_expected_user': actor},
      );
      if (!mounted || ref.read(authUserProvider).asData?.value?.id != actor)
        return;
      ref.invalidate(registrationIntakeProvider);
      ref.invalidate(notificationsProvider);
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncContent<JsonRow>(
    value: ref.watch(registrationIntakeProvider),
    onRetry: () => ref.invalidate(registrationIntakeProvider),
    preserveOnRefresh: true,
    builder: (settings) {
      final clubs = widget.clubs
          .where((row) => row['is_archived'] != true)
          .toList();
      final selected = settings['youth_id'] as String?;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Клуб для новых заявок',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'После подтверждения email новые заявки поступают сюда. Пользователю список клубов не показывается.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (clubs.isEmpty)
                const Text('Создайте клуб, чтобы направить заявки на проверку.')
              else
                DropdownButtonFormField<String>(
                  key: ValueKey(selected),
                  initialValue: clubs.any((row) => row['id'] == selected)
                      ? selected
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Молодёжный клуб',
                  ),
                  items: [
                    for (final club in clubs)
                      DropdownMenuItem(
                        value: club['id'] as String,
                        child: Text(club['name'] as String, softWrap: true),
                      ),
                  ],
                  onChanged: _busy ? null : _select,
                ),
              if ((settings['waiting_count'] as num? ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Ожидают назначения клуба: ${settings['waiting_count']}',
                  ),
                ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      );
    },
  );
}
