import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moy_prihod/features/map/application/yandex_tile_provider.dart';

void main() {
  test(
    'both maps share pacing without sending a burst of tile requests',
    () async {
      final clock = Stopwatch()..start();
      final starts = <int>[];
      http.Client inner() => MockClient((request) async {
        starts.add(clock.elapsedMilliseconds);
        return http.Response('', 200);
      });
      final first = YandexTileClient(inner: inner());
      final second = YandexTileClient(inner: inner());
      addTearDown(first.close);
      addTearDown(second.close);
      await Future.wait(
        List.generate(
          12,
          (i) => (i.isEven ? first : second).get(
            Uri.parse('https://map.test/tile/$i'),
          ),
        ),
      );
      expect(starts.length, 12);
      for (var i = 1; i < starts.length; i++) {
        expect(starts[i] - starts[i - 1], greaterThanOrEqualTo(45));
      }
    },
  );

  test(
    'obsolete and disposed queued requests never reach the service',
    () async {
      var sent = 0;
      final client = YandexTileClient(
        inner: MockClient((request) async {
          sent++;
          return http.Response('', 200);
        }),
      );
      final abort = Completer<void>();
      final request = http.AbortableRequest(
        'GET',
        Uri.parse('https://map.test/tile'),
        abortTrigger: abort.future,
      );
      final result = expectLater(
        client.send(request),
        throwsA(isA<http.RequestAbortedException>()),
      );
      abort.complete();
      client.close();
      await result;
      expect(sent, 0);
    },
  );
}
