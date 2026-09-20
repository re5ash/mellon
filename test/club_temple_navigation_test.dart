import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' hide MapEvent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:moy_prihod/features/community/club_temple_address.dart';
import 'package:moy_prihod/features/map/application/map_actions.dart';
import 'package:moy_prihod/features/map/application/map_providers.dart';
import 'package:moy_prihod/features/map/application/map_temples.dart';
import 'package:moy_prihod/features/map/application/yandex_map_config.dart';
import 'package:moy_prihod/features/map/presentation/map_page.dart';
import 'package:moy_prihod/features/map/presentation/map_tiles.dart';
import 'package:moy_prihod/features/parishes/domain/parish.dart';

import 'map_test.dart' show FakeMapActions, FakeMapTiles;

const templeA = Parish(id: 'temple-a', name: 'Одинаковое название',
  address: 'Первый адрес', description: '', latitude: 54.72, longitude: 20.52);
const templeB = Parish(id: 'temple-b', name: 'Одинаковое название',
  address: 'Адрес связанного храма', description: '', latitude: 54.75, longitude: 20.57);

void main() {
  test('identity and map coordinates come from the parish record', () {
    expect(templeById([templeA, templeB], 'temple-b'), same(templeB));
    expect(templeMapPlace(templeB)!.address, templeB.address);
    expect(templeMapPlace(templeB)!.point, const LatLng(54.75, 20.57));
    expect(templeMapPlace(const Parish(id: 'missing', name: '', address: '', description: '')), isNull);
  });

  testWidgets('icon and text open the exact existing marker and its sheet', (tester) async {
    final actions = FakeMapActions();
    final router = GoRouter(initialLocation: '/club', routes: [
      GoRoute(path: '/club', builder: (_, state) => const Scaffold(
        body: ClubTempleAddress(parishId: 'temple-b', fallbackAddress: 'Старый адрес'),
      )),
      GoRoute(path: '/map', builder: (_, state) => Scaffold(body: MapPage(
        parishId: state.uri.queryParameters['parish'],
        focusRequest: state.uri.queryParameters['focus'],
      ))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      mapTemplesProvider.overrideWith((ref) async => [templeA, templeB]),
      mapEventsProvider.overrideWith((ref) async => []),
      mapTileProvider.overrideWithValue(FakeMapTiles.new),
      mapActionsProvider.overrideWithValue(actions),
      yandexMapConfigProvider.overrideWithValue(const YandexMapConfig(tilesKey: 'test-key')),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    expect(find.text(templeB.address), findsOneWidget);
    expect(find.text('Старый адрес'), findsNothing);
    for (final icon in [true, false]) {
      await tester.tap(icon ? find.byIcon(Icons.place_outlined) : find.text(templeB.address));
      await tester.pumpAndSettle();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.center.latitude, closeTo(54.75, .00001));
      expect(map.mapController!.camera.center.longitude, closeTo(20.57, .00001));
      expect(map.mapController!.camera.zoom, closeTo(17, .001));
      // Offscreen markers may be culled by FlutterMap at zoom 17.
      final markers = tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;
      final pins = markers.map((marker) => marker.child).whereType<TemplePin>().toList();
      expect(pins, hasLength(2));
      expect(pins.singleWhere((pin) => pin.place.id == templeB.id).selected, isTrue);
      expect(pins.singleWhere((pin) => pin.place.id == templeA.id).selected, isFalse);
      expect(find.byKey(const ValueKey('map-place-sheet')), findsOneWidget);
      expect(find.text(templeB.address), findsOneWidget);
      expect(actions.opened, isEmpty);
      Navigator.of(tester.element(find.byKey(const ValueKey('map-place-sheet')))).pop();
      await tester.pumpAndSettle();
      router.go('/club');
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('one parish update changes the club address without changing its ID', (tester) async {
    var rows = [templeB];
    final container = ProviderContainer(overrides: [
      mapTemplesProvider.overrideWith((ref) async => rows),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: Scaffold(body: ClubTempleAddress(
        parishId: 'temple-b', fallbackAddress: 'Старое значение RPC',
      ))),
    ));
    await tester.pumpAndSettle();
    expect(find.text(templeB.address), findsOneWidget);
    rows = [const Parish(id: 'temple-b', name: 'Новое название', address: 'Обновлённый адрес',
      description: '', latitude: 54.75, longitude: 20.57)];
    container.invalidate(mapTemplesProvider);
    await tester.pumpAndSettle();
    expect(find.text('Обновлённый адрес'), findsOneWidget);
    expect(find.text(templeB.address), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a late parish response does not open a sheet after leaving the map', (tester) async {
    final response = Completer<List<Parish>>();
    var visible = true;
    late StateSetter change;
    await tester.pumpWidget(ProviderScope(overrides: [
      mapTemplesProvider.overrideWith((ref) => response.future),
      mapEventsProvider.overrideWith((ref) async => []),
      mapTileProvider.overrideWithValue(FakeMapTiles.new),
      yandexMapConfigProvider.overrideWithValue(const YandexMapConfig(tilesKey: 'test-key')),
    ], child: MaterialApp(home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      change = setState;
      return TickerMode(enabled: visible, child: const MapPage(parishId: 'temple-b', focusRequest: '1'));
    })))));
    await tester.pumpAndSettle();
    change(() => visible = false);
    await tester.pump();
    response.complete([templeB]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-place-sheet')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
