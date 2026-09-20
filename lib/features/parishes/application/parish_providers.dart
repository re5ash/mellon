import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';
import '../data/supabase_parish_repository.dart';
import '../domain/parish.dart';
import '../domain/parish_repository.dart';

final parishRepositoryProvider = Provider<ParishRepository>(
  (ref) => SupabaseParishRepository(ref.watch(backendProvider)),
);
final parishListProvider = FutureProvider.autoDispose
    .family<List<Parish>, String>((ref, query) {
      ref.watch(authUserProvider);
      return ref.watch(parishRepositoryProvider).list(query: query);
    });
final parishProvider = FutureProvider.autoDispose.family<Parish, String>((
  ref,
  id,
) {
  ref.watch(authUserProvider);
  return ref.watch(parishRepositoryProvider).get(id);
});
