import 'package:flutter/material.dart';

import '../tokens.dart';

class ParishWelcome extends StatelessWidget {
  const ParishWelcome({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.church_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Добро пожаловать\nв ваш приход!',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpace.md),
              const Text(
                'Читайте новости, общайтесь в чатах и участвуйте в добрых делах вместе.',
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                '«Где двое или трое собраны во имя Моё, там Я посреди них».\nМф. 18:20',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
