import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'photo_store_stub.dart'
    if (dart.library.io) 'photo_store_io.dart'
    if (dart.library.js_interop) 'photo_store_web.dart'
    as platform;

String photoCacheHash(String value) =>
    sha256.convert(utf8.encode(value)).toString();

abstract interface class PhotoStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
  Future<void> clear();
}

// Immutable object paths are revision identifiers. Only thumbnails are stored.
PhotoStore createPhotoStore(String scope) =>
    platform.createStore(photoCacheHash(scope));

const photoStoreMaxBytes = 32 * 1024 * 1024;
const photoStoreMaxEntries = 60;
const photoStoreLifetime = Duration(days: 14);
