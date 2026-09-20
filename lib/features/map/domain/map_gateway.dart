import '../../parishes/domain/parish.dart';

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}

abstract interface class MapGateway {
  // Adapter chosen separately: licensed tiles, attribution, quotas and geo permission UX.
  Future<void> focus(GeoPoint point);
  Future<GeoPoint?> requestUserLocation();
  Future<void> showParishes(List<Parish> parishes);
  Future<void> dispose();
}
