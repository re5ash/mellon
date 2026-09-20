class HelpRequest {
  const HelpRequest({
    required this.id,
    required this.title,
    required this.description,
    this.createdAt,
  });
  final String id;
  final String title;
  final String description;
  final DateTime? createdAt;
  factory HelpRequest.fromJson(Map<String, dynamic> json) => HelpRequest(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    createdAt: json['created_at'] == null
        ? null
        : DateTime.parse(json['created_at'] as String),
  );
}
