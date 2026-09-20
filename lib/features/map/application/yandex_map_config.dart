import 'package:flutter_riverpod/flutter_riverpod.dart';

final yandexMapConfigProvider = Provider<YandexMapConfig>(
  (ref) => const YandexMapConfig(
    tilesKey: String.fromEnvironment('YANDEX_TILES_API_KEY'),
  ),
);

class YandexMapConfig {
  const YandexMapConfig({required this.tilesKey});
  final String tilesKey;
  bool get configured =>
      tilesKey.trim().isNotEmpty &&
      !tilesKey.contains('REPLACE') &&
      !tilesKey.contains('YOUR_');

  // FlutterMap uses spherical Web Mercator. Yandex's default is elliptical:
  // explicitly requesting web_mercator keeps the photo pin on the temple.
  String get tileTemplate =>
      'https://tiles.api-maps.yandex.ru/v1/tiles/'
      '?apikey=${Uri.encodeQueryComponent(tilesKey.trim())}'
      '&lang=ru_RU&l=map&projection=web_mercator&maptype=future_map'
      '&x={x}&y={y}&z={z}';
}
