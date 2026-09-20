import '../../../core/pagination/cursor_page.dart';
import 'post.dart';

abstract interface class FeedRepository {
  Future<CursorPage<Post>> page({String? parishId, PageCursor? before});
}
