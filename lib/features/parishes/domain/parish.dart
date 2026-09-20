class Parish {
  const Parish({
    required this.id,
    required this.name,
    required this.address,
    required this.description,
    this.latitude,
    this.longitude,
  });
  final String id;
  final String name;
  final String address;
  final String description;
  final double? latitude;
  final double? longitude;
  factory Parish.fromJson(Map<String, dynamic> json) => Parish(
    id: json['id'] as String,
    name: json['name'] as String,
    address: json['address'] as String,
    description: json['description'] as String,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );
}
