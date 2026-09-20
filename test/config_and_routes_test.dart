import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/router/route_access.dart';
import 'package:moy_prihod/core/config/app_config.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';

void main() {
  AppConfig config(String key, {String url = 'https://example.supabase.co'}) =>
      AppConfig(
        supabaseUrl: url,
        publishableKey: key,
        authRedirectUrl: 'https://parish.example/',
      );
  test('privileged and malformed keys are rejected', () {
    for (final key in ['sb_secret_test', '', 'eyJ.invalid.signature']) {
      expect(() => config(key).validate(release: true), throwsFormatException);
    }
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'role': 'service_role'})))
        .replaceAll('=', '');
    expect(
      () => config('eyJheader.$payload.signature').validate(release: true),
      throwsFormatException,
    );
  });
  test('publishable key accepted; HTTP rejected in release', () {
    expect(
      () => config('sb_publishable_test').validate(release: true),
      returnsNormally,
    );
    expect(
      () => config(
        'sb_publishable_test',
        url: 'http://localhost:54321',
      ).validate(release: true),
      throwsFormatException,
    );
  });
  test('external URLs cannot be used for notification or login redirects', () {
    for (final target in [
      'https://evil.example',
      '//evil.example',
      '/auth',
      '/%2f%2fevil.example',
      '/unknown',
    ]) {
      expect(safeDestination(target), '/feed');
    }
    expect(safeDestination('/my-parish'), '/my-parish');
    expect(requiresSignIn('/chats/room'), isTrue);
    expect(requiresSignIn('/parishes/one'), isFalse);
  });
  test('feed cursor includes UUID tie-breaker for equal timestamps', () {
    final cursor = PageCursor(
      DateTime.utc(2026, 9, 10),
      'a0000000-0000-0000-0000-000000000001',
    );
    final filter = cursor.beforeFilter('published_at');
    expect(filter, contains('and(published_at.eq.'));
    expect(filter, contains('id.lt.a0000000-0000-0000-0000-000000000001'));
  });
}
