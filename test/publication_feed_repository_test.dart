import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moy_prihod/core/pagination/cursor_page.dart';
import 'package:moy_prihod/features/feed/data/supabase_feed_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'general feed uses one projection, metadata and a stable composite cursor',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode(
              List.generate(
                21,
                (i) => {
                  'id':
                      'event:00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
                  'source_id':
                      '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}',
                  'source_kind': 'schedule',
                  'parish_id': 'parish',
                  'title': 'Расписание',
                  'body': 'Описание',
                  'published_at': '2026-09-19T10:00:00Z',
                  'starts_at': '2026-09-20T10:00:00Z',
                  'photo_path': 'club/event/image.png',
                  'icon_id': 'event_date',
                },
              ),
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = SupabaseFeedRepository(client);
      final page = await repo.page();
      expect(requests.single.path, '/rest/v1/mellon_general_feed');
      expect(page.items, hasLength(20));
      expect(page.items.first.source, 'schedule');
      expect(page.items.first.photoPath, 'club/event/image.png');
      expect(page.items.first.startsAt, isNotNull);
      expect(page.next, isNotNull);
      await repo.page(before: page.next);
      expect(requests.last.queryParameters['or'], contains(page.next!.id));
      await expectLater(
        repo.page(before: PageCursor(DateTime.now(), 'event:bad,filter')),
        throwsFormatException,
      );
      final before = requests.length;
      await repo.page(parishId: 'parish');
      expect(requests.length, before + 1);
      expect(requests.last.path, '/rest/v1/posts');
      expect(requests.last.queryParameters['status'], 'eq.published');
    },
  );
}
