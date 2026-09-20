import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../../core/errors/app_failure.dart';
import '../../../design_system/components/navigation_content_insets.dart';
import '../application/map_actions.dart';
import '../application/map_providers.dart';
import '../application/map_temples.dart';
import '../application/yandex_map_config.dart';
import '../domain/map_place.dart';
import 'map_tiles.dart';
import 'place_sheet.dart';
import 'temple_pin.dart';
export 'temple_pin.dart' show TemplePin;

class MapPage extends ConsumerStatefulWidget {
  const MapPage({this.parishId, this.focusRequest, super.key});
  final String? parishId, focusRequest;
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _map = MapController();
  late final AnimationController _flight;
  Timer? _refresh;
  LatLng? _from, _to, _position;
  MapPlace? _selectedPlace;
  ModalRoute<void>? _placeRoute;
  double _fromZoom = 15, _toZoom = 15;
  bool _ready = false,
      _sheetOpen = false,
      _locating = false,
      _tileError = false;
  int _tileRevision = 0;
  bool _visible = true;
  String? _handledRequest, _selectedTempleId;
  String? get _requestToken => widget.parishId == null
      ? null
      : '${widget.parishId}:${widget.focusRequest ?? ''}';

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parishId != widget.parishId ||
        oldWidget.focusRequest != widget.focusRequest) {
      _handledRequest = null;
    }
  }

  void _requestTempleFocus() {
    final token = _requestToken;
    if (token == null ||
        token == _handledRequest ||
        !_ready ||
        !_visible ||
        _sheetOpen)
      return;
    final state = ref.read(mapTemplesProvider);
    if (!state.hasValue || state.isReloading) {
      if (state.hasError && !state.isLoading) {
        _handledRequest = token;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось загрузить храм. Повторите нажатие на адрес.',
            ),
          ),
        );
      }
      return;
    }
    final temple = templeById(state.requireValue, widget.parishId!);
    if (temple == null && state.isLoading) return;
    _handledRequest = token;
    final place = temple == null ? null : templeMapPlace(temple);
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            temple == null
                ? 'Храм недоступен на карте.'
                : 'У этого храма ещё не указаны координаты.',
          ),
        ),
      );
      return;
    }
    _focus(place.point, zoom: 17);
    unawaited(_show(place, temple: true, stopFlight: false));
  }

  void _scheduleTempleFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestTempleFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flight =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 650),
        )..addListener(() {
          if (!_ready || _from == null || _to == null) return;
          final t = Curves.easeInOutCubic.transform(_flight.value);
          _map.move(
            LatLng(
              _from!.latitude + (_to!.latitude - _from!.latitude) * t,
              _from!.longitude + (_to!.longitude - _from!.longitude) * t,
            ),
            _fromZoom + (_toZoom - _fromZoom) * t,
          );
        });
    _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        ref.invalidate(mapEventsProvider);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_visible) {
      scheduleMicrotask(() {
        if (mounted) {
          ref.invalidate(mapEventsProvider);
          ref.invalidate(mapTemplesProvider);
        }
      });
    }
    if (!visible && _visible) _handledRequest = _requestToken;
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(mapEventsProvider);
      ref.invalidate(mapTemplesProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    _flight.dispose();
    _map.dispose();
    super.dispose();
  }

  void _focus(LatLng point, {double? zoom}) {
    if (!_ready) return;
    _flight.stop();
    _from = _map.camera.center;
    _to = point;
    _fromZoom = _map.camera.zoom;
    _toZoom = zoom ?? math.max(15, _fromZoom);
    if (MediaQuery.disableAnimationsOf(context)) {
      _map.move(point, _toZoom);
      return;
    }
    unawaited(_flight.forward(from: 0));
  }

  Future<void> _chooseMapEvent(List<MapEvent> events) async {
    final event = await showModalBottomSheet<MapEvent>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .5,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('События на карте'),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return ListTile(
                      key: ValueKey('map-event-list-${event.place.id}'),
                      leading: const Icon(Icons.event_rounded),
                      title: Text(event.place.title),
                      subtitle: Text(
                        '${event.place.dateLabel ?? 'Сегодня'} ${event.place.timeLabel ?? ''}',
                      ),
                      onTap: () => Navigator.pop(context, event),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && event != null) _focus(event.place.point);
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final point = await ref.read(mapActionsProvider).locate();
      if (!mounted) return;
      setState(() => _position = point);
      _focus(point);
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userError(error))));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _show(
    MapPlace place, {
    bool temple = false,
    bool stopFlight = true,
  }) async {
    if (_sheetOpen) return;
    setState(() {
      _sheetOpen = true;
      _selectedPlace = place;
      _selectedTempleId = temple ? place.id : null;
    });
    if (stopFlight) _flight.stop();
    final size = MediaQuery.sizeOf(context);
    final height = math.min(
      size.height * .75,
      math.max(300.0, size.height * .40),
    );
    final theme = mellonMapTheme(context);
    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        enableDrag: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        barrierColor: Colors.black.withValues(alpha: .08),
        requestFocus: false,
        sheetAnimationStyle: AnimationStyle(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 320,
          ),
          reverseDuration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 260,
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 600),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) {
          _placeRoute = ModalRoute.of<void>(context);
          return Theme(
            data: theme,
            child: SizedBox(
              height: height,
              child: Consumer(
                builder: (context, ref, child) {
                  var current = place;
                  if (temple) {
                    final data = ref.watch(mapTemplesProvider);
                    final record = data.hasValue
                        ? templeById(data.requireValue, place.id)
                        : null;
                    if (record != null)
                      current = templeMapPlace(record) ?? place;
                  }
                  return PlaceSheet(
                    place: current,
                    position: _position,
                    onLocated: (point) {
                      if (mounted) setState(() => _position = point);
                    },
                  );
                },
              ),
            ),
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _sheetOpen = false;
          _selectedPlace = null;
          _selectedTempleId = null;
          _placeRoute = null;
        });
        _scheduleTempleFocus();
      }
    }
  }

  void _tileFailed() {
    if (_tileError) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileError) setState(() => _tileError = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(yandexMapConfigProvider).configured) {
      return const MapNotConfigured();
    }
    final templesState = ref.watch(mapTemplesProvider);
    final temples = templesState.hasValue && !templesState.isReloading
        ? templesState.requireValue
              .map(templeMapPlace)
              .whereType<MapPlace>()
              .toList()
        : <MapPlace>[];
    ref.listen(mapTemplesProvider, (_, next) {
      final selected = _selectedTempleId;
      if (selected == null) return;
      if (next.isReloading ||
          next.hasError ||
          next.hasValue && templeById(next.requireValue, selected) == null) {
        final route = _placeRoute;
        scheduleMicrotask(() {
          if (mounted &&
              identical(route, _placeRoute) &&
              route?.navigator != null) {
            route!.navigator!.removeRoute(route);
          }
        });
      }
    });
    _scheduleTempleFocus();
    final state = ref.watch(mapEventsProvider);
    ref.listen(mapEventsProvider, (_, next) {
      final selected = _selectedPlace;
      if (selected == null || _selectedTempleId != null) return;
      if (next.hasError ||
          next.isReloading ||
          next.hasValue &&
              !next.requireValue.any(
                (event) => event.place.id == selected.id,
              )) {
        final route = _placeRoute;
        scheduleMicrotask(() {
          if (mounted &&
              identical(route, _placeRoute) &&
              route?.navigator != null) {
            _placeRoute = null;
            _selectedPlace = null;
            route!.navigator!.removeRoute(route);
          }
        });
      }
    });
    final events = state.isReloading || state.hasError
        ? <MapEvent>[]
        : state.asData?.value ?? <MapEvent>[];
    final todayEvents = events.where((event) => event.isToday).toList();
    return Theme(
      data: mellonMapTheme(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: FlutterMap(
              key: const ValueKey('mellon-interactive-map'),
              mapController: _map,
              options: MapOptions(
                initialCenter: alexanderNevsky.point,
                initialZoom: 15,
                minZoom: 3,
                maxZoom: 19,
                backgroundColor: const Color(0xffeaf0f3),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: () {
                  _ready = true;
                  _scheduleTempleFocus();
                },
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture) _flight.stop();
                },
              ),
              children: [
                MellonMapTiles(
                  key: ValueKey(_tileRevision),
                  onError: _tileFailed,
                ),
                MarkerLayer(
                  markers: [
                    for (final place in temples)
                      Marker(
                        point: place.point,
                        width: 70,
                        height: 84,
                        alignment: Alignment.topCenter,
                        child: TemplePin(
                          key: ValueKey('map-temple-${place.id}'),
                          place: place,
                          selected: _selectedTempleId == place.id,
                          onTap: () => _show(place, temple: true),
                        ),
                      ),
                    for (final event in events)
                      Marker(
                        point: event.place.point,
                        width: 48,
                        height: 48,
                        child: Tooltip(
                          message: event.place.title,
                          child: IconButton.filled(
                            key: ValueKey('map-event-${event.place.id}'),
                            onPressed: () => _show(event.place),
                            icon: const Icon(Icons.event_rounded),
                          ),
                        ),
                      ),
                    if (_position != null)
                      Marker(
                        point: _position!,
                        width: 20,
                        height: 20,
                        child: Semantics(
                          label: 'Ваше местоположение',
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xff2b96e2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x302b96e2),
                                  blurRadius: 8,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (todayEvents.isNotEmpty)
            Positioned(
              top: MapAttribution.height + 8,
              left: 12,
              right: 12,
              child: SizedBox(
                height: MediaQuery.textScalerOf(context).scale(18) + 32,
                child: PageView(
                  children: [
                    for (final event in todayEvents)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: Colors.white,
                          elevation: 2,
                          shadowColor: Colors.black12,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            key: ValueKey('map-banner-${event.place.id}'),
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _focus(event.place.point),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.event_available_rounded,
                                    size: 19,
                                    color: Color(0xff2c92d1),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      'Сегодня ${event.place.timeLabel} — ${event.place.title}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (todayEvents.length > 1)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Text(
                                        '${todayEvents.indexOf(event) + 1}/${todayEvents.length}',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 42 + NavigationContentInsets.of(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MapButton(
                  label: 'Приблизить карту',
                  icon: Icons.add,
                  onPressed: () => _focus(
                    _map.camera.center,
                    zoom: (_map.camera.zoom + 1).clamp(3, 19),
                  ),
                ),
                const SizedBox(height: 6),
                _MapButton(
                  label: 'Отдалить карту',
                  icon: Icons.remove,
                  onPressed: () => _focus(
                    _map.camera.center,
                    zoom: (_map.camera.zoom - 1).clamp(3, 19),
                  ),
                ),
                if (events.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _MapButton(
                    label: 'События на карте (${events.length})',
                    icon: Icons.event_rounded,
                    onPressed: () => _chooseMapEvent(events),
                  ),
                ],
                const SizedBox(height: 12),
                _MapButton(
                  label: _locating
                      ? 'Определяем местоположение'
                      : 'Моё местоположение',
                  icon: Icons.my_location_rounded,
                  onPressed: _locating ? null : _locate,
                ),
              ],
            ),
          ),
          if (_tileError || state.hasError || templesState.hasError)
            Positioned(
              left: 12,
              right: 72,
              bottom: 44 + NavigationContentInsets.of(context),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _tileError = false;
                      _tileRevision++;
                    });
                    ref.invalidate(mapEventsProvider);
                    ref.invalidate(mapTemplesProvider);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _tileError
                          ? 'Карта не загрузилась. Нажмите, чтобы повторить.'
                          : templesState.hasError
                          ? 'Храмы недоступны. Нажмите, чтобы повторить.'
                          : 'События недоступны. Нажмите, чтобы повторить.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          const Positioned(left: 0, top: 0, child: MapAttribution()),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    shadowColor: Colors.black12,
    borderRadius: BorderRadius.circular(15),
    child: IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, color: const Color(0xff2c739f)),
      style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
    ),
  );
}
