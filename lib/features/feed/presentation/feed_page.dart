import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' as rendering show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/pagination/cursor_page.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/components/navigation_content_insets.dart';
import '../../../design_system/components/record_card.dart';
import '../../../design_system/tokens.dart';
import '../application/feed_providers.dart';
import '../domain/publication_icon.dart';
import 'publication_photo.dart';

class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({this.parishId, super.key});
  final String? parishId;
  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  PageCursor? _cursor;
  final List<PageCursor?> _history = [];
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = (parishId: widget.parishId, before: _cursor);
    ref.watch(feedChangesProvider);
    return ContentFrame(
      child: AsyncContent(
        value: ref.watch(feedPageProvider(request)),
        preserveOnRefresh: true,
        onRetry: () => ref.invalidate(feedPageProvider(request)),
        builder: (page) {
          final indices = {
            for (var i = 0; i < page.items.length; i++) page.items[i].id: i,
          };
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(feedPageProvider(request));
              await ref.read(feedPageProvider(request).future);
            },
            child: ListView.builder(
              key: PageStorageKey('feed-${widget.parishId ?? "general"}'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              scrollCacheExtent: const rendering.ScrollCacheExtent.pixels(240),
              padding: EdgeInsets.only(
                bottom: NavigationContentInsets.of(context) + AppSpace.md,
              ),
              itemCount: page.items.length + 1,
              findChildIndexCallback: (key) =>
                  key is ValueKey<String> ? indices[key.value] : null,
              itemBuilder: (context, index) {
                if (index == page.items.length) {
                  return Column(
                    children: [
                      if (page.items.isEmpty)
                        const EmptyState(
                          title: 'Пока нет публикаций',
                          message: 'Новые записи появятся здесь.',
                        ),
                      Wrap(
                        spacing: AppSpace.md,
                        runSpacing: AppSpace.sm,
                        children: [
                          if (_history.isNotEmpty)
                            OutlinedButton(
                              onPressed: () => setState(
                                () => _cursor = _history.removeLast(),
                              ),
                              child: const Text('Назад'),
                            ),
                          if (page.next != null)
                            FilledButton(
                              onPressed: () => setState(() {
                                _history.add(_cursor);
                                _cursor = page.next;
                              }),
                              child: const Text('Следующие записи'),
                            ),
                        ],
                      ),
                    ],
                  );
                }
                final post = page.items[index];
                final icon =
                    publicationIconById(post.iconId) ??
                    suggestPublicationIcon(
                      post.title,
                      post.body,
                      seed: post.id,
                    );
                return Padding(
                  key: ValueKey(post.id),
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: RecordCard(
                    title: post.title,
                    body: post.body,
                    date: post.startsAt ?? post.publishedAt,
                    showTime: post.startsAt != null,
                    location: post.location,
                    photo: post.photoPath == null
                        ? null
                        : PublicationPhoto(path: post.photoPath!),
                    category: post.source == 'schedule'
                        ? 'Расписание'
                        : icon.group,
                    icon: icon.icon,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
