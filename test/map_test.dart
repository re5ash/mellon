import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/features/map/application/map_actions.dart';
import 'package:moy_prihod/features/map/application/map_providers.dart';
import 'package:moy_prihod/features/map/application/map_temples.dart';
import 'package:moy_prihod/features/map/application/yandex_map_config.dart';
import 'package:moy_prihod/features/map/domain/map_place.dart';
import 'package:moy_prihod/features/map/presentation/event_map_field.dart';
import 'package:moy_prihod/features/map/presentation/map_page.dart';
import 'package:moy_prihod/features/map/presentation/map_tiles.dart';
import 'package:moy_prihod/features/parishes/domain/parish.dart';

class FakeMapTiles extends TileProvider {
  static final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN49eHzfwAJYgPNIyeaqwAAAABJRU5ErkJggg==',
  );
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(pixel);
}

class FakeMapActions extends MapActions {
  int locations = 0, shares = 0;
  final opened = <Uri>[];
  bool deny = false;
  @override
  Future<LatLng> locate() async {
    locations++;
    if (deny) throw const AppFailure('Доступ к геолокации не разрешён.');
    return const LatLng(54.72, 20.52);
  }

  @override
  Future<void> open(Uri uri) async {
    opened.add(uri);
  }

  @override
  Future<bool> share(MapPlace place, Rect origin) async {
    shares++;
    return true;
  }
}

Future<FakeMapActions> mountMap(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double scale = 1,
  List<MapEvent> events = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final actions = FakeMapActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mapTemplesProvider.overrideWith((ref) async => [
          Parish(id: alexanderNevsky.id, name: alexanderNevsky.title,
            address: 'Адрес из записи', description: '',
            latitude: alexanderNevsky.point.latitude,
            longitude: alexanderNevsky.point.longitude),
        ]),
        mapEventsProvider.overrideWith((ref) async => events),
        mapTileProvider.overrideWithValue(FakeMapTiles.new),
        yandexMapConfigProvider.overrideWithValue(
          const YandexMapConfig(tilesKey: 'test-key'),
        ),
        mapActionsProvider.overrideWithValue(actions),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: MapPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return actions;
}

