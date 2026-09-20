import '../../../core/pagination/cursor_page.dart';
import 'admin_models.dart';

abstract interface class AdminRepository {
  Future<ParishBatch> parishes({String? after});
  Future<AdminParish?> parish(String id);
  Future<String> saveParish(ParishInput input);
  Future<CursorPage<AdminPost>> posts(AdminListRequest request);
  Future<AdminPost?> post(AdminPostRequest request);
  Future<String> savePost(PostInput input);
  Future<CursorPage<PendingMembership>> requests(AdminListRequest request);
  Future<void> review(String membershipId, {required bool approve});
}
