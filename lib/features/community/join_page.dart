import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/permission_providers.dart';
import '../../core/errors/app_failure.dart';
import '../../design_system/components/async_content.dart';
import '../auth/application/auth_providers.dart';
import '../membership/application/membership_providers.dart';
import '../profile/application/profile_providers.dart';
import '../profile/domain/user_profile.dart';
import '../profile/presentation/profile_form.dart';
import 'community_widgets.dart';

class JoinParishPage extends ConsumerStatefulWidget {
  const JoinParishPage({required this.parish, super.key});
  final String parish;
  @override
  ConsumerState<JoinParishPage> createState() => _JoinParishPageState();
}

class _JoinParishPageState extends ConsumerState<JoinParishPage> {
  bool _busy = false;
  String? _error;
  Future<void> _join(UserProfile p) async {
    if (_busy || ref.read(authUserProvider).asData?.value?.id != p.userId)
      return;
    setState(() => _busy = true);
    try {
      await ref.read(membershipRepositoryProvider).request(widget.parish);
      ref.invalidate(currentMembershipProvider);
      ref.invalidate(permissionsProvider);
      if (mounted) context.go('/my-parish');
    } on Object catch (e) {
      if (mounted) setState(() => _error = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Присоединиться',
    children: [
      const Text(
        'Перед вступлением заполните личные данные. Контакты и дата рождения не публикуются в ленте или чатах.',
      ),
      const SizedBox(height: 16),
      AsyncContent<UserProfile?>(
        value: ref.watch(ownProfileProvider),
        preserveOnRefresh: true,
        onRetry: () => ref.invalidate(ownProfileProvider),
        builder: (p) {
          if (p == null)
            return FilledButton(
              onPressed: () =>
                  context.push('/auth?from=/join/${widget.parish}'),
              child: const Text('Войти'),
            );
          final complete =
              p.givenName.isNotEmpty &&
              p.familyName.isNotEmpty &&
              p.birthDate != null &&
              p.phone.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ProfileForm(profile: p, key: ValueKey(p.userId)),
                ),
              ),
              const SizedBox(height: 16),
              if (!complete)
                const Text(
                  'Укажите и сохраните имя, фамилию, дату рождения и телефон.',
                ),
              if (_error != null) Text(_error!),
              FilledButton(
                onPressed: complete && !_busy ? () => _join(p) : null,
                child: Text(_busy ? 'Отправляем…' : 'Подать заявку'),
              ),
            ],
          );
        },
      ),
    ],
  );
}