void main() {
  test(
    'Yandex tiles use spherical projection and never call a route service',
    () {
      const config = YandexMapConfig(tilesKey: 'key +?&');
      final uri = Uri.parse(
        config.tileTemplate
            .replaceAll('{x}', '12')
            .replaceAll('{y}', '34')
            .replaceAll('{z}', '8'),
      );
      expect(uri.host, 'tiles.api-maps.yandex.ru');
      expect(uri.queryParameters['projection'], 'web_mercator');
      expect(uri.queryParameters['apikey'], 'key +?&');
      expect(uri.queryParameters['lang'], 'ru_RU');
    },
  );
  testWidgets(
    'missing key does not issue requests or draw pins over a blank map',
    (tester) async {
      var providersCreated = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
        mapTemplesProvider.overrideWith((ref) async => [
          Parish(id: alexanderNevsky.id, name: alexanderNevsky.title,
            address: 'Адрес из записи', description: '',
            latitude: alexanderNevsky.point.latitude,
            longitude: alexanderNevsky.point.longitude),
        ]),
            yandexMapConfigProvider.overrideWithValue(
              const YandexMapConfig(tilesKey: ''),
            ),
            mapTileProvider.overrideWithValue(() {
              providersCreated++;
              return FakeMapTiles();
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: MapPage())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-not-configured')), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      expect(providersCreated, 0);
    },
  );
  testWidgets(
    'returning to the map refreshes today events without resetting the camera',
    (tester) async {
      var calls = 0, visible = true;
      late StateSetter change;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
        mapTemplesProvider.overrideWith((ref) async => [
          Parish(id: alexanderNevsky.id, name: alexanderNevsky.title,
            address: 'Адрес из записи', description: '',
            latitude: alexanderNevsky.point.latitude,
            longitude: alexanderNevsky.point.longitude),
        ]),
            mapEventsProvider.overrideWith((ref) async {
              calls++;
              return [];
            }),
            mapTileProvider.overrideWithValue(FakeMapTiles.new),
            yandexMapConfigProvider.overrideWithValue(
              const YandexMapConfig(tilesKey: 'test-key'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  change = setState;
                  return TickerMode(enabled: visible, child: const MapPage());
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      controller.move(const LatLng(54.7, 20.5), 14);
      expect(calls, 1);
      change(() => visible = false);
      await tester.pumpAndSettle();
      change(() => visible = true);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(controller.camera.center, const LatLng(54.7, 20.5));
    },
  );
  testWidgets(
    'future events have pins and a focus action but no Today banner',
    (tester) async {
      final event = MapEvent(
        place: const MapPlace(
          id: 'future',
          title: 'Завтрашняя встреча',
          address: '',
          point: LatLng(54.725, 20.527),
          timeLabel: '18:00',
          dateLabel: '14.09.2026',
        ),
        startsAt: DateTime(2026, 9, 14, 18),
        isToday: false,
      );
      await mountMap(tester, events: [event]);
      expect(find.byKey(const ValueKey('map-event-future')), findsOneWidget);
      expect(find.byKey(const ValueKey('map-banner-future')), findsNothing);
      await tester.tap(find.byTooltip('События на карте (1)'));
      await tester.pumpAndSettle();
      expect(find.text('14.09.2026 18:00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('map-event-list-future')));
      await tester.pumpAndSettle();
      final map = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      expect(map.camera.center, event.place.point);
      await tester.tap(find.byKey(const ValueKey('map-event-future')));
      await tester.pumpAndSettle();
      expect(find.text('14.09.2026 18:00'), findsOneWidget);
      expect(find.text('Сегодня 18:00'), findsNothing);
    },
  );

  testWidgets('an event card closes when the server removes its visibility', (
    tester,
  ) async {
    final events = [
      MapEvent(
        place: MapPlace(
          id: 'private',
          title: 'Закрытая встреча',
          address: '',
          point: alexanderNevsky.point,
          timeLabel: '18:00',
        ),
        startsAt: DateTime.now(),
      ),
    ];
    await mountMap(tester, events: events);
    await tester.tap(find.byKey(const ValueKey('map-event-private')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    events.clear();
    ProviderScope.containerOf(tester.element(find.byType(MapPage)))
        .invalidate(mapEventsProvider);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('Закрытая встреча'), findsNothing);
  });
  test('distance and links use the actual coordinates, not an invented walking route length', () {
    expect(distanceLabel(alexanderNevsky.point, alexanderNevsky.point), '0 м');
    expect(
      distanceLabel(const LatLng(54.72, 20.52), alexanderNevsky.point),
      matches(r'^\d+ м$'),
    );
    expect(
      placeLink(alexanderNevsky).queryParameters['pt'],
      '20.526467,54.723306',
    );
  });
  testWidgets(
    'map pans and zooms; opening, expanding and swiping the sheet never move its camera',
    (tester) async {
      final actions = await mountMap(tester);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final start = controller.camera.center;
      await tester.dragFrom(const Offset(100, 450), const Offset(35, 0));
      await tester.pumpAndSettle();
      expect(controller.camera.center, isNot(start));
      final zoom = controller.camera.zoom;
      await tester.tap(find.byTooltip('Приблизить карту'));
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, closeTo(zoom + 1, .001));
      final before = controller.camera.center;
      await tester.tap(find.byKey(const ValueKey('temple-map-pin')));
      await tester.pumpAndSettle();
      expect(actions.locations, 0);
      expect(controller.camera.center, before);
      expect(find.text('Проложить маршрут'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('map-hours')));
      await tester.pumpAndSettle();
      expect(find.text('Ежедневно с 8 до 19'), findsOneWidget);
      expect(controller.camera.center, before);
      final sheet = tester.getRect(find.byType(BottomSheet));
      await tester.dragFrom(
        Offset(sheet.center.dx, sheet.top + 16),
        const Offset(0, 380),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(controller.camera.center, before);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'location is requested on action; denial leaves sharing available and never opens a route',
    (tester) async {
      final actions = await mountMap(tester);
      actions.deny = true;
      await tester.tap(find.byKey(const ValueKey('temple-map-pin')));
      await tester.pumpAndSettle();
      expect(actions.locations, 0);
      await tester.tap(find.byKey(const ValueKey('map-distance')));
      await tester.pumpAndSettle();
      expect(actions.locations, 1);
      expect(
        find.textContaining('Доступ к геолокации не разрешён'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('map-route')), findsNothing);
      expect(actions.opened, isEmpty);
      await tester.tap(find.byKey(const ValueKey('map-share')));
      await tester.pumpAndSettle();
      expect(actions.shares, 1);
      actions.deny = false;
      await tester.tap(find.byKey(const ValueKey('map-distance')));
      await tester.pumpAndSettle();
      expect(find.textContaining('по прямой'), findsOneWidget);
      expect(actions.opened, isEmpty);
    },
  );
  testWidgets(
    'today banner animates to the actual event point and does not jump on first frame',
    (tester) async {
      final event = MapEvent(
        place: const MapPlace(
          id: 'boat',
          title: 'Сплав по реке Анграпа',
          address: 'Место сбора',
          point: LatLng(54.41, 22.0),
          timeLabel: '18:00',
        ),
        startsAt: DateTime.utc(2026, 9, 13, 16),
      );
      await mountMap(tester, events: [event]);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final before = controller.camera.center;
      await tester.tap(find.byKey(const ValueKey('map-banner-boat')));
      await tester.pump();
      expect(controller.camera.center, before);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.camera.center, isNot(before));
      expect(controller.camera.center, isNot(event.place.point));
      await tester.pumpAndSettle();
      expect(
        controller.camera.center.latitude,
        closeTo(event.place.point.latitude, 1e-6),
      );
      expect(
        controller.camera.center.longitude,
        closeTo(event.place.point.longitude, 1e-6),
      );
    },
  );
  for (final size in [
    const Size(320, 568),
    const Size(1000, 700),
    const Size(844, 390),
  ]) {
    testWidgets(
      'sheet fits $size with enlarged text and keeps actions reachable',
      (tester) async {
        await mountMap(tester, size: size, scale: 1.5);
        await tester.tap(find.byKey(const ValueKey('temple-map-pin')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('map-route')), findsNothing);
        expect(
          find.byKey(const ValueKey('map-share')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'event map field requires an explicit point and returns selected coordinates',
    (tester) async {
      final form = GlobalKey<FormState>();
      var value = const EventMapValue();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
        mapTemplesProvider.overrideWith((ref) async => [
          Parish(id: alexanderNevsky.id, name: alexanderNevsky.title,
            address: 'Адрес из записи', description: '',
            latitude: alexanderNevsky.point.latitude,
            longitude: alexanderNevsky.point.longitude),
        ]),
            mapTileProvider.overrideWithValue(FakeMapTiles.new),
            yandexMapConfigProvider.overrideWithValue(
              const YandexMapConfig(tilesKey: 'test-key'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Form(
                key: form,
                child: StatefulBuilder(
                  builder: (context, setState) => EventMapField(
                    value: value,
                    onChanged: (next) => setState(() => value = next),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('show-event-on-map')));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('choose-event-map-point')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('У храма Александра Невского'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-event-map-point')));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isTrue);
      expect(value.payload, {
        'show_on_map': true,
        'map_latitude': 54.723306,
        'map_longitude': 20.526467,
      });
      await tester.tap(find.byKey(const ValueKey('show-event-on-map')));
      await tester.pumpAndSettle();
      expect(value.enabled, isFalse);
      expect(value.point, alexanderNevsky.point);
    },
  );
}
