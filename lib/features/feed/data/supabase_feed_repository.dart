import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pagination/cursor_page.dart';
import '../domain/feed_repository.dart';
import '../domain/post.dart';

class SupabaseFeedRepository implements FeedRepository {
  SupabaseFeedRepository(this.client);
  final SupabaseClient client;
  static const pageSize = 20;
  @override
  Future<CursorPage<Post>> page({String? parishId, PageCursor? before}) async {
    var query = client
        .from(parishId == null ? 'mellon_general_feed' : 'posts')
        .select();
    if (parishId != null) {
      query = query
          .eq('parish_id', parishId)
          .eq('status', 'published')
          .lte('published_at', DateTime.now().toUtc().toIso8601String());
    }
    if (before != null) {
      if (parishId != null) {
        query = query.or(before.beforeFilter('published_at'));
      } else {
        if (!RegExp(r'^(post|event):[0-9a-fA-F-]{36}$').hasMatch(before.id)) {
          throw const FormatException('Invalid cursor');
        }
        final date = before.timestamp.toUtc().toIso8601String();
        query = query.or(
          'published_at.lt.$date,and(published_at.eq.$date,id.lt.${before.id})',
        );
      }
    }
    final rows = await query
        .order('published_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize + 1);
    final items = rows
        .take(pageSize)
        .map(Post.fromJson)
        .toList(growable: false);
    return CursorPage(
      items: items,
      next: rows.length > pageSize
          ? PageCursor(items.last.publishedAt, items.last.id)
          : null,
    );
  }
}
