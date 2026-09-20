import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/community/club_photo.dart';
import 'package:moy_prihod/features/community/club_photo_cache.dart';
import 'package:moy_prihod/features/community/club_photo_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

final pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN49eHzfwAJYgPNIyeaqwAAAABJRU5ErkJggg==',
);

class PhotoRepository implements ClubPhotoRepository {
  final requests = <String>[];
  final pending = <String, Completer<Uint8List>>{};
  @override
  Future<Uint8List> download(String path) {
    requests.add(path);
    return pending.putIfAbsent(path, Completer<Uint8List>.new).future;
  }

  @override
  Future<String> url(String path) =>
      throw StateError('A signed URL should not be requested');
  @override
  Future<JsonRow> save({
    required String club,
    required String actor,
    required String path,
    required int revision,
    required Uint8List bytes,
  }) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'photo cache coalesces requests, respects its bounds and ignores a late result after logout',
    () async {
      final cache = ClubPhotoCache(maximumEntries: 1);
      final pending = Completer<List<int>>();
      final first = cache.load('one', () => pending.future);
      final second = cache.load('one', () => throw StateError('duplicate'));
      pending.complete(pixel);
      expect(await first, same(await second));
      final image = cache.peek('one');
      expect(image, isNotNull);
      cache.put('two', MemoryImage(pixel));
      expect(cache.peek('one'), isNull);
      final late = Completer<List<int>>();
      final download = cache.load('late', () => late.future);
      cache.dispose();
      late.complete(pixel);
      await download;
      expect(cache.peek('late'), isNull);
      expect(cache.peek('two'), isNull);
    },
  );

  test('photo cache refreshes expired images', () async {
    var now = DateTime(2026, 9, 13);
    final cache = ClubPhotoCache(
      now: () => now,
      ttl: const Duration(minutes: 1),
    );
    addTearDown(cache.dispose);
    cache.put('photo', MemoryImage(pixel));
    now = now.add(const Duration(minutes: 2));
    expect(cache.peek('photo'), isNull);
    var calls = 0;
    await cache.load('photo', () async {
      calls++;
      return pixel;
    });
    expect(calls, 1);
  });

  testWidgets(
    'opening and changing a custom photo never flashes the built-in photograph; returning reuses bytes',
    (tester) async {
      final repo = PhotoRepository(), cache = ClubPhotoCache();
      addTearDown(cache.dispose);
      var path = 'club/photo-1';
      var visible = true;
      late StateSetter change;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clubPhotoRepositoryProvider.overrideWithValue(repo),
            clubPhotoCacheProvider.overrideWithValue(cache),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return visible
                      ? SizedBox(width: 310, child: ClubPhoto(path: path))
                      : const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ClubPhotoPlaceholder), findsNothing);
      expect(find.byType(ClubPhotoLoading), findsOneWidget);
      repo.pending[path]!.complete(pixel);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final first = tester.widget<Image>(find.byType(Image)).image;
      change(() => visible = false);
      await tester.pumpAndSettle();
      change(() => visible = true);
      await tester.pump();
      expect(find.byType(ClubPhotoPlaceholder), findsNothing);
      expect(tester.widget<Image>(find.byType(Image)).image, same(first));
      expect(repo.requests, ['club/photo-1']);
      change(() => path = 'club/photo-2');
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(ClubPhotoPlaceholder), findsNothing);
      expect(find.byType(ClubPhotoLoading), findsOneWidget);
      repo.pending[path]!.complete(Uint8List.fromList(pixel));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isNot(same(first)),
      );
      expect(repo.requests, ['club/photo-1', 'club/photo-2']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
