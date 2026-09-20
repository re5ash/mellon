import '../../../core/pagination/cursor_page.dart';

typedef AdminListRequest = ({String parishId, PageCursor? before});
typedef AdminPostRequest = ({String parishId, String postId});

class AdminParish {
  const AdminParish({
    required this.id,
    required this.cityName,
    required this.name,
    required this.description,
    required this.address,
    required this.joinMode,
    required this.isPublished,
    required this.updatedAt,
    required this.permissions,
  });
  final String id, cityName, name, description, address, joinMode;
  final bool isPublished;
  final DateTime updatedAt;
  final Set<String> permissions;
  bool allows(String permission) => permissions.contains(permission);
  factory AdminParish.fromJson(Map<String, dynamic> row) => AdminParish(
    id: row['id'] as String,
    cityName: row['city_name'] as String,
    name: row['name'] as String,
    description: row['description'] as String,
    address: row['address'] as String,
    joinMode: row['join_mode'] as String,
    isPublished: row['is_published'] as bool,
    updatedAt: DateTime.parse(row['updated_at'] as String),
    permissions: (row['permissions'] as List<dynamic>).cast<String>().toSet(),
  );
}

class ParishBatch {
  const ParishBatch(this.items, this.next);
  final List<AdminParish> items;
  final String? next;
}

class ParishInput {
  const ParishInput({
    required this.id,
    required this.create,
    required this.cityName,
    required this.name,
    required this.description,
    required this.address,
    required this.joinMode,
    required this.isPublished,
    this.expectedUpdatedAt,
  });
  final String id, cityName, name, description, address, joinMode;
  final bool create, isPublished;
  final DateTime? expectedUpdatedAt;
}

class AdminPost {
  const AdminPost({
    required this.id,
    required this.parishId,
    required this.title,
    required this.body,
    required this.visibility,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, parishId, title, body, visibility, status;
  final DateTime createdAt, updatedAt;
  factory AdminPost.fromJson(Map<String, dynamic> row) => AdminPost(
    id: row['id'] as String,
    parishId: row['parish_id'] as String,
    title: row['title'] as String,
    body: row['body'] as String,
    visibility: row['visibility'] as String,
    status: row['status'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}

class PostInput {
  const PostInput({
    required this.id,
    required this.parishId,
    required this.create,
    required this.title,
    required this.body,
    required this.visibility,
    required this.status,
    this.expectedUpdatedAt,
  });
  final String id, parishId, title, body, visibility, status;
  final bool create;
  final DateTime? expectedUpdatedAt;
}

class PendingMembership {
  const PendingMembership({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.requestedAt,
  });
  final String id, userId, displayName;
  final DateTime requestedAt;
  factory PendingMembership.fromJson(Map<String, dynamic> row) =>
      PendingMembership(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        displayName: row['display_name'] as String,
        requestedAt: DateTime.parse(row['requested_at'] as String),
      );
}
