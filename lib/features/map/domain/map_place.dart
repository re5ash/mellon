import 'package:latlong2/latlong.dart';

class MapPlace {
  const MapPlace({
    required this.id,
    required this.title,
    required this.address,
    required this.point,
    this.photoAsset,
    this.hours,
    this.timeLabel,
    this.dateLabel,
  });
  final String id, title, address;
  final LatLng point;
  final String? photoAsset, hours, timeLabel, dateLabel;
}

const alexanderNevsky = MapPlace(
  id: 'c9102d4b-4ad0-4b03-b523-179052cbc0c0',
  title: 'Храм святого благоверного князя Александра Невского',
  // Displayed address and marker coordinates come from the parish record.
  address: '',
  point: LatLng(54.723306, 20.526467),
  photoAsset: 'assets/map/alexander_nevsky.jpg',
  hours: 'Ежедневно с 8 до 19',
);

class MapEvent {
  const MapEvent({
    required this.place,
    required this.startsAt,
    this.isToday = true,
  });
  final MapPlace place;
  final DateTime startsAt;
  final bool isToday;
  factory MapEvent.fromJson(Map<String, dynamic> row) => MapEvent(
    startsAt: DateTime.parse(row['starts_at'] as String),
    isToday: row['is_today'] == true,
    place: MapPlace(
      id: row['id'] as String,
      title: row['title'] as String,
      address: row['location_label'] as String? ?? '',
      point: LatLng(
        (row['map_latitude'] as num).toDouble(),
        (row['map_longitude'] as num).toDouble(),
      ),
      timeLabel: row['time_label'] as String,
      dateLabel: row['date_label'] as String?,
    ),
  );
}

String distanceLabel(LatLng from, LatLng to) {
  final metres = const Distance().as(LengthUnit.Meter, from, to);
  if (metres < 1000) return '${(metres / 10).round() * 10} м';
  final km = metres / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0).replaceAll('.', ',')} км';
}

Uri placeLink(MapPlace place) => Uri.https('yandex.ru', '/maps/', {
  'pt': '${place.point.longitude},${place.point.latitude}',
  'z': '17',
  'l': 'map',
});
