import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../core/backend/backend_provider.dart';
import '../../auth/application/auth_providers.dart';

class ClubStory {
  const ClubStory({
    required this.id,
    required this.club,
    required this.path,
    required this.mime,
    required this.createdAt,
    required this.expiresAt,
    this.durationMs,
  });
  final String id, club, path, mime;
  final DateTime createdAt, expiresAt;
  final int? durationMs;
  bool get video => mime.startsWith('video/');
  factory ClubStory.fromJson(Map<String, dynamic> row) => ClubStory(
    id: row['id'] as String,
    club: row['youth_id'] as String,
    path: row['media_path'] as String,
    mime: row['mime_type'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
    expiresAt: DateTime.parse(row['expires_at'] as String),
    durationMs: (row['duration_ms'] as num?)?.toInt(),
  );
}

abstract interface class ClubStoryRepository {
  Future<List<ClubStory>> list(String club);
  Future<String> url(ClubStory story);
  Future<ClubStory> publish({
    required String id,
    required String club,
    required String actor,
    required Uint8List bytes,
    required String mime,
    required String extension,
    int? durationMs,
  });
  Future<void> cleanup(String club, String actor);
}

final clubStoryRepositoryProvider = Provider<ClubStoryRepository>((ref) {
  ref.watch(authUserProvider.select((v) => v.asData?.value?.id));
  return SupabaseClubStoryRepository(ref.watch(backendProvider));
});
final clubStoriesProvider = FutureProvider.autoDispose
    .family<List<ClubStory>, String>((ref, club) async {
      final actor = ref.watch(
        authUserProvider.select((v) => v.asData?.value?.id),
      );
      ref.watch(
        accountAccessProvider.select((v) => v.asData?.value.restrictedGuest),
      );
      if (actor == null) return [];
      final stories = await ref.watch(clubStoryRepositoryProvider).list(club);
      if (!ref.mounted) return [];
      final now = DateTime.now();
      final active = stories.where((s) => s.expiresAt.isAfter(now)).toList();
      if (active.isNotEmpty) {
        final expiry = active
            .map((s) => s.expiresAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final timer = Timer(
          expiry.difference(now) + const Duration(milliseconds: 100),
          ref.invalidateSelf,
        );
        ref.onDispose(timer.cancel);
      }
      return active;
    }, retry: (_, error) => null);

class SupabaseClubStoryRepository implements ClubStoryRepository {
  SupabaseClubStoryRepository(this.client);
  final SupabaseClient client;
  final _urls = <String, ({DateTime until, Future<String> value})>{};
  void _actor(String actor) {
    if (client.auth.currentUser?.id != actor)
      throw StateError('Аккаунт изменился.');
  }

  @override
  Future<List<ClubStory>> list(String club) async {
    final rows = await client
        .from('club_stories')
        .select()
        .eq('youth_id', club)
        .order('created_at')
        .order('id')
        .timeout(const Duration(seconds: 20));
    return rows.map(ClubStory.fromJson).toList();
  }

  @override
  Future<String> url(ClubStory story) {
    final cached = _urls[story.path];
    final now = DateTime.now();
    if (cached != null && cached.until.isAfter(now)) return cached.value;
    _urls.removeWhere((key, value) => !value.until.isAfter(now));
    if (_urls.length >= 32) _urls.remove(_urls.keys.first);
    final value = client.storage
        .from('club-stories')
        .createSignedUrl(story.path, 300);
    _urls[story.path] = (
      until: now.add(const Duration(minutes: 3)),
      value: value,
    );
    return value.catchError((Object error) {
      _urls.remove(story.path);
      throw error;
    });
  }

  @override
  Future<ClubStory> publish({
    required String id,
    required String club,
    required String actor,
    required Uint8List bytes,
    required String mime,
    required String extension,
    int? durationMs,
  }) async {
    _actor(actor);
    final path = '$club/$actor/$id.$extension';
    try {
      await client.storage
          .from('club-stories')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } on StorageException catch (error) {
      if (error.statusCode != '409') rethrow;
    }
    _actor(actor);
    final row = await client.rpc<Map<String, dynamic>>(
      'publish_club_story',
      params: {
        'p_id': id,
        'p_youth': club,
        'p_path': path,
        'p_mime': mime,
        'p_bytes': bytes.length,
        'p_duration': durationMs,
        'p_expected_user': actor,
      },
    );
    return ClubStory.fromJson(row);
  }

  @override
  Future<void> cleanup(String club, String actor) async {
    _actor(actor);
    final rows = await client.rpc<List<dynamic>>(
      'expired_club_stories',
      params: {'p_youth': club},
    );
    for (final value in rows) {
      _actor(actor);
      final row = value as Map<String, dynamic>;
      await client.storage.from('club-stories').remove([
        row['media_path'] as String,
      ]);
      _actor(actor);
      await client.rpc<void>(
        'remove_club_story',
        params: {'p_id': row['id'], 'p_expected_user': actor},
      );
    }
  }
}
