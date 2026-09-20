import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/errors/app_failure.dart';
import '../application/map_actions.dart';
import '../domain/map_place.dart';

class PlaceSheet extends ConsumerStatefulWidget {
  const PlaceSheet({
    required this.place,
    this.position,
    required this.onLocated,
    super.key,
  });
  final MapPlace place;
  final LatLng? position;
  final ValueChanged<LatLng> onLocated;
  @override
  ConsumerState<PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends ConsumerState<PlaceSheet> {
  bool _hours = false, _locating = false;
  late LatLng? _position = widget.position;
  String? _error;
  Future<void> _locate() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final point = await ref.read(mapActionsProvider).locate();
      if (!mounted) return;
      setState(() => _position = point);
      widget.onLocated(point);
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      await ref.read(mapActionsProvider).open(uri);
    } on Object catch (error) {
      if (mounted) setState(() => _error = userError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      child: Padding(
        key: const ValueKey('map-place-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: SizedBox(
                            width: 84,
                            height: 106,
                            child: place.photoAsset != null
                                ? Image.asset(
                                    place.photoAsset!,
                                    fit: BoxFit.cover,
                                    semanticLabel: 'Фотография храма',
                                    cacheWidth: 336,
                                  )
                                : const ColoredBox(
                                    color: Color(0xffe6f3fc),
                                    child: Icon(
                                      Icons.event_rounded,
                                      color: Color(0xff318ac1),
                                      size: 34,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                place.title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  height: 1.22,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                place.address.isEmpty
                                    ? 'Место встречи отмечено на карте'
                                    : place.address,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Color(0xff647889),
                                ),
                              ),
                              if (place.timeLabel != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    '${place.dateLabel ?? 'Сегодня'} ${place.timeLabel}',
                                    style: const TextStyle(
                                      color: Color(0xff2589c7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('map-distance'),
                        onPressed: _locating ? null : _locate,
                        icon: const Icon(
                          Icons.directions_walk_rounded,
                          size: 19,
                        ),
                        label: Text(
                          _locating
                              ? 'Определяем расстояние…'
                              : _position == null
                              ? 'Узнать расстояние'
                              : '${distanceLabel(_position!, place.point)} · по прямой',
                        ),
                      ),
                    ),
                    if (place.hours != null) ...[
                      InkWell(
                        key: const ValueKey('map-hours'),
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => _hours = !_hours),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 18,
                                color: Color(0xff647889),
                              ),
                              const SizedBox(width: 9),
                              const Expanded(child: Text('График работы')),
                              AnimatedRotation(
                                turns: _hours ? .5 : 0,
                                duration: Duration(
                                  milliseconds: reduced ? 0 : 200,
                                ),
                                child: const Icon(Icons.expand_more),
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: Duration(milliseconds: reduced ? 0 : 220),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: double.infinity,
                          child: _hours
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    left: 27,
                                    bottom: 10,
                                  ),
                                  child: Text(place.hours!),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    if (place.photoAsset != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Фотография храма'),
                              content: const Text(
                                'Zairon, 2019 · Wikimedia Commons\nCC BY-SA 4.0\nФотография уменьшена; в метке и карточке показана с обрезкой по форме, без растяжения.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => _open(
                                    Uri.parse(
                                      'https://commons.wikimedia.org/wiki/File:Kaliningrad_Alexander_Nevsky_1.jpg',
                                    ),
                                  ),
                                  child: const Text('Источник'),
                                ),
                                TextButton(
                                  onPressed: () => _open(
                                    Uri.parse(
                                      'https://creativecommons.org/licenses/by-sa/4.0/',
                                    ),
                                  ),
                                  child: const Text('Лицензия'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Закрыть'),
                                ),
                              ],
                            ),
                          ),
                          child: const Text(
                            'Фото: Zairon · CC BY-SA 4.0',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff7b8b97),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Builder(
                  builder: (buttonContext) => IconButton.filledTonal(
                    key: const ValueKey('map-share'),
                    tooltip: 'Поделиться',
                    onPressed: () async {
                      final box =
                          buttonContext.findRenderObject()! as RenderBox;
                      final origin = box.localToGlobal(Offset.zero) & box.size;
                      try {
                        final copied = await ref
                            .read(mapActionsProvider)
                            .share(place, origin);
                        if (copied && mounted)
                          setState(() => _error = 'Ссылка скопирована.');
                      } on Object catch (error) {
                        if (mounted) setState(() => _error = userError(error));
                      }
                    },
                    icon: const Icon(Icons.ios_share_rounded, size: 21),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
