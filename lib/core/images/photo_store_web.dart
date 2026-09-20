import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'photo_store.dart';

PhotoStore createStore(String scope) => BrowserPhotoStore(scope);

class BrowserPhotoStore implements PhotoStore {
  BrowserPhotoStore(this.scope);
  final String scope;
  String get _name => 'mellon-photos-v1-$scope';
  String _url(String key) =>
      '${web.window.location.origin}/__mellon_photo_cache__/${photoCacheHash(key)}';
  Future<web.Cache> _cache() => web.window.caches.open(_name).toDart;
  @override
  Future<Uint8List?> read(String key) async {
    final cache = await _cache();
    final response = await cache.match(_url(key).toJS).toDart;
    if (response == null) return null;
    final saved =
        int.tryParse(response.headers.get('x-mellon-saved') ?? '') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - saved >
        photoStoreLifetime.inMilliseconds) {
      await cache.delete(_url(key).toJS).toDart;
      return null;
    }
    return (await response.arrayBuffer().toDart).toDart.asUint8List();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.length > photoStoreMaxBytes) return;
    final cache = await _cache();
    final headers = web.Headers();
    headers.set('x-mellon-saved', '${DateTime.now().millisecondsSinceEpoch}');
    headers.set('x-mellon-size', '${bytes.length}');
    await cache
        .put(
          _url(key).toJS,
          web.Response(bytes.toJS, web.ResponseInit(headers: headers)),
        )
        .toDart;
    final keys = (await cache.keys().toDart).toDart;
    final entries = <({web.Request request, int size, int saved})>[];
    for (final request in keys) {
      final response = await cache.match(request).toDart;
      if (response == null) continue;
      entries.add((
        request: request,
        size: int.tryParse(response.headers.get('x-mellon-size') ?? '') ?? 0,
        saved: int.tryParse(response.headers.get('x-mellon-saved') ?? '') ?? 0,
      ));
    }
    entries.sort((a, b) => a.saved.compareTo(b.saved));
    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    var count = entries.length;
    for (final entry in entries) {
      if (count <= photoStoreMaxEntries &&
          total <= photoStoreMaxBytes &&
          DateTime.now().millisecondsSinceEpoch - entry.saved <=
              photoStoreLifetime.inMilliseconds)
        break;
      await cache.delete(entry.request).toDart;
      count--;
      total -= entry.size;
    }
  }

  @override
  Future<void> remove(String key) async =>
      (await _cache()).delete(_url(key).toJS).toDart.then((_) {});
  @override
  Future<void> clear() async =>
      web.window.caches.delete(_name).toDart.then((_) {});
}
