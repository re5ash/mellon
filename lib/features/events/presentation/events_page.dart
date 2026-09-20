import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/components/record_card.dart';
import '../../../design_system/tokens.dart';
import '../../feed/domain/publication_icon.dart';
import '../../feed/presentation/publication_photo.dart';
import '../application/events_providers.dart';

class ParishEventPage extends ConsumerWidget {
  const ParishEventPage({
    this.ownParish = false,
    this.schedule = false,
    super.key,
  });
  final bool ownParish, schedule;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ownParish ? myParishEventsProvider : eventsProvider;
    return ContentFrame(
      child: AsyncContent(
        value: ref.watch(provider),
        // Live updates must retain the mounted list and decoded photographs.
        // Dependency changes and access errors still clear the previous rows.
        preserveOnRefresh: true,
        onRetry: () => ref.invalidate(provider),
        builder: (items) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (ownParish) ...[
              Text(
                schedule ? 'Расписание прихода' : 'События моего прихода',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            if (items.isEmpty)
              const EmptyState(
                title: 'Пока нет событий',
                message: 'Опубликованные предстоящие события появятся здесь.',
              ),
            for (final item in items)
              Padding(
                key: ValueKey(item.id),
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: RecordCard(
                  key: ValueKey(item.id),
                  title: item.title,
                  body: item.description,
                  category: item.section == 'schedule'
                      ? 'Расписание'
                      : 'Событие',
                  icon:
                      (publicationIconById(item.iconId) ??
                              suggestPublicationIcon(
                                item.title,
                                item.description,
                                seed: item.id,
                              ))
                          .icon,
                  date: item.startsAt,
                  showTime: true,
                  location: item.location,
                  photo: item.photoPath == null
                      ? null
                      : PublicationPhoto(path: item.photoPath!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
