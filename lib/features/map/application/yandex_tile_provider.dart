import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

class YandexTileProvider extends NetworkTileProvider {
  factory YandexTileProvider() => YandexTileProvider._(YandexTileClient());
  YandexTileProvider._(this._client)
    : super(
        httpClient: _client,
        attemptDecodeOfHttpErrorResponses: false,
        cachingProvider: const DisabledMapCachingProvider(),
      );
  final YandexTileClient _client;
  @override
  Future<void> dispose() async {
    _client.close();
    await super.dispose();
  }
}

/// Pace requests across the main map and the event picker. There is no
/// automatic retry storm; obsolete tiles are skipped before reaching Yandex.
class YandexTileClient extends http.BaseClient {
  YandexTileClient({http.Client? inner}) : _inner = inner ?? http.Client();
  final http.Client _inner;
  static Future<void> _turn = Future.value();
  static final _clock = Stopwatch()..start();
  static int _lastStart = -50;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    var aborted = false;
    if (request is http.Abortable) {
      unawaited(request.abortTrigger?.then((_) => aborted = true));
    }
    final turn = _turn.then((_) async {
      if (_closed || aborted) return;
      final delay = 50 - (_clock.elapsedMilliseconds - _lastStart);
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      if (!_closed && !aborted) _lastStart = _clock.elapsedMilliseconds;
    });
    _turn = turn;
    await turn;
    if (_closed || aborted) throw http.RequestAbortedException();
    return _inner.send(request);
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
  }
}
