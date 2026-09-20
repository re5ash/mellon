import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../core/id/new_uuid.dart';
import '../../auth/application/auth_providers.dart';
import '../club_photo_crop.dart';
import 'story_repository.dart';
import 'story_video_controller.dart';

class PickedStory {
  const PickedStory(this.file, this.video, this.mime, this.extension);
  final XFile file;
  final bool video;
  final String mime, extension;
}

class ClubStoryPicker {
  const ClubStoryPicker();
  Future<PickedStory?> pick(bool video) async {
    final file = await openFile(
      acceptedTypeGroups: [
        video
            ? const XTypeGroup(
                label: 'Видео',
                extensions: ['mp4', 'webm', 'mov', 'm4v'],
                mimeTypes: ['video/mp4', 'video/webm', 'video/quicktime'],
                uniformTypeIdentifiers: ['public.movie'],
              )
            : const XTypeGroup(
                label: 'Фото',
                extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'],
                mimeTypes: ['image/*'],
                uniformTypeIdentifiers: ['public.image'],
              ),
      ],
    );
    if (file == null) return null;
    if (await file.length() > 50 * 1024 * 1024)
      throw StateError('Выберите файл до 50 МБ.');
    final ext = file.name.split('.').last.toLowerCase();
    if (video && !{'mp4', 'webm', 'mov', 'm4v'}.contains(ext))
      throw StateError('Выберите видео MP4, MOV или WebM.');
    return PickedStory(
      file,
      video,
      video
          ? (ext == 'webm'
                ? 'video/webm'
                : ext == 'mov'
                ? 'video/quicktime'
                : 'video/mp4')
          : 'image/png',
      video
          ? (ext == 'webm'
                ? 'webm'
                : ext == 'mov'
                ? 'mov'
                : 'mp4')
          : 'png',
    );
  }
}

final clubStoryPickerProvider = Provider<ClubStoryPicker>(
  (ref) => const ClubStoryPicker(),
);

Future<ClubStory?> openStoryComposer(
  BuildContext context,
  WidgetRef ref,
  String club,
  String actor,
) async {
  final video = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_outlined),
            title: const Text('Фото'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Видео'),
            subtitle: const Text('До 60 секунд, до 50 МБ'),
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ),
  );
  if (video == null || !context.mounted) return null;
  try {
    final picked = await ref.read(clubStoryPickerProvider).pick(video);
    if (picked == null ||
        !context.mounted ||
        ref.read(authUserProvider).asData?.value?.id != actor)
      return null;
    return await Navigator.of(context, rootNavigator: true).push<ClubStory>(
      PageRouteBuilder<ClubStory>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, animation, secondary) =>
            StoryComposer(club: club, actor: actor, picked: picked),
        transitionsBuilder: (_, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  } on Object {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось выбрать файл. Используйте фото или видео до 50 МБ.',
          ),
        ),
      );
    return null;
  }
}

class StoryComposer extends ConsumerStatefulWidget {
  const StoryComposer({
    required this.club,
    required this.actor,
    required this.picked,
    super.key,
  });
  final String club, actor;
  final PickedStory picked;
  @override
  ConsumerState<StoryComposer> createState() => _StoryComposerState();
}

class _StoryComposerState extends ConsumerState<StoryComposer>
    with WidgetsBindingObserver {
  final _id = newUuid();
  VideoPlayerController? _video;
  Uint8List? _bytes;
  bool _ready = false, _busy = false, _muted = true;
  String? _error;
  bool get _same =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_prepare());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_video?.pause());
  }

  Future<void> _prepare() async {
    try {
      if (widget.picked.video) {
        final controller = localStoryVideo(widget.picked.file.path);
        _video = controller;
        await controller.initialize().timeout(const Duration(seconds: 20));
        if (!mounted || !_same) return;
        final duration = controller.value.duration.inMilliseconds;
        if (duration <= 0 || duration > 60000)
          throw StateError('Длина видео должна быть от 1 до 60 секунд.');
        await controller.setLooping(true);
        await controller.setVolume(0);
        await controller.play();
      } else {
        final raw = await widget.picked.file.readAsBytes();
        final image = await decodeClubPhoto(raw);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Не удалось открыть фото.');
          _bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
        if (_bytes!.length > 50 * 1024 * 1024)
          throw StateError('Фотография слишком большая.');
        if (!mounted || !_same) return;
        await precacheImage(MemoryImage(_bytes!), context);
      }
      if (_same) setState(() => _ready = true);
    } on Object catch (error) {
      if (mounted)
        setState(
          () => _error = error is StateError
              ? '${error.message}'
              : 'Файл не удалось открыть. Попробуйте другое фото или видео MP4.',
        );
    }
  }

  Future<void> _publish() async {
    if (!_same || _busy || !_ready) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _bytes ??= await widget.picked.file.readAsBytes();
      if (!mounted || !_same) return;
      final repository = ref.read(clubStoryRepositoryProvider);
      final story = await repository
          .publish(
            id: _id,
            club: widget.club,
            actor: widget.actor,
            bytes: _bytes!,
            mime: widget.picked.mime,
            extension: widget.picked.extension,
            durationMs: _video?.value.duration.inMilliseconds,
          )
          .timeout(const Duration(minutes: 3));
      if (!mounted || !_same) return;
      ref.invalidate(clubStoriesProvider(widget.club));
      // Storage removes the physical objects; SQL only removes their records.
      unawaited(
        repository
            .cleanup(widget.club, widget.actor)
            .timeout(const Duration(seconds: 30))
            .catchError((Object _) {}),
      );
      Navigator.pop(context, story);
    } on Object {
      if (_same)
        setState(
          () => _error =
              'Не удалось опубликовать. Проверьте связь и попробуйте ещё раз.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final same = ref.watch(authUserProvider).asData?.value?.id == widget.actor;
    ref.listen(authUserProvider, (_, next) {
      if (next.asData?.value?.id != widget.actor) unawaited(_video?.pause());
    });
    final video = _video;
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: PopScope(
        canPop: !_busy,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: const Text('Предпросмотр истории'),
            leading: IconButton(
              tooltip: 'Закрыть',
              onPressed: _busy ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: !same
                        ? const Text('Аккаунт изменился.')
                        : !_ready
                        ? Text(
                            _error ?? 'Готовим предпросмотр…',
                            textAlign: TextAlign.center,
                          )
                        : video == null
                        ? Image.memory(
                            _bytes!,
                            fit: BoxFit.contain,
                            gaplessPlayback: false,
                          )
                        : AspectRatio(
                            aspectRatio: video.value.aspectRatio,
                            child: VideoPlayer(video),
                          ),
                  ),
                ),
                if (_ready && _error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (video != null)
                        IconButton(
                          tooltip: _muted ? 'Включить звук' : 'Выключить звук',
                          onPressed: !same
                              ? null
                              : () {
                                  setState(() => _muted = !_muted);
                                  unawaited(video.setVolume(_muted ? 0 : 1));
                                },
                          icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                          ),
                        ),
                      Expanded(
                        child: FilledButton(
                          onPressed: same && _ready && !_busy ? _publish : null,
                          child: Text(_busy ? 'Публикуем…' : 'Опубликовать'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
