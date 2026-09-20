import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'photo_store.dart';

final photoLoadQueueProvider = Provider<PhotoLoadQueue>(
  (ref) => PhotoLoadQueue(),
);

class _PhotoJob {
  _PhotoJob(this.run, this.priority);
  final Future<void> Function() run;
  final int priority;
}

class PhotoLoadQueue {
  PhotoLoadQueue({this.concurrency = 2});
  final int concurrency;
  final _jobs = <_PhotoJob>[];
  int _running = 0;
  Future<T> run<T>(Future<T> Function() task, {int priority = 0}) {
    final done = Completer<T>();
    _jobs.add(
      _PhotoJob(() async {
        try {
          done.complete(await task());
        } catch (error, stack) {
          done.completeError(error, stack);
        }
      }, priority),
    );
    _drain();
    return done.future;
  }

  void _drain() {
    while (_running < concurrency && _jobs.isNotEmpty) {
      var selected = 0;
      for (var i = 1; i < _jobs.length; i++) {
        if (_jobs[i].priority > _jobs[selected].priority) selected = i;
      }
      final job = _jobs.removeAt(selected);
      _running++;
      unawaited(
        job.run().whenComplete(() {
          _running--;
          _drain();
        }),
      );
    }
  }
}

class PhotoCache {
  PhotoCache({
    this.maximumBytes = 12 * 1024 * 1024,
    this.maximumEntries = 24,
    this.ttl = photoStoreLifetime,
    DateTime Function()? now,
    this.store,
    PhotoLoadQueue? queue,
    this.prepare,
  }) : _now = now ?? DateTime.now,
       _queue = queue ?? PhotoLoadQueue();
  final int maximumBytes, maximumEntries;
  final Duration ttl;
  final DateTime Function() _now;
  final PhotoStore? store;
  final PhotoLoadQueue _queue;
  final Future<Uint8List> Function(Uint8List)? prepare;
  final _images =
      LinkedHashMap<String, ({MemoryImage image, DateTime loaded})>();
  final _pending = <String, Future<MemoryImage>>{};
  Future<void> _writes = Future.value();
  bool _disposed = false;
  int _bytes = 0;

  MemoryImage? peek(String key) {
    final entry = _images.remove(key);
    if (entry == null) return null;
    if (_now().difference(entry.loaded) >= ttl) {
      _bytes -= entry.image.bytes.length;
      unawaited(entry.image.evict());
      return null;
    }
    _images[key] = entry;
    return entry.image;
  }

  MemoryImage put(String key, MemoryImage image) {
    if (_disposed) return image;
    final old = _images.remove(key);
    if (old != null) {
      _bytes -= old.image.bytes.length;
      if (!identical(old.image, image)) unawaited(old.image.evict());
    }
    if (image.bytes.length > maximumBytes) return image;
    _images[key] = (image: image, loaded: _now());
    _bytes += image.bytes.length;
    while (_bytes > maximumBytes || _images.length > maximumEntries) {
      final removed = _images.remove(_images.keys.first)!;
      _bytes -= removed.image.bytes.length;
      unawaited(removed.image.evict());
    }
    return image;
  }

  Future<MemoryImage> load(
    String key,
    Future<List<int>> Function() fetch, {
    int priority = 0,
  }) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);
    return _pending.putIfAbsent(key, () async {
      try {
        Uint8List? local;
        if (store != null) {
          try {
            local = await store!
                .read(key)
                .timeout(const Duration(milliseconds: 180));
          } on Object {
            /* A slow/unavailable disk must not delay the first network load. */
          }
        }
        if (local != null) return put(key, MemoryImage(local));
        final bytes = await _queue.run(() async {
          if (_disposed) throw StateError('Photo cache closed');
          final raw = await fetch().timeout(const Duration(seconds: 20));
          final data = raw is Uint8List ? raw : Uint8List.fromList(raw);
          return prepare == null ? data : await prepare!(data);
        }, priority: priority);
        final image = put(key, MemoryImage(bytes));
        if (!_disposed && store != null) {
          _writes = _writes
              .then((_) async {
                if (!_disposed) await store!.write(key, bytes);
              })
              .catchError((Object _) {
                /* Quota/full disk must not hide an image. */
              });
        }
        return image;
      } finally {
        unawaited(_pending.remove(key));
      }
    });
  }

  void prefetch(
    String key,
    Future<List<int>> Function() fetch, {
    int priority = 1,
  }) {
    unawaited(
      load(
        key,
        fetch,
        priority: priority,
      ).then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
  }

  Future<void> remove(String key) async {
    final old = _images.remove(key);
    if (old != null) {
      _bytes -= old.image.bytes.length;
      await old.image.evict();
    }
    try {
      await _writes;
      await store?.remove(key);
    } on Object {
      /* optional cache */
    }
  }

  Future<void> flush() => _writes;
  void dispose() {
    _disposed = true;
    for (final entry in _images.values) {
      unawaited(entry.image.evict());
    }
    _images.clear();
    _pending.clear();
    _bytes = 0;
  }
}
