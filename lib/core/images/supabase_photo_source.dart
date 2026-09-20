import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

final _sources = Expando<SupabasePhotoSource>();
SupabasePhotoSource supabasePhotoSource(SupabaseClient client) =>
    _sources[client] ??= SupabasePhotoSource(client);

/// Direct authenticated downloads avoid the signed-URL round trip and token
/// changes in Flutter's image key. Storage RLS still authorizes each download.
class SupabasePhotoSource {
  SupabasePhotoSource(this.client);
  final SupabaseClient client;
  bool? _transforms;
  Completer<void>? _probe;
  Future<Uint8List> download(
    String bucket,
    String path, {
    required int edge,
  }) async {
    final waiting = _probe;
    if (waiting != null) await waiting.future;
    if (_transforms == false) return client.storage.from(bucket).download(path);
    final probing = _transforms == null;
    if (probing) _probe = Completer<void>();
    try {
      final bytes = await client.storage
          .from(bucket)
          .download(
            path,
            transform: TransformOptions(
              width: edge,
              height: edge,
              resize: ResizeMode.contain,
              quality: 80,
            ),
          )
          .timeout(const Duration(seconds: 12));
      _transforms = true;
      return bytes;
    } on StorageException catch (error) {
      // Some existing Supabase plans do not offer transformations. Never turn
      // an authorization failure into an unauthenticated/public fallback.
      if (!{'400', '404', '501'}.contains(error.statusCode)) rethrow;
      _transforms = false;
      return client.storage.from(bucket).download(path);
    } finally {
      if (probing) {
        _probe?.complete();
        _probe = null;
      }
    }
  }
}
