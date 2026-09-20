import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' as rendering show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../../core/errors/app_failure.dart';
import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/chat_surface.dart';
import '../../../design_system/theme_controller.dart';
import '../../auth/application/auth_providers.dart';
import '../../community/community_widgets.dart';
import '../application/chat_moderation.dart';
import '../application/chat_providers.dart';
import '../domain/chat.dart';
import '../domain/chat_interactions.dart';
import 'chat_dates.dart';
import 'message_interactions.dart';
import 'message_removal.dart';

class ModeratedTimeline extends ConsumerStatefulWidget {
  const ModeratedTimeline({
    required this.room,
    required this.actor,
    this.onRead,
    this.onReply,
    super.key,
  });
  final Future<void> Function(ChatMessage message)? onRead;
  final String room, actor;
  final ValueChanged<ChatMessage>? onReply;
  @override
  ConsumerState<ModeratedTimeline> createState() => _ModeratedTimelineState();
}

class _ModeratedTimelineState extends ConsumerState<ModeratedTimeline>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  bool _readScheduled = false, _reading = false, _foreground = true;
  bool _anchorPending = false;
  ChatMessage? _readMessage;
  final _keys = <String, GlobalKey<State<StatefulWidget>>>{};
  final _removed = <String>{};
  final _collapsed = <String>{};
  List<ChatMessage>? _window;
  String? _anchor, _highlight, _error;
  Map<String, dynamic>? _pin;
  List<Map<String, dynamic>> _pins = [];
  Map<String, List<ChatReaction>> _reactions = {};
  final _reacting = <String>{}, _newMessages = <String>{};
  bool _away = false,
      _refreshBusy = false,
      _refreshQueued = false,
      _refreshHistoryQueued = false,
      _returning = false;
  ChatMessage? _newest;
  Timer? _highlightTimer;
  bool get _interactive =>
      ref.read(chatModerationProvider) is ChatInteractionRepository;
  Duration get _jumpDuration => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);
  // Keep the interaction locked while a menu/dialog is open, but animate
  // progress only while a request is actually pending.
  bool _busy = false, _loading = false;
  int _generation = 0, _windowEpoch = 0;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  bool get _same =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _scroll.addListener(_onScroll);
    final repo = ref.read(chatModerationProvider);
    _subscription = repo
        .changes(widget.room)
        .listen(
          (_) {
            unawaited(_refresh());
          },
          onError: (Object e) {
            if (_same) setState(() => _error = userError(e));
          },
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _scheduleRead();
      ref.invalidate(chatAccessProvider(widget.room));
      ref.invalidate(chatMessagesProvider(widget.room));
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    _scheduleRead();
    if (!_same || !_scroll.hasClients) return;
    final away = !_returning && (_window != null || _scroll.offset > 100);
    if (_away != away || !away && _newMessages.isNotEmpty) {
      setState(() {
        _away = away;
        if (!away) _newMessages.clear();
      });
    }
  }

  void _goLatest() {
    if (!_same || _busy) return;
    setState(() {
      _generation++;
      _windowEpoch++;
      _window = null;
      _anchor = null;
      _highlight = null;
      _newMessages.clear();
      _away = false;
      _returning = true;
    });
    unawaited(_refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_same || !_scroll.hasClients) return;
      unawaited(
        _scroll
            .animateTo(
              0,
              duration: _jumpDuration == Duration.zero
                  ? const Duration(milliseconds: 1)
                  : _jumpDuration,
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (_same) {
                _returning = false;
                _onScroll();
              }
            }),
      );
    });
  }

  void _flash(String id) {
    _highlightTimer?.cancel();
    setState(() => _highlight = id);
    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (_same && _highlight == id) setState(() => _highlight = null);
    });
  }

  Future<void> _react(
    ChatMessage message,
    String emoji, {
    bool? selected,
  }) async {
    final Object repo = ref.read(chatModerationProvider);
    if (!_same ||
        repo is! ChatInteractionRepository ||
        !_reacting.add(message.id))
      return;
    final mine =
        _reactions[message.id]?.any((r) => r.emoji == emoji && r.mine) == true;
    try {
      await repo
          .react(
            widget.room,
            message.id,
            emoji,
            selected ?? !mine,
            widget.actor,
          )
          .timeout(const Duration(seconds: 20));
      if (_same) await _refresh();
    } on Object catch (error) {
      if (_same) setState(() => _error = userError(error));
    } finally {
      _reacting.remove(message.id);
    }
  }

  void _preserveReadingPosition() {
    if (_anchorPending ||
        _window != null ||
        !_scroll.hasClients ||
        _scroll.offset < 24 ||
        _scroll.position.isScrollingNotifier.value)
      return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
    String? anchor;
    double? top;
    for (final entry in _keys.entries) {
      final box = entry.value.currentContext?.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (bounds.overlaps(rect)) {
          anchor = entry.key;
          top = rect.top;
          break;
        }
      }
    }
    if (anchor == null) return;
    _anchorPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anchorPending = false;
      if (!mounted ||
          !_scroll.hasClients ||
          _scroll.position.isScrollingNotifier.value)
        return;
      final box = _keys[anchor]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final correction = top! - box.localToGlobal(Offset.zero).dy;
      if (correction.abs() <= .5) return;
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + correction)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  void _scheduleRead() {
    if (_readScheduled || widget.onRead == null || !_same) return;
    _readScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (_same) unawaited(_reportVisibleRead());
    });
  }

  bool _later(ChatMessage a, ChatMessage b) =>
      a.createdAt.isAfter(b.createdAt) ||
      (a.createdAt.isAtSameMomentAs(b.createdAt) && a.id.compareTo(b.id) > 0);

  Future<void> _reportVisibleRead() async {
    if (_reading ||
        !_same ||
        !_foreground ||
        widget.onRead == null ||
        ModalRoute.of(context)?.isCurrent != true ||
        !TickerMode.valuesOf(context).enabled)
      return;
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize)
      return;
    var bounds = (viewport.localToGlobal(Offset.zero) & viewport.size)
        .intersect(Offset.zero & MediaQuery.sizeOf(context));
    // The club's independently scrolling region may itself be partly off-screen.
    for (var parent = viewport.parent; parent != null; parent = parent.parent) {
      if (parent is RenderBox && parent.attached && parent.hasSize) {
        bounds = bounds.intersect(
          parent.localToGlobal(Offset.zero) & parent.size,
        );
      }
    }
    if (bounds.isEmpty) return;
    final rows =
        _window ??
        ref.read(chatMessagesProvider(widget.room)).asData?.value ??
        <ChatMessage>[];
    ChatMessage? latest;
    for (final message in rows) {
      if (message.deleted || _removed.contains(message.id)) continue;
      final box = _keys[message.id]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      if (bounds.overlaps(box.localToGlobal(Offset.zero) & box.size) &&
          (latest == null || _later(message, latest)))
        latest = message;
    }
    if (latest == null ||
        _readMessage != null && !_later(latest, _readMessage!))
      return;
    _reading = true;
    try {
      await widget.onRead!(latest);
      if (_same) _readMessage = latest;
    } on Object {
      // The next message, scroll, or resume retries; do not mark failed writes locally.
    } finally {
      _reading = false;
    }
    if (_same && _readMessage == latest) unawaited(_reportVisibleRead());
  }

  Future<void> _refresh({bool reloadHistory = true}) async {
    if (!_same) return;
    if (_refreshBusy) {
      _refreshQueued = true;
      _refreshHistoryQueued |= reloadHistory;
      return;
    }
    _refreshBusy = true;
    final ticket = ++_generation;
    final epoch = _windowEpoch;
    try {
      final repo = ref.read(chatModerationProvider);
      final visible =
          _window ??
          ref.read(chatMessagesProvider(widget.room)).asData?.value ??
          <ChatMessage>[];
      final ChatInteractions result;
      if (repo case ChatInteractionRepository interactions) {
        result = await interactions
            .interactions(widget.room, visible.map((m) => m.id).toList())
            .timeout(const Duration(seconds: 20));
      } else {
        final legacyPin = await repo.pin(widget.room);
        result = ChatInteractions(pins: [if (legacyPin != null) legacyPin]);
      }
      final rows = !reloadHistory || _anchor == null
          ? null
          : await repo
                .history(widget.room, anchor: _anchor)
                .timeout(const Duration(seconds: 20));
      if (!_same || ticket != _generation) return;
      _preserveReadingPosition();
      setState(() {
        _pins = result.pins;
        _pin =
            _pins
                .where((p) => p['message_id'] == _pin?['message_id'])
                .firstOrNull ??
            _pins.firstOrNull;
        if (epoch == _windowEpoch) _reactions = result.reactions;
        if (rows != null && epoch == _windowEpoch) _window = rows;
        _error = null;
      });
    } on Object catch (e) {
      if (_same && ticket == _generation)
        setState(() {
          _error = userError(e);
          if (e is PostgrestException && e.code == '42501') {
            _pin = null;
            _pins = [];
            _reactions = {};
            _window = null;
          }
        });
    } finally {
      _refreshBusy = false;
      if (_refreshQueued && _same) {
        final reloadQueuedHistory = _refreshHistoryQueued;
        _refreshQueued = false;
        _refreshHistoryQueued = false;
        unawaited(_refresh(reloadHistory: reloadQueuedHistory));
      }
    }
  }

  Future<void> _jump() async {
    if (_pin != null) await _jumpTo(_pin!['message_id'] as String);
  }

  Future<void> _jumpTo(String id) async {
    if (_busy || !_same) return;
    final mountedTarget = _keys[id]?.currentContext;
    if (mountedTarget != null) {
      _flash(id);
      await Scrollable.ensureVisible(
        mountedTarget,
        alignment: .5,
        duration: _jumpDuration,
        curve: Curves.easeOutCubic,
      );
      return;
    }
    if (_removed.contains(id)) return;
    _windowEpoch++;
    _generation++;
    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      final rows = await ref
          .read(chatModerationProvider)
          .history(widget.room, anchor: id)
          .timeout(const Duration(seconds: 20));
      if (!mounted || !_same) return;
      setState(() {
        _window = rows;
        _anchor = id;
        _away = true;
        _highlight = id;
      });
      unawaited(_refresh(reloadHistory: false));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_same || _removed.contains(id)) return;
        final target = _keys[id]?.currentContext;
        _flash(id);
        if (target != null)
          unawaited(
            Scrollable.ensureVisible(
              target,
              alignment: .5,
              duration: _jumpDuration,
              curve: Curves.easeOutCubic,
            ),
          );
      });
    } on Object catch (e) {
      if (_same) setState(() => _error = userError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _older(List<ChatMessage> rows) async {
    if (_busy || rows.isEmpty || !_same) return;
    _windowEpoch++;
    _generation++;
    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      final data = await ref
          .read(chatModerationProvider)
          .history(widget.room, before: rows.last)
          .timeout(const Duration(seconds: 20));
      if (!mounted || !_same) return;
      if (data.isNotEmpty)
        setState(() {
          _window = data;
          _away = true;
          _anchor = data.first.id;
          _highlight = null;
        });
      if (data.isNotEmpty)
        unawaited(_refresh(reloadHistory: false));
      else
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Это начало переписки.')));
    } on Object catch (e) {
      if (_same) setState(() => _error = userError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  Future<void> _menu(ChatMessage m) async {
    if (_busy || !_same || m.deleted || _removed.contains(m.id)) return;
    setState(() {
      _busy = true;
      _loading = true;
    });
    try {
      final repo = ref.read(chatModerationProvider);
      final caps =
          (repo is ChatInteractionRepository
              ? ref.read(chatAccessProvider(widget.room)).asData?.value
              : null) ??
          await repo.capabilities(widget.room);
      if (!mounted || !_same) return;
      final canDelete =
          caps['delete_any'] == true ||
          m.authorId == widget.actor && caps['delete_own'] == true;
      final isPinned = repo is ChatInteractionRepository
          ? _pins.any((p) => p['message_id'] == m.id)
          : (await repo.pin(widget.room))?['message_id'] == m.id;
      if (!mounted || !_same) return;
      setState(() => _loading = false);
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    m.authorId == widget.actor
                        ? 'Ваше сообщение'
                        : m.authorName,
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  CommunityTile(
                    title: 'Копировать',
                    icon: Icons.copy_rounded,
                    onTap: () => Navigator.pop(c, 'copy'),
                  ),
                  if (_interactive && caps['react'] == true)
                    CommunityTile(
                      title: 'Добавить реакцию',
                      icon: Icons.add_reaction_outlined,
                      onTap: () => Navigator.pop(c, 'react'),
                    ),
                  if (_interactive &&
                      caps['send'] == true &&
                      widget.onReply != null)
                    CommunityTile(
                      title: 'Ответить',
                      icon: Icons.reply_rounded,
                      onTap: () => Navigator.pop(c, 'reply'),
                    ),
                  if (caps['pin'] == true)
                    CommunityTile(
                      title: isPinned ? 'Открепить' : 'Закрепить',
                      icon: Icons.push_pin_outlined,
                      onTap: () => Navigator.pop(c, isPinned ? 'unpin' : 'pin'),
                    ),
                  if (canDelete)
                    CommunityTile(
                      title: 'Удалить сообщение',
                      icon: Icons.delete_outline,
                      color: Theme.of(c).colorScheme.error,
                      onTap: () => Navigator.pop(c, 'delete'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!mounted || !_same || action == null) return;
      if (action == 'reply') {
        widget.onReply?.call(m);
        return;
      }
      if (action == 'react') {
        final emoji = await chooseReaction(context);
        if (emoji != null && _same) await _react(m, emoji);
        return;
      }
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: m.body));
        return;
      }
      if (action == 'delete') {
        if (!await confirmAction(
              context,
              'Удалить сообщение?',
              'Сообщение будет удалено для всех участников чата.',
            ) ||
            !_same)
          return;
        setState(() => _loading = true);
        await repo.delete(m.id, widget.actor);
        if (!_same) return;
        setState(() {
          _removed.add(m.id);
          _pins.removeWhere((p) => p['message_id'] == m.id);
          if (_pin?['message_id'] == m.id) _pin = _pins.firstOrNull;
          if (_highlight == m.id) _highlight = null;
        });
      } else {
        setState(() => _loading = true);
        if (repo case ChatInteractionRepository interactions) {
          await interactions
              .setPinned(widget.room, m.id, action == 'pin', widget.actor)
              .timeout(const Duration(seconds: 20));
        } else {
          await repo.setPin(
            widget.room,
            action == 'unpin' ? null : m.id,
            widget.actor,
          );
        }
      }
      if (!mounted || !_same) return;
      if (action == 'delete') ref.invalidate(chatMessagesProvider(widget.room));
      await _refresh();
    } on Object catch (e) {
      if (_same) setState(() => _error = userError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatMessagesProvider(widget.room));
    _newest ??= messages.asData?.value.firstOrNull;
    _scheduleRead();
    for (final message
        in _window ?? messages.asData?.value ?? <ChatMessage>[]) {
      if (message.deleted) _removed.add(message.id);
    }
    ref.listen(chatMessagesProvider(widget.room), (_, next) {
      if (next.hasValue) {
        final rows = next.asData?.value ?? <ChatMessage>[];
        if (_newest != null && (_away || _window != null)) {
          for (final m in rows) {
            if (!m.deleted && m.authorId != widget.actor && _later(m, _newest!))
              _newMessages.add(m.id);
          }
        }
        if (rows.isNotEmpty)
          _newest = rows.reduce((a, b) => _later(a, b) ? a : b);
        _preserveReadingPosition();
        unawaited(_refresh());
      }
    });
    ref.listen(chatAccessProvider(widget.room), (_, next) {
      if (next.hasValue) unawaited(_refresh());
    });
    final appearance = ref.watch(appearanceControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_pin != null && !_removed.contains(_pin!['message_id']))
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _busy ? null : _jump,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Закреплённое сообщение',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Text(
                            '${_pin!['author_name']} · ${_pin!['body'] ?? 'Сообщение'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (_pins.length > 1) ...[
                      Text('${_pins.indexOf(_pin!) + 1}/${_pins.length}'),
                      IconButton(
                        tooltip: 'Следующее закреплённое сообщение',
                        icon: const Icon(Icons.expand_more),
                        onPressed: () => setState(
                          () => _pin =
                              _pins[(_pins.indexOf(_pin!) + 1) % _pins.length],
                        ),
                      ),
                    ] else
                      const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        SizedBox(
          height: 2,
          child: _loading ? const LinearProgressIndicator() : null,
        ),
        if (_window != null)
          TextButton(
            onPressed: _goLatest,
            child: const Text('К новым сообщениям'),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: AsyncContent<List<ChatMessage>>(
                  value: messages,
                  preserveOnRefresh: true,
                  loading: Semantics(
                    label: 'Загрузка сообщений',
                    child: const SizedBox.expand(),
                  ),
                  onRetry: () =>
                      ref.invalidate(chatMessagesProvider(widget.room)),
                  builder: (latest) {
                    final rows = _window ?? latest;
                    final rowIds = rows.map((m) => m.id).toSet();
                    _keys.removeWhere((id, _) => !rowIds.contains(id));
                    final visible = rows
                        .where((m) => !_collapsed.contains(m.id))
                        .toList()
                        .reversed
                        .toList();
                    if (rows.isEmpty)
                      return const Center(child: Text('Сообщений пока нет.'));
                    if (_window == null && visible.isNotEmpty) {
                      final indices = {
                        for (var i = 0; i < visible.length; i++)
                          visible[i].id: visible.length - i - 1,
                      };
                      return ClipRect(
                        key: _viewport,
                        child: ListView.builder(
                          key: ValueKey('chat-timeline-${widget.room}'),
                          controller: _scroll,
                          reverse: true,
                          padding: EdgeInsets.zero,
                          scrollCacheExtent:
                              const rendering.ScrollCacheExtent.pixels(240),
                          itemCount:
                              visible.length + (rows.length == 50 ? 1 : 0),
                          findChildIndexCallback: (key) =>
                              key is ValueKey<String>
                              ? indices[key.value]
                              : null,
                          itemBuilder: (context, index) {
                            if (index == visible.length)
                              return TextButton(
                                onPressed: _busy ? null : () => _older(rows),
                                child: const Text('Более ранние сообщения'),
                              );
                            final i = visible.length - index - 1;
                            final message = visible[i];
                            final showDay =
                                !_removed.contains(message.id) &&
                                (i == 0 ||
                                    !sameChatDay(
                                      visible[i - 1].createdAt,
                                      message.createdAt,
                                    ));
                            return Column(
                              key: ValueKey(message.id),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showDay) _dayHeader(message),
                                _message(message, appearance),
                              ],
                            );
                          },
                        ),
                      );
                    }
                    return ClipRect(
                      key: _viewport,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        reverse: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (rows.length == 50)
                              TextButton(
                                onPressed: _busy ? null : () => _older(rows),
                                child: const Text('Более ранние сообщения'),
                              ),
                            if (visible.isEmpty)
                              Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  rows.length == 50
                                      ? 'В этой части переписки нет сообщений.'
                                      : 'Сообщений пока нет.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            for (var i = 0; i < visible.length; i++) ...[
                              if (!_removed.contains(visible[i].id) &&
                                  (i == 0 ||
                                      !sameChatDay(
                                        visible[i - 1].createdAt,
                                        visible[i].createdAt,
                                      )))
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surface
                                            .withValues(alpha: .9),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        child: Text(
                                          chatDayLabel(visible[i].createdAt),
                                          key: ValueKey(
                                            'chat-day-${visible[i].id}',
                                          ),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              _message(visible[i], appearance),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_away || _window != null)
                Positioned(
                  right: 8,
                  bottom: 10,
                  child: Badge(
                    isLabelVisible: _newMessages.isNotEmpty,
                    label: Text('${_newMessages.length}'),
                    child: FloatingActionButton.small(
                      key: const ValueKey('chat-scroll-down'),
                      heroTag: null,
                      tooltip: 'К последнему сообщению',
                      onPressed: _goLatest,
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayHeader(ChatMessage message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            chatDayLabel(message.createdAt),
            key: ValueKey('chat-day-${message.id}'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _message(ChatMessage m, AppearanceSettings appearance) =>
      MessageRemoval(
        key: _keys.putIfAbsent(m.id, GlobalKey<State<StatefulWidget>>.new),
        removed: _removed.contains(m.id),
        onRemoved: () {
          if (_same) setState(() => _collapsed.add(m.id));
        },
        child: AnimatedContainer(
          key: ValueKey('message-highlight-${m.id}'),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: _highlight == m.id
                ? Theme.of(context).colorScheme.primary.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Semantics(
            button: true,
            label: 'Меню сообщения',
            onLongPress: () => _menu(m),
            child: GestureDetector(
              onLongPress: () => _menu(m),
              onSecondaryTap: () => _menu(m),
              child: RepaintBoundary(
                child: ChatMessageCard(
                  settings: appearance,
                  body: m.body,
                  author: m.authorId == widget.actor ? 'Вы' : m.authorName,
                  outgoing: m.authorId == widget.actor,
                  time: chatClock(m.createdAt),
                  reply: m.reply == null
                      ? null
                      : MessageReplyBlock(
                          reply: m.reply!,
                          onTap: () => _jumpTo(m.reply!.id),
                        ),
                  reactions: (_reactions[m.id]?.isEmpty ?? true)
                      ? null
                      : MessageReactions(
                          message: m.id,
                          reactions: _reactions[m.id]!,
                          onToggle:
                              _interactive &&
                                  ref
                                          .read(chatAccessProvider(widget.room))
                                          .asData
                                          ?.value['react'] ==
                                      true
                              ? (r) => _react(m, r.emoji, selected: !r.mine)
                              : null,
                        ),
                ),
              ),
            ),
          ),
        ),
      );
}
