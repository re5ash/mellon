import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_photo.dart';
import 'package:moy_prihod/features/community/stories/story_avatar.dart';
import 'package:moy_prihod/features/community/stories/story_composer.dart';
import 'package:moy_prihod/features/community/stories/story_repository.dart';
import 'package:moy_prihod/features/community/stories/story_viewer.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'club_photo_loading_test.dart' show pixel;

ClubStory story(String id, {bool video = true}) => ClubStory(
  id: id,
  club: 'club-a',
  path: '$id.${video ? 'mp4' : 'png'}',
  mime: video ? 'video/mp4' : 'image/png',
  createdAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
  durationMs: video ? 10000 : null,
);

class Stories implements ClubStoryRepository {
  final values = <ClubStory>[];
  final attempts = <String>[];
  bool fail = false, denied = false;
  int cleaned = 0;
  Completer<void>? pending;
  @override
  Future<List<ClubStory>> list(String club) async {
    if (denied) throw StateError('forbidden');
    return [...values];
  }

  @override
  Future<String> url(ClubStory story) async =>
      'https://example.test/${story.path}';
  @override
  Future<void> cleanup(String club, String actor) async {
    cleaned++;
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
    attempts.add(id);
    await pending?.future;
    if (fail) {
      fail = false;
      throw StateError('network');
    }
    final result = story(id, video: mime.startsWith('video/'));
    values.add(result);
    return result;
  }
}

class Picker extends ClubStoryPicker {
  bool? selected;
  bool cancel = false;
  @override
  Future<PickedStory?> pick(bool video) async {
    selected = video;
    if (cancel) return null;
    return PickedStory(
      XFile.fromData(
        pixel,
        name: video ? 'sample.mp4' : 'sample.png',
        path: video ? '/sample.mp4' : null,
      ),
      video,
      video ? 'video/mp4' : 'image/png',
      video ? 'mp4' : 'png',
    );
  }
}

class Videos extends VideoPlayerPlatform {
  int seq = 0, disposed = 0, paused = 0;
  Duration duration = const Duration(seconds: 10);
  final streams = <int, StreamController<VideoEvent>>{};
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = seq++;
    // The player owns this stream and closes it in dispose(playerId).
    // ignore: close_sinks
    final stream = StreamController<VideoEvent>();
    streams[id] = stream;
    stream.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(640, 360),
        duration: duration,
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
    await streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {
    paused++;
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool value,
  ) async {}
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black, key: ValueKey('video-surface'));
}

Future<ProviderContainer> mount(
  WidgetTester tester,
  Stories repo,
  Picker picker, {
  bool edit = true,
  Stream<AppUser?>? auth,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => auth ?? Stream.value(const AppUser('admin')),
        ),
        clubStoryRepositoryProvider.overrideWithValue(repo),
        clubStoryPickerProvider.overrideWithValue(picker),
        clubStoriesProvider('club-a').overrideWith((ref) async {
          ref.watch(authUserProvider);
          return repo.list('club-a');
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 152,
              child: ClubStoryAvatar(
                club: 'club-a',
                enabled: true,
                onEdit: edit ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
    tester.element(find.byType(ClubStoryAvatar)),
  );
}

Future<void> add(WidgetTester tester, bool video) async {
  await tester.tap(find.byKey(const ValueKey('club-photo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-club-story')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(video ? 'Видео' : 'Фото'));
  await tester.pumpAndSettle();
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Опубликовать');
    if (button.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(button).onPressed != null)
      break;
  }
}

void main() {
  late Videos videos;
  setUp(() {
    videos = Videos();
    VideoPlayerPlatform.instance = videos;
  });
  testWidgets(
    'circle has no background photograph; tap reveals only pencil and plus without resizing',
    (tester) async {
      await mount(tester, Stories(), Picker());
      final photo = find.byType(ClubPhoto);
      final rect = tester.getRect(photo);
      expect(find.byType(ClipOval), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Ещё'), findsNothing);
      expect(
        find.byKey(const ValueKey('add-club-story')).hitTestable(),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('club-photo')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('add-club-story')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('edit-club-photo')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.getRect(photo), rect);
    },
  );
  testWidgets('member can view stories but cannot add or edit', (tester) async {
    final repo = Stories()..values.add(story('one'));
    await mount(tester, repo, Picker(), edit: false);
    expect(find.byKey(const ValueKey('add-club-story')), findsNothing);
    expect(find.byKey(const ValueKey('edit-club-photo')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('club-photo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StoryViewer), findsOneWidget);
    expect(find.byType(ClubPhoto), findsNothing);
    await tester.tap(find.byTooltip('Закрыть истории'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    expect(videos.disposed, 1);
  });
  testWidgets(
    'photo preview publishes once, retry uses the same id and ring appears',
    (tester) async {
      final repo = Stories()..fail = true;
      final picker = Picker();
      await mount(tester, repo, picker);
      await add(tester, false);
      expect(picker.selected, false);
      expect(find.byType(StoryComposer), findsOneWidget);
      final publish = find.widgetWithText(FilledButton, 'Опубликовать');
      expect(tester.widget<FilledButton>(publish).onPressed, isNotNull);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(find.textContaining('Не удалось опубликовать'), findsOneWidget);
      repo.pending = Completer<void>();
      await tester.tap(publish);
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Публикуем…'),
            )
            .onPressed,
        isNull,
      );
      repo.pending!.complete();
      await tester.pumpAndSettle();
      expect(repo.attempts.length, 2);
      expect(repo.attempts.toSet().length, 1);
      expect(tester.widget<ClubPhoto>(find.byType(ClubPhoto)).hasStories, true);
      expect(find.byType(StoryComposer), findsNothing);
    },
  );
  testWidgets(
    'video choice has playable preview and publishes video; long video cannot publish',
    (tester) async {
      final repo = Stories();
      final picker = Picker();
      await mount(tester, repo, picker);
      await add(tester, true);
      expect(picker.selected, true);
      expect(find.byKey(const ValueKey('video-surface')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Опубликовать'));
      await tester.pumpAndSettle();
      expect(repo.values.single.video, true);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      expect(videos.disposed, 1);
      videos.duration = const Duration(seconds: 61);
      await add(tester, true);
      expect(find.textContaining('Длина видео'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Опубликовать'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'viewer side taps switch, cancelled swipe restores position, swipe down closes',
    (tester) async {
      final repo = Stories()..values.addAll([story('one'), story('two')]);
      await mount(tester, repo, Picker(), edit: false);
      await tester.tap(find.byKey(const ValueKey('club-photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<StoryMedia>(find.byType(StoryMedia)).story.id,
        'one',
      );
      final surface = find.byKey(const ValueKey('story-gesture-surface'));
      final rect = tester.getRect(surface);
      await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<StoryMedia>(find.byType(StoryMedia)).story.id,
        'two',
      );
      await tester.tapAt(Offset(20, rect.center.dy));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<StoryMedia>(find.byType(StoryMedia)).story.id,
        'one',
      );
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(const Offset(0, 30));
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump();
      expect(tester.getRect(surface), rect);
      await tester.drag(surface, const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(find.byType(StoryViewer), findsNothing);
    },
  );
  testWidgets(
    'revocation hides active media and prevents access to captured initial stories',
    (tester) async {
      final repo = Stories()..values.add(story('one'));
      final container = await mount(tester, repo, Picker(), edit: false);
      await tester.tap(find.byKey(const ValueKey('club-photo')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      repo.denied = true;
      container.invalidate(clubStoriesProvider('club-a'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(StoryMedia), findsNothing);
      expect(find.text('История больше недоступна.'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть истории'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
