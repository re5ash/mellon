import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/app_user.dart';
import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client, this.redirectUrl);
  final SupabaseClient client;
  final String redirectUrl;
  @override
  Stream<AppUser?> watchUser() async* {
    yield client.auth.currentUser == null
        ? null
        : AppUser(client.auth.currentUser!.id);
    yield* client.auth.onAuthStateChange.map(
      (event) => event.session == null ? null : AppUser(event.session!.user.id),
    );
  }

  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<bool> signUp(String email, String password) async {
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: redirectUrl,
    );
    return response.session == null;
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
