import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../design_system/tokens.dart';
import '../../../community/community_repository.dart';
import '../../../parishes/domain/parish.dart';

class ParishIdentityCard extends ConsumerWidget {
  const ParishIdentityCard({required this.parish, super.key});
  final Parish parish;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < 440 ||
              MediaQuery.textScalerOf(context).scale(14) > 22;
          final picture = Semantics(
            label: 'Фотография прихода пока не добавлена',
            child: AspectRatio(
              aspectRatio: narrow ? 2.4 : 1.3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primaryContainer,
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.church_rounded,
                    size: 72,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(parish.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpace.sm),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await context.push<void>('/parishes/${parish.id}');
                },
                icon: const Icon(Icons.info_outline),
                label: const Text('О приходе'),
              ),
              const SizedBox(height: AppSpace.sm),
              if (parish.address.isNotEmpty)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(parish.address)),
                  ],
                ),
              const SizedBox(height: AppSpace.sm),
              Text(
                ref
                            .watch(appConfigurationProvider)
                            .asData
                            ?.value['welcome_text']
                        as String? ??
                    'Вера объединяет людей',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          return narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    picture,
                    const SizedBox(height: AppSpace.md),
                    details,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 2, child: picture),
                    const SizedBox(width: AppSpace.md),
                    Expanded(flex: 3, child: details),
                  ],
                );
        },
      ),
    ),
  );
}
