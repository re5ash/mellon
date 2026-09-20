import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/components/record_card.dart';
import '../../../design_system/tokens.dart';
import '../../feed/domain/publication_icon.dart';
import '../application/help_providers.dart';

class HelpRequestPage extends ConsumerWidget {
  const HelpRequestPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ContentFrame(
    child: AsyncContent(
      value: ref.watch(helpProvider),
      onRetry: () => ref.invalidate(helpProvider),
      builder: (items) => ListView(
        children: [
          if (items.isEmpty)
            const EmptyState(
              title: 'Пока нет объявлений о помощи',
              message:
                  'Здесь появятся просьбы о помощи и добрые дела приходов.',
            ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: RecordCard(
                key: ValueKey(item.id),
                title: item.title,
                body: item.description,
                category: 'Помощь',
                icon: suggestPublicationIcon(
                  item.title,
                  item.description,
                  seed: item.id,
                ).icon,
                date: item.createdAt,
              ),
            ),
        ],
      ),
    ),
  );
}
