class Post {
  const Post({
    required this.id,
    required this.parishId,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.source = 'post',
    this.sourceId,
    this.photoPath,
    this.iconId,
    this.startsAt,
    this.location,
  });
  final String id, parishId, title, body, source;
  final String? sourceId, photoPath, iconId, location;
  final DateTime publishedAt;
  final DateTime? startsAt;
  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as String,
    parishId: json['parish_id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    publishedAt: DateTime.parse(json['published_at'] as String),
    source: json['source_kind'] as String? ?? 'post',
    sourceId: json['source_id'] as String?,
    photoPath: json['photo_path'] as String?,
    iconId: json['icon_id'] as String?,
    location: json['location_label'] as String?,
    startsAt: DateTime.tryParse(json['starts_at'] as String? ?? ''),
  );
}
