import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moy_prihod/core/images/supabase_photo_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'photo uses a single authenticated thumbnail GET with bounded dimensions',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.test',
        'key',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response.bytes([1, 2, 3], 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      final source = SupabasePhotoSource(client);
      expect(
        await source.download(
          'event-photos',
          'club/event/photo.png',
          edge: 640,
        ),
        [1, 2, 3],
      );
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(
        request.url.path,
        contains('/render/image/authenticated/event-photos/'),
      );
      expect(request.url.queryParameters['width'], '640');
      expect(request.url.queryParameters['height'], '640');
      expect(request.url.queryParameters['resize'], 'contain');
      expect(
        request.headers['Authorization'] ?? request.headers['authorization'],
        isNotNull,
      );
    },
  );
  test(
    'unsupported transformations are probed once; old photos remain accessible',
    () async {
      final paths = <String>[];
      final client = SupabaseClient(
        'https://example.test',
        'key',
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.contains('/render/'))
            return http.Response(
              jsonEncode({
                'statusCode': '400',
                'message': 'Image transformations not available',
                'error': 'Bad Request',
              }),
              400,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          return http.Response.bytes([1], 200, request: request);
        }),
      );
      addTearDown(client.dispose);
      final source = SupabasePhotoSource(client);
      await source.download('event-photos', 'old.png', edge: 640);
      await source.download('event-photos', 'other.png', edge: 640);
      expect(paths.where((p) => p.contains('/render/')), hasLength(1));
      expect(paths.where((p) => p.contains('/object/')), hasLength(2));
    },
  );
  test('permission failure is never retried with a public URL', () async {
    var requests = 0;
    final client = SupabaseClient(
      'https://example.test',
      'key',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response(
          jsonEncode({
            'statusCode': '403',
            'message': 'Forbidden',
            'error': 'Forbidden',
          }),
          403,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabasePhotoSource(
        client,
      ).download('event-photos', 'private.png', edge: 640),
      throwsA(isA<StorageException>()),
    );
    expect(requests, 1);
  });
}
