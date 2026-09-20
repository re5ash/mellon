import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../../membership/application/membership_providers.dart';
import '../../membership/domain/membership.dart';
import 'feed_page.dart';

class ParishNewsPage extends ConsumerWidget {
  const ParishNewsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    if (user == null) return const ParishNewsGate(signedIn: false);
    return AsyncContent<Membership?>(
      value: ref.watch(currentMembershipProvider),
      onRetry: () => ref.invalidate(currentMembershipProvider),
      builder: (membership) {
        if (membership == null || !membership.isActive)
          return const ParishNewsGate(signedIn: true);
        return FeedPage(
          key: ValueKey('${user.id}-${membership.parishId}'),
          parishId: membership.parishId,
        );
      },
    );
  }
}

class ParishNewsGate extends StatelessWidget {
  const ParishNewsGate({required this.signedIn, super.key});
  final bool signedIn;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: ContentFrame(
      maxWidth: AppLayout.formMaxWidth,
      child: Column(
        children: [
          const Icon(Icons.church_outlined, size: 48),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Новости вашего прихода',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            signedIn
                ? 'Выберите приход или проверьте статус заявки, чтобы читать новости участников.'
                : 'Войдите и присоединитесь к своему приходу, чтобы читать его новости.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            onPressed: () =>
                context.go(signedIn ? '/my-parish' : '/auth?from=/my-parish'),
            child: Text(
              signedIn ? 'Открыть Mellon' : 'Войти или зарегистрироваться',
            ),
          ),
        ],
      ),
    ),
  );
}
