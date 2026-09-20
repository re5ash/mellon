import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../auth/application/auth_providers.dart';
import 'story_repository.dart';

Future<void> openStoryViewer(
  BuildContext context,
  String club,
  List<ClubStory> stories,
) => Navigator.of(context, rootNavigator: true).push<void>(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, animation, secondary) =>
        StoryViewer(club: club, initial: stories),
    transitionsBuilder: (_, animation, secondary, child) =>
        FadeTransition(opacity: animation, child: child),
  ),
);

class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({required this.club, required this.initial, super.key});
  final String club;
  final List<ClubStory> initial;
  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _progress;
  late final String? _actor;
  late String? _selected;
  String? _readyId;
  bool _paused = false, _muted = true, _dragging = false, _closed = false;
  double _dy = 0;
  List<ClubStory> _items = [];
  @override
  void initState() {
    super.initState();
    _actor = ref.read(authUserProvider).asData?.value?.id;
    _selected = widget.initial.firstOrNull?.id;
    _progress =
        AnimationController(vsync: this, duration: const Duration(seconds: 5))
          ..addStatusListener((s) {
            if (s == AnimationStatus.completed) _step(1);
          });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progress.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _paused = state != AppLifecycleState.resumed);
    if (_paused)
      _progress.stop();
    else if (_readyId == _selected)
      _progress.forward();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _progress.stop();
    Navigator.of(context).pop();
  }

  void _step(int delta) {
    if (_items.isEmpty || _closed) return;
    final current = _items.indexWhere((s) => s.id == _selected);
    final index = current + delta;
    if (index >= _items.length) {
      _close();
      return;
    }
    if (index < 0) {
      _progress.forward(from: 0);
      return;
    }
    _progress.reset();
    _readyId = null;
    setState(() {
      _selected = _items[index].id;
      _paused = false;
    });
  }

  Future<void> _prefetchNext() async {
    final i = _items.indexWhere((s) => s.id == _selected);
    if (i < 0 || i + 1 >= _items.length || _items[i + 1].video) return;
    try {
      final url = await ref
          .read(clubStoryRepositoryProvider)
          .url(_items[i + 1]);
      if (mounted)
        await precacheImage(NetworkImage(url), context, onError: (_, stack) {});
    } on Object {
      /* The current story remains usable if prefetch fails. */
    }
  }

  void _ready(Duration duration) {
    if (!mounted || _closed) return;
    unawaited(_prefetchNext());
    _readyId = _selected;
    _progress.duration = duration;
    if (!_paused && !_dragging) _progress.forward(from: 0);
  }

  void _playback(bool playing) {
    if (!mounted || _closed) return;
    if (playing && !_paused && !_dragging)
      _progress.forward();
    else
      _progress.stop();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(clubStoriesProvider(widget.club));
    final actor = ref.watch(authUserProvider).asData?.value?.id;
    final allowed = actor == _actor && actor != null && !data.hasError;
    _items = allowed
        ? (data.asData?.value ?? widget.initial)
              .where((s) => s.expiresAt.isAfter(DateTime.now()))
              .toList()
        : [];
    var index = _items.indexWhere((s) => s.id == _selected);
    if (index < 0 && _items.isNotEmpty) {
      index = 0;
      _selected = _items.first.id;
      _progress.reset();
    }
    final story = index < 0 ? null : _items[index];
    if (story == null) _progress.stop();
    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: AnimatedContainer(
          duration: _dragging
              ? Duration.zero
              : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _dy, 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                key: const ValueKey('story-gesture-surface'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  if (story != null)
                    _step(
                      d.localPosition.dx <
                              MediaQuery.sizeOf(context).width * .35
                          ? -1
                          : 1,
                    );
                },
                onLongPressStart: (_) {
                  setState(() => _paused = true);
                  _progress.stop();
                },
                onLongPressEnd: (_) {
                  setState(() => _paused = false);
                  if (story != null && _readyId == _selected)
                    _progress.forward();
                },
                onVerticalDragStart: (_) {
                  _progress.stop();
                  setState(() => _dragging = true);
                },
                onVerticalDragUpdate: (d) => setState(
                  () => _dy = (_dy + d.delta.dy).clamp(
                    0,
                    MediaQuery.sizeOf(context).height,
                  ),
                ),
                onVerticalDragCancel: () {
                  setState(() {
                    _dy = 0;
                    _dragging = false;
                  });
                  if (story != null && !_paused && _readyId == _selected)
                    _progress.forward();
                },
                onVerticalDragEnd: (d) {
                  if (_dy > 90 || d.primaryVelocity! > 800) {
                    _close();
                  } else {
                    setState(() {
                      _dy = 0;
                      _dragging = false;
                    });
                    if (story != null && !_paused && _readyId == _selected)
                      _progress.forward();
                  }
                },
                child: story == null
                    ? const Center(child: Text('История больше недоступна.'))
                    : StoryMedia(
                        key: ValueKey(story.id),
                        story: story,
                        paused: _paused || _dragging,
                        muted: _muted,
                        onReady: _ready,
                        onPlayback: _playback,
                        onComplete: () => _step(1),
                      ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (_, child) => Row(
                            children: [
                              for (var i = 0; i < _items.length; i++)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: LinearProgressIndicator(
                                      value: i < index
                                          ? 1
                                          : i == index
                                          ? _progress.value
                                          : 0,
                                      color: Colors.white,
                                      backgroundColor: Colors.white24,
                                      minHeight: 3,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Text(
                              'Истории клуба',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (story?.video == true)
                            IconButton(
                              tooltip: _muted
                                  ? 'Включить звук'
                                  : 'Выключить звук',
                              onPressed: () => setState(() => _muted = !_muted),
                              icon: Icon(
                                _muted ? Icons.volume_off : Icons.volume_up,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Закрыть истории',
                            onPressed: _close,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoryMedia extends ConsumerStatefulWidget {
  const StoryMedia({
    required this.story,
    required this.paused,
    required this.muted,
    required this.onReady,
    required this.onPlayback,
    required this.onComplete,
    super.key,
  });
  final ClubStory story;
  final bool paused, muted;
  final ValueChanged<Duration> onReady;
  final ValueChanged<bool> onPlayback;
  final VoidCallback onComplete;
  @override
  ConsumerState<StoryMedia> createState() => _StoryMediaState();
}

class _StoryMediaState extends ConsumerState<StoryMedia> {
  VideoPlayerController? _video;
  ImageProvider? _image;
  bool _loading = true, _error = false, _ended = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(StoryMedia old) {
    super.didUpdateWidget(old);
    if (old.paused != widget.paused || old.muted != widget.muted)
      unawaited(_sync());
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_video?.dispose());
    super.dispose();
  }

  Future<void> _sync() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    await video.setVolume(widget.muted ? 0 : 1);
    if (widget.paused) {
      await video.pause();
    } else {
      await video.play();
    }
  }

  void _status() {
    final value = _video?.value;
    if (value == null || !mounted) return;
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_ended) {
      _ended = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onComplete();
      });
    }
    if (value.hasError && !_error) {
      setState(() => _error = true);
      widget.onPlayback(false);
      return;
    }
    widget.onPlayback(value.isPlaying && !value.isBuffering);
  }

  Future<void> _load() async {
    final ticket = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
      _ended = false;
    });
    try {
      final url = await ref
          .read(clubStoryRepositoryProvider)
          .url(widget.story)
          .timeout(const Duration(seconds: 15));
      if (!mounted || ticket != _generation) return;
      if (widget.story.video) {
        await _video?.dispose();
        final video = VideoPlayerController.networkUrl(
          Uri.parse(url),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        _video = video;
        await video.initialize().timeout(const Duration(seconds: 20));
        if (!mounted || ticket != _generation) return;
        video.addListener(_status);
        await _sync();
        widget.onReady(video.value.duration);
      } else {
        final image = NetworkImage(url);
        Object? failure;
        await precacheImage(
          image,
          context,
          onError: (error, stack) => failure = error,
        );
        if (failure != null) throw failure!;
        if (!mounted || ticket != _generation) return;
        _image = image;
        widget.onReady(const Duration(seconds: 5));
      }
      if (mounted) setState(() => _loading = false);
    } on Object {
      if (mounted && ticket == _generation)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error)
      return Center(
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Повторить загрузку'),
        ),
      );
    if (_loading)
      return const Center(
        child: Text(
          'Загружаем историю…',
          style: TextStyle(color: Colors.white70),
        ),
      );
    final video = _video;
    return Center(
      child: video == null
          ? Image(image: _image!, fit: BoxFit.contain, gaplessPlayback: false)
          : AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
    );
  }
}
