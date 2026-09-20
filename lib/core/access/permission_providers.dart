import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../backend/backend_provider.dart';

// A display hint only. PostgreSQL independently checks every operation.
final permissionsProvider = FutureProvider.autoDispose
    .family<Set<String>, String?>((ref, parishId) async {
      ref.watch(authUserProvider.select((value) => value.asData?.value?.id));
      final rows = await ref
          .watch(backendProvider)
          .rpc<List<dynamic>>('my_permissions', params: {'p_parish': parishId});
      return rows
          .map(
            (row) => (row as Map<String, dynamic>)['permission_key'] as String,
          )
          .toSet();
    });
