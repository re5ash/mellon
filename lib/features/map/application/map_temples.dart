import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../../parishes/domain/parish.dart';
import '../domain/map_place.dart';

/// Both the club address and map markers read the same parish records.
final mapTemplesProvider = FutureProvider.autoDispose<List<Parish>>((ref) async {
  ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
  final client = ref.watch(backendProvider);
  var disposed = false;
  Timer? debounce;
  final channel = client.channel('mellon-map-temples');
  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'parishes',
    callback: (_) {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), () {
        if (!disposed) ref.invalidateSelf();
      });
    },
  ).subscribe();
  // Works even when Realtime is not enabled for parishes in this project.
  final refresh = Timer(const Duration(seconds: 30), () {
    if (!disposed) ref.invalidateSelf();
  });
  ref.onDispose(() {
    disposed = true;
    debounce?.cancel();
    refresh.cancel();
    unawaited(client.removeChannel(channel));
  });
  final result = <String, Parish>{};
  const pageSize = 500;
  for (var offset = 0; !disposed; offset += pageSize) {
    final rows = await client
        .from('parishes')
        .select('id,name,address,description,latitude,longitude')
        .order('id')
        .range(offset, offset + pageSize - 1)
        .timeout(const Duration(seconds: 15));
    for (final row in rows) {
      final parish = Parish.fromJson(row);
      result[parish.id] = parish;
    }
    if (rows.length < pageSize) break;
  }
  return List<Parish>.unmodifiable(result.values);
}, retry: (_, error) => null);

Parish? templeById(Iterable<Parish> temples, String id) {
  for (final temple in temples) {
    if (temple.id == id) return temple;
  }
  return null;
}

MapPlace? templeMapPlace(Parish temple) {
  final latitude = temple.latitude;
  final longitude = temple.longitude;
  if (latitude == null || longitude == null ||
      !latitude.isFinite || !longitude.isFinite ||
      latitude < -90 || latitude > 90 ||
      longitude < -180 || longitude > 180) return null;
  // Existing local photo/hours belong to this ID, never a name match.
  final existing = temple.id == alexanderNevsky.id;
  return MapPlace(
    id: temple.id,
    title: temple.name,
    address: temple.address,
    point: LatLng(latitude, longitude),
    photoAsset: existing ? alexanderNevsky.photoAsset : null,
    hours: existing ? alexanderNevsky.hours : null,
  );
}
