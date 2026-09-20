import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../design_system/appearance_palette.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/theme_controller.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/club_registration_dialog.dart';
import '../../community/community_repository.dart';
import '../../community/community_widgets.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});
  Future<void> _action(
    BuildContext context,
    Future<void> Function() run,
  ) async {
    try {
      await run();
    } on Object catch (e) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authUserProvider).asData?.value != null;
    final configuration = ref.watch(appConfigurationProvider).asData?.value;
    final appearance = ref.watch(appearanceControllerProvider);
    return SingleChildScrollView(
      child: ContentFrame(
        maxWidth: AppLayout.formMaxWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Настройки',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (configuration != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(configuration['welcome_text'] as String),
              ),
            if ((configuration?['support_email'] as String? ?? '').isNotEmpty)
              CommunityTile(
                title: 'Поддержка',
                subtitle: configuration!['support_email'] as String,
                icon: Icons.help_outline,
              ),
            const SizedBox(height: AppSpace.lg),
            if (signedIn) ...[
              CommunityTile(
                key: const ValueKey('open-profile'),
                title: 'Профиль',
                subtitle: 'Фото, имя и личные данные',
                icon: Icons.person_rounded,
                color: const Color(0xFF168AF4),
                onTap: () => context.push('/profile/details'),
              ),
              const SizedBox(height: AppSpace.xl),
            ],
            Card(
              child: ListTile(
                key: const ValueKey('open-appearance'),
                leading: Icon(
                  Icons.palette_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Оформление'),
                subtitle: Text(
                  '${AppearancePalette.presetLabel(appearance.preset)} · ${(appearance.textScale * 100).round()}%',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/profile/appearance'),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            if (signedIn)
              OutlinedButton(
                onPressed: () => _action(
                  context,
                  () => ref.read(authRepositoryProvider).signOut(),
                ),
                child: const Text('Выйти из аккаунта'),
              )
            else
              FilledButton(
                onPressed: () =>
                    openClubRegistration(context, startWithSignIn: true),
                child: const Text('Войти'),
              ),
          ],
        ),
      ),
    );
  }
}
