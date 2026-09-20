import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../domain/map_place.dart';

final mapEventsProvider = FutureProvider.autoDispose<List<MapEvent>>((
  ref,
) async {
  ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
  ref.watch(
    accountAccessProvider.select((v) => v.asData?.value.restrictedGuest),
  );
  // SECURITY INVOKER: the same event visibility rules apply on the map.
  final rows = await ref
      .watch(backendProvider)
      .rpc<List<dynamic>>('map_events_visible')
      .timeout(const Duration(seconds: 15));
  return rows
      .map((row) => MapEvent.fromJson(row as Map<String, dynamic>))
      .toList();
}, retry: (_, error) => null);
