import 'dart:typed_data';

import 'photo_store.dart';

PhotoStore createStore(String scope) => _NoPhotoStore();

class _NoPhotoStore implements PhotoStore {
  @override
  Future<Uint8List?> read(String key) async => null;
  @override
  Future<void> write(String key, Uint8List bytes) async {}
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clear() async {}
}
