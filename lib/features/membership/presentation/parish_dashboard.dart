import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/components/record_card.dart';
import '../../../design_system/parish_menu_theme.dart';
import '../../../design_system/tokens.dart';
import '../../chats/application/chat_providers.dart';
import '../../events/application/events_providers.dart';
import '../../events/domain/event.dart';
import '../../help/application/help_providers.dart';
import '../../parishes/domain/parish.dart';
import 'components/parish_chat_directory.dart';
import 'components/parish_identity_card.dart';

class ParishDashboard extends ConsumerStatefulWidget {
  const ParishDashboard({required this.parish, super.key});
  final Parish parish;
  @override
  ConsumerState<ParishDashboard> createState() => _ParishDashboardState();
}

class _ParishDashboardState extends ConsumerState<ParishDashboard> {
  int _section = 0;
  static const _sections = <({String title, IconData icon, Color color})>[
    (
      title: 'Чаты',
      icon: Icons.chat_bubble_rounded,
      color: ParishMenuTheme.blue,
    ),
    (
      title: 'Расписание',
      icon: Icons.calendar_month_rounded,
      color: ParishMenuTheme.green,
    ),
    (
      title: 'События',
      icon: Icons.event_rounded,
      color: ParishMenuTheme.orange,
    ),
    (
      title: 'Помощь',
      icon: Icons.volunteer_activism,
      color: ParishMenuTheme.pink,
    ),
  ];
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final events = ref.watch(myParishEventsProvider);
    return ContentFrame(
      child: ListView(
        children: [
          ParishIdentityCard(parish: widget.parish),
          const SizedBox(height: AppSpace.md),
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppLayout.radius),
              onTap: () => setState(() => _section = 2),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ParishColorIcon(
                      icon: Icons.calendar_today_rounded,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ближайшее событие',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpace.xs),
                          AsyncContent(
                            value: events,
                            onRetry: () =>
                                ref.invalidate(myParishEventsProvider),
                            builder: (items) => items.isEmpty
                                ? Text(
                                    'Предстоящих событий пока нет.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colors.onSurfaceVariant,
                                        ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        items.first.title,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      if (items.first.startsAt != null)
                                        Text(
                                          _date(context, items.first.startsAt!),
                                          style: TextStyle(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      if (items.first.description.isNotEmpty)
                                        Text(
                                          items.first.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
              final columns = constraints.maxWidth >= 580
                  ? 4
                  : largeText
                  ? 2
                  : 4;
              final width =
                  (constraints.maxWidth - AppSpace.sm * (columns - 1)) /
                  columns;
              return Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (var i = 0; i < _sections.length; i++)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        selected: i == _section,
                        button: true,
                        child: Material(
                          color: i == _section
                              ? colors.primaryContainer
                              : colors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _section = i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpace.xs,
                                vertical: 12,
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    _sections[i].icon,
                                    color: i == 0
                                        ? colors.primary
                                        : _sections[i].color,
                                    size: 30,
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    _sections[i].title,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: i == _section
                                              ? colors.primary
                                              : colors.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpace.md),
          if (_section == 0)
            AsyncContent(
              value: ref.watch(chatRoomsProvider),
              onRetry: () => ref.invalidate(chatRoomsProvider),
              builder: (rooms) => ParishChatDirectory(
                key: ValueKey(widget.parish.id),
                rooms: rooms,
              ),
            ),
          if (_section == 1 || _section == 2) ...[
            Text(
              _section == 1 ? 'Расписание прихода' : 'События прихода',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpace.sm),
            if (_section == 1)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpace.md),
                child: Text('Предстоящие события по дате и времени.'),
              ),
            AsyncContent(
              value: events,
              onRetry: () => ref.invalidate(myParishEventsProvider),
              builder: (items) => items.isEmpty
                  ? const EmptyState(
                      title: 'Пока нет событий',
                      message: 'Опубликованные события появятся здесь.',
                    )
                  : Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
                            child: _eventCard(context, item),
                          ),
                      ],
                    ),
            ),
          ],
          if (_section == 3) ...[
            Text(
              'Помощь прихода',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpace.sm),
            AsyncContent(
              value: ref.watch(myParishHelpProvider),
              onRetry: () => ref.invalidate(myParishHelpProvider),
              builder: (items) => items.isEmpty
                  ? const EmptyState(
                      title: 'Пока нет объявлений о помощи',
                      message: 'Просьбы вашего прихода появятся здесь.',
                    )
                  : Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpace.sm),
                            child: RecordCard(
                              key: ValueKey(item.id),
                              title: item.title,
                              body: item.description,
                              category: 'Помощь',
                              icon: Icons.volunteer_activism,
                              date: item.createdAt,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: AppSpace.md),
        ],
      ),
    );
  }

  String _date(BuildContext context, DateTime date) {
    final local = date.toLocal();
    final formats = MaterialLocalizations.of(context);
    return '${formats.formatMediumDate(local)} · ${formats.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Widget _eventCard(BuildContext context, ParishEvent event) => RecordCard(
    key: ValueKey(event.id),
    title: event.title,
    body: event.startsAt == null
        ? event.description
        : '${_date(context, event.startsAt!)}\n${event.description}',
    category: 'Событие',
    icon: Icons.event_rounded,
    date: event.startsAt,
  );
}
