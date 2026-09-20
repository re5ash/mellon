import 'app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> watchUser();
  Future<void> signIn(String email, String password);
  Future<bool> signUp(String email, String password);
  Future<void> signOut();
}
