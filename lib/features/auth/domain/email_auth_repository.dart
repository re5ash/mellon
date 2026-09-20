enum EmailPurpose { confirmation, recovery }

/// All token validation and password changes are performed by Supabase Auth.
abstract interface class EmailAuthRepository {
  String? get currentUserId;
  Future<void> send(String email, EmailPurpose purpose);
  Future<String> verify({
    required EmailPurpose purpose,
    String? email,
    String? code,
    String? tokenHash,
  });
  Future<void> setPassword(String password, String expectedUserId);
}
