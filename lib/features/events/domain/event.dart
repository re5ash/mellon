class ParishEvent {
  const ParishEvent({
    required this.id,
    required this.title,
    required this.description,
    this.startsAt,
    this.photoPath,
    this.iconId,
    this.location,
    this.section,
  });
  final String id;
  final String title;
  final String description;
  final DateTime? startsAt;
  final String? photoPath, iconId, location, section;
  factory ParishEvent.fromJson(Map<String, dynamic> json) => ParishEvent(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String,
    photoPath: json['photo_path'] as String?,
    iconId: json['icon_id'] as String?,
    location: json['location_label'] as String?,
    section: json['club_section'] as String?,
    startsAt: json['starts_at'] == null
        ? null
        : DateTime.parse(json['starts_at'] as String),
  );
}
