import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../application/yandex_map_config.dart';
import '../domain/map_place.dart';
import 'map_tiles.dart';

class EventMapValue {
  const EventMapValue({this.enabled = false, this.point});
  final bool enabled;
  final LatLng? point;
  factory EventMapValue.fromJson(Map<String, dynamic>? row) => EventMapValue(
    enabled: row?['show_on_map'] == true,
    point: row?['map_latitude'] is num && row?['map_longitude'] is num
        ? LatLng(
            (row!['map_latitude'] as num).toDouble(),
            (row['map_longitude'] as num).toDouble(),
          )
        : null,
  );
  Map<String, dynamic> get payload => {
    'show_on_map': enabled,
    'map_latitude': point?.latitude,
    'map_longitude': point?.longitude,
  };
}

class EventMapField extends FormField<EventMapValue> {
  EventMapField({
    required EventMapValue value,
    required ValueChanged<EventMapValue> onChanged,
    bool readOnly = false,
    super.key,
  }) : super(
         initialValue: value,
         validator: (value) => value?.enabled == true && value?.point == null
             ? 'Выберите точку события на карте.'
             : null,
         builder: (field) {
           final current = field.value!;
           void change(EventMapValue next) {
             field.didChange(next);
             onChanged(next);
           }

           return Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
               SwitchListTile.adaptive(
                 key: const ValueKey('show-event-on-map'),
                 contentPadding: EdgeInsets.zero,
                 title: const Text('Показать на карте'),
                 subtitle: const Text(
                   'После сохранения опубликованного события появится метка. В день события — также плашка сверху.',
                 ),
                 value: current.enabled,
                 onChanged: readOnly
                     ? null
                     : (enabled) => change(
                         EventMapValue(enabled: enabled, point: current.point),
                       ),
               ),
               if (current.enabled)
                 OutlinedButton.icon(
                   key: const ValueKey('choose-event-map-point'),
                   onPressed: readOnly
                       ? null
                       : () async {
                           FocusScope.of(field.context).unfocus();
                           final point = await showModalBottomSheet<LatLng>(
                             context: field.context,
                             isScrollControlled: true,
                             useRootNavigator: true,
                             useSafeArea: true,
                             constraints: const BoxConstraints(maxWidth: 760),
                             builder: (context) => SizedBox(
                               height: MediaQuery.sizeOf(context).height * .85,
                               child: EventPointPicker(initial: current.point),
                             ),
                           );
                           if (point != null && field.mounted)
                             change(EventMapValue(enabled: true, point: point));
                         },
                   icon: const Icon(Icons.add_location_alt_outlined),
                   label: Text(
                     current.point == null
                         ? 'Выбрать точку на карте'
                         : 'Точка выбрана · изменить',
                   ),
                 ),
               if (field.hasError)
                 Text(
                   field.errorText!,
                   style: TextStyle(
                     color: Theme.of(field.context).colorScheme.error,
                   ),
                 ),
             ],
           );
         },
       );
}

class EventPointPicker extends ConsumerStatefulWidget {
  const EventPointPicker({this.initial, super.key});
  final LatLng? initial;
  @override
  ConsumerState<EventPointPicker> createState() => _EventPointPickerState();
}

class _EventPointPickerState extends ConsumerState<EventPointPicker> {
  final _map = MapController();
  late LatLng? _point = widget.initial;
  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: mellonMapTheme(context),
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Точка события'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: !ref.watch(yandexMapConfigProvider).configured
          ? const MapNotConfigured()
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(
                    'Нажмите на место встречи. Карту можно двигать и масштабировать.',
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        key: const ValueKey('event-point-map'),
                        mapController: _map,
                        options: MapOptions(
                          initialCenter: _point ?? alexanderNevsky.point,
                          initialZoom: 14,
                          minZoom: 3,
                          maxZoom: 19,
                          interactionOptions: const InteractionOptions(
                            flags:
                                InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                          onTap: (_, point) => setState(() => _point = point),
                        ),
                        children: [
                          const MellonMapTiles(),
                          MarkerLayer(
                            markers: [
                              if (_point != null)
                                Marker(
                                  point: _point!,
                                  width: 44,
                                  height: 48,
                                  alignment: Alignment.topCenter,
                                  child: const Icon(
                                    Icons.location_pin,
                                    size: 48,
                                    color: Color(0xff278cc9),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      const Positioned(
                        left: 0,
                        top: 0,
                        child: MapAttribution(),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _point = alexanderNevsky.point);
                            _map.move(alexanderNevsky.point, 16);
                          },
                          icon: const Icon(Icons.church_outlined),
                          label: const Text('У храма Александра Невского'),
                        ),
                        FilledButton(
                          key: const ValueKey('confirm-event-map-point'),
                          onPressed: _point == null
                              ? null
                              : () => Navigator.pop(context, _point),
                          child: const Text('Использовать эту точку'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    ),
  );
}
