class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.targetPath,
    required this.isRead,
    this.kind = '',
    this.subjectUserId,
    this.youthRequestId,
  });
  final String id;
  final String title;
  final String body;
  final String targetPath;
  final bool isRead;
  final String kind;
  final String? subjectUserId, youthRequestId;
  bool get hasApplicant =>
      (kind == 'review_routing' || kind == 'youth_request') &&
      (subjectUserId != null || youthRequestId != null);
  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        targetPath: json['target_path'] as String,
        isRead: json['read_at'] != null,
        kind: json['kind'] as String? ?? '',
        subjectUserId: json['subject_user_id'] as String?,
        youthRequestId: json['youth_request_id'] as String?,
      );
}
