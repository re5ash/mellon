import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_store.dart';

PhotoStore createStore(String scope) => FilePhotoStore(scope);

class FilePhotoStore implements PhotoStore {
  FilePhotoStore(this.scope, {this.directory});
  final String scope;
  final Directory? directory;
  Future<Directory>? _pendingDirectory;
  Future<Directory> _directory() => _pendingDirectory ??= () async {
    final base = directory ?? await getApplicationCacheDirectory();
    return Directory(
      '${base.path}/mellon-photos-v1/$scope',
    ).create(recursive: true);
  }();
  Future<File> _file(String key) async =>
      File('${(await _directory()).path}/${photoCacheHash(key)}.bin');

  @override
  Future<Uint8List?> read(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (stat.size > photoStoreMaxBytes ||
        DateTime.now().difference(stat.modified) > photoStoreLifetime) {
      await file.delete();
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (bytes.length > photoStoreMaxBytes) return;
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
    final files = <({File file, FileStat stat})>[];
    await for (final entry in (await _directory()).list()) {
      if (entry is File && entry.path.endsWith('.bin'))
        files.add((file: entry, stat: await entry.stat()));
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    var total = files.fold<int>(0, (sum, item) => sum + item.stat.size);
    var count = files.length;
    for (final item in files) {
      if (total <= photoStoreMaxBytes &&
          count <= photoStoreMaxEntries &&
          DateTime.now().difference(item.stat.modified) <= photoStoreLifetime)
        break;
      await item.file.delete();
      total -= item.stat.size;
      count--;
    }
  }

  @override
  Future<void> remove(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    final dir = await _directory();
    if (await dir.exists()) await dir.delete(recursive: true);
    _pendingDirectory = null;
  }
}
