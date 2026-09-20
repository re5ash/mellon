import 'email_auth_repository.dart';

/// Only the two explicitly supported purposes are accepted. No redirect URL
/// from an email is trusted and no verification happens just by opening a page.
class AuthLink {
  const AuthLink(this.purpose, this.tokenHash);
  final EmailPurpose purpose;
  final String tokenHash;
  static AuthLink? parse(Uri uri) {
    final parameters = uri.queryParametersAll;
    if (parameters['type']?.length != 1 ||
        parameters['token_hash']?.length != 1)
      return null;
    final type = uri.queryParameters['type'];
    final token = uri.queryParameters['token_hash'] ?? '';
    if (!RegExp(r'^[a-zA-Z0-9_-]{32,512}$').hasMatch(token)) return null;
    if (type != 'email' && type != 'recovery') return null;
    return AuthLink(
      type == 'recovery' ? EmailPurpose.recovery : EmailPurpose.confirmation,
      token,
    );
  }
}
