import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pagination/cursor_page.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

class SupabaseAdminRepository implements AdminRepository {
  const SupabaseAdminRepository(this.client);
  final SupabaseClient client;
  static const pageSize = 20;
  static const postFields =
      'id,parish_id,title,body,visibility,status,created_at,updated_at';
  @override
  Future<ParishBatch> parishes({String? after}) async {
    final rows = await client.rpc<List<dynamic>>(
      'admin_parishes',
      params: {'p_after': after, 'p_limit': pageSize + 1},
    );
    final items = rows
        .take(pageSize)
        .map((row) => AdminParish.fromJson(row as Map<String, dynamic>))
        .toList();
    return ParishBatch(items, rows.length > pageSize ? items.last.id : null);
  }

  @override
  Future<AdminParish?> parish(String id) async {
    final rows = await client.rpc<List<dynamic>>(
      'admin_parishes',
      params: {'p_only': id, 'p_limit': 1},
    );
    return rows.isEmpty
        ? null
        : AdminParish.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<String> saveParish(ParishInput input) => client.rpc<String>(
    'admin_save_parish',
    params: {
      'p_id': input.id,
      'p_create': input.create,
      'p_city_name': input.cityName,
      'p_name': input.name,
      'p_description': input.description,
      'p_address': input.address,
      'p_join_mode': input.joinMode,
      'p_is_published': input.isPublished,
      'p_expected_updated_at': input.expectedUpdatedAt
          ?.toUtc()
          .toIso8601String(),
    },
  );
  @override
  Future<CursorPage<AdminPost>> posts(AdminListRequest request) async {
    var query = client
        .from('posts')
        .select(postFields)
        .eq('parish_id', request.parishId);
    if (request.before != null)
      query = query.or(request.before!.beforeFilter('created_at'));
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize + 1);
    final items = rows.take(pageSize).map(AdminPost.fromJson).toList();
    return CursorPage(
      items: items,
      next: rows.length > pageSize
          ? PageCursor(items.last.createdAt, items.last.id)
          : null,
    );
  }

  @override
  Future<AdminPost?> post(AdminPostRequest request) async {
    final row = await client
        .from('posts')
        .select(postFields)
        .eq('parish_id', request.parishId)
        .eq('id', request.postId)
        .maybeSingle();
    return row == null ? null : AdminPost.fromJson(row);
  }

  @override
  Future<String> savePost(PostInput input) => client.rpc<String>(
    'admin_save_post',
    params: {
      'p_id': input.id,
      'p_parish': input.parishId,
      'p_create': input.create,
      'p_title': input.title,
      'p_body': input.body,
      'p_visibility': input.visibility,
      'p_status': input.status,
      'p_expected_updated_at': input.expectedUpdatedAt
          ?.toUtc()
          .toIso8601String(),
    },
  );
  @override
  Future<CursorPage<PendingMembership>> requests(
    AdminListRequest request,
  ) async {
    final rows = await client.rpc<List<dynamic>>(
      'admin_pending_memberships',
      params: {
        'p_parish': request.parishId,
        'p_before': request.before?.timestamp.toUtc().toIso8601String(),
        'p_before_id': request.before?.id,
        'p_limit': pageSize + 1,
      },
    );
    final items = rows
        .take(pageSize)
        .map((row) => PendingMembership.fromJson(row as Map<String, dynamic>))
        .toList();
    return CursorPage(
      items: items,
      next: rows.length > pageSize
          ? PageCursor(items.last.requestedAt, items.last.id)
          : null,
    );
  }

  @override
  Future<void> review(String membershipId, {required bool approve}) async {
    await client.rpc<Object?>(
      'review_membership',
      params: {
        'p_membership': membershipId,
        'p_decision': approve ? 'active' : 'rejected',
      },
    );
  }
}
