import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/backend_provider.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(
    ref.watch(backendProvider),
    ref.watch(configProvider).authRedirectUrl,
  ),
);
final authUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchUser(),
);
