import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/images/photo_cache.dart';
import 'package:moy_prihod/core/images/photo_store.dart';
import 'package:moy_prihod/core/images/photo_store_io.dart';

class MemoryStore implements PhotoStore {
  final files = <String, Uint8List>{};
  bool unavailable = false;
  @override
  Future<Uint8List?> read(String key) async {
    if (unavailable) throw StateError('storage unavailable');
    return files[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (unavailable) throw StateError('quota');
    files[key] = bytes;
  }

  @override
  Future<void> remove(String key) async {
    files.remove(key);
  }

  @override
  Future<void> clear() async => files.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one download and decode; reopening uses persisted bytes without network',
    () async {
      final store = MemoryStore();
      final cache = PhotoCache(store: store);
      var calls = 0;
      final pending = Completer<List<int>>();
      Future<List<int>> fetch() {
        calls++;
        return pending.future;
      }

      final a = cache.load('immutable/photo-1', fetch);
      final b = cache.load('immutable/photo-1', fetch);
      pending.complete([1, 2, 3]);
      expect(await a, same(await b));
      expect(calls, 1);
      await cache.flush();
      cache.dispose();
      final reopened = PhotoCache(store: store);
      addTearDown(reopened.dispose);
      final image = await reopened.load(
        'immutable/photo-1',
        () => throw StateError('unexpected network'),
      );
      expect(image.bytes, [1, 2, 3]);
      await reopened.remove('immutable/photo-1');
      expect(store.files, isEmpty);
    },
  );

  test('storage failure leaves successful image usable', () async {
    final cache = PhotoCache(store: MemoryStore()..unavailable = true);
    addTearDown(cache.dispose);
    final image = await cache.load('photo', () async => [4, 5, 6]);
    await cache.flush();
    expect(image.bytes, [4, 5, 6]);
    expect(cache.peek('photo'), same(image));
  });

  test(
    'visible work gets next free slot and parallel downloads stay bounded',
    () async {
      final queue = PhotoLoadQueue(concurrency: 1);
      final started = <String>[];
      final first = Completer<int>();
      final a = queue.run(() {
        started.add('first');
        return first.future;
      });
      final b = queue.run(() async {
        started.add('offscreen');
        return 2;
      });
      final c = queue.run(() async {
        started.add('visible');
        return 3;
      }, priority: 3);
      expect(started, ['first']);
      first.complete(1);
      expect(await a, 1);
      expect(await c, 3);
      expect(await b, 2);
      expect(started, ['first', 'visible', 'offscreen']);
    },
  );

  test(
    'native cache survives restart, isolates accounts and bounds its entry count',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mellon-photo-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final a = FilePhotoStore(
        photoCacheHash('account-a'),
        directory: directory,
      );
      final b = FilePhotoStore(
        photoCacheHash('account-b'),
        directory: directory,
      );
      await a.write('same-path', Uint8List.fromList([7, 8]));
      expect(await b.read('same-path'), isNull);
      final reopened = FilePhotoStore(
        photoCacheHash('account-a'),
        directory: directory,
      );
      expect(await reopened.read('same-path'), [7, 8]);
      for (var i = 0; i < photoStoreMaxEntries + 2; i++) {
        await a.write('photo-$i', Uint8List.fromList([i]));
      }
      final folder = Directory(
        '${directory.path}/mellon-photos-v1/${photoCacheHash("account-a")}',
      );
      expect(await folder.list().length, photoStoreMaxEntries);
      await a.clear();
      expect(await a.read('same-path'), isNull);
    },
  );
}
