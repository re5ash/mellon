import 'dart:convert';

class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.publishableKey,
    required this.authRedirectUrl,
  });
  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    authRedirectUrl: String.fromEnvironment('AUTH_REDIRECT_URL'),
  );
  final String supabaseUrl;
  final String publishableKey;
  final String authRedirectUrl;

  void validate({required bool release}) {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty ||
        !(uri.scheme == 'https' ||
            (!release &&
                uri.scheme == 'http' &&
                const [
                  'localhost',
                  '127.0.0.1',
                  '10.0.2.2',
                ].contains(uri.host)))) {
      throw const FormatException(
        'Укажите корректный SUPABASE_URL. Для релиза требуется HTTPS.',
      );
    }
    var publicKey =
        publishableKey.startsWith('sb_publishable_') &&
        !publishableKey.contains('REPLACE_ME');
    if (publishableKey.startsWith('eyJ')) {
      try {
        final payload =
            jsonDecode(
                  utf8.decode(
                    base64Url.decode(
                      base64Url.normalize(publishableKey.split('.')[1]),
                    ),
                  ),
                )
                as Map<String, dynamic>;
        publicKey = payload['role'] == 'anon';
      } on Object {
        publicKey = false;
      }
    }
    if (!publicKey)
      throw const FormatException(
        'Нужен publishable key или legacy anon key. Секретные ключи запрещены.',
      );
    final redirect = Uri.tryParse(authRedirectUrl);
    if (redirect == null ||
        !redirect.hasScheme ||
        !(redirect.scheme == 'https' ||
            redirect.scheme == 'org.moyprihod.app' ||
            (!release &&
                redirect.scheme == 'http' &&
                const ['localhost', '127.0.0.1'].contains(redirect.host)))) {
      throw const FormatException(
        'Укажите AUTH_REDIRECT_URL и добавьте его в разрешённые адреса Supabase Auth.',
      );
    }
  }
}
