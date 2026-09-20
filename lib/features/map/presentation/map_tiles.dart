import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/map_actions.dart';
import '../application/yandex_map_config.dart';
import '../application/yandex_tile_provider.dart';

// Override in tests so camera/gesture tests make no network tile requests.
final mapTileProvider = Provider<TileProvider Function()>(
  (ref) => YandexTileProvider.new,
);

ThemeData mellonMapTheme(BuildContext context) => Theme.of(context).copyWith(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff2c92d1),
    brightness: Brightness.light,
  ),
  textTheme: Theme.of(context).textTheme.apply(
    bodyColor: const Color(0xff19384e),
    displayColor: const Color(0xff19384e),
  ),
);

class MellonMapTiles extends ConsumerStatefulWidget {
  const MellonMapTiles({this.onError, super.key});
  final VoidCallback? onError;
  @override
  ConsumerState<MellonMapTiles> createState() => _MellonMapTilesState();
}

class _MellonMapTilesState extends ConsumerState<MellonMapTiles> {
  late final TileProvider _tiles = ref.read(mapTileProvider)();
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(yandexMapConfigProvider);
    if (!config.configured) {
      return const MapNotConfigured();
    }
    return TileLayer(
      urlTemplate: config.tileTemplate,
      userAgentPackageName: 'app.mellon.map',
      maxNativeZoom: 20,
      panBuffer: 0,
      tileProvider: _tiles,
      errorTileCallback: (_, _, _) => widget.onError?.call(),
    );
  }
}

class MapNotConfigured extends StatelessWidget {
  const MapNotConfigured({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Text(
        'Яндекс Карта пока не подключена.\nСкоро здесь появится карта храмов и событий.',
        key: ValueKey('map-not-configured'),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class MapAttribution extends ConsumerWidget {
  const MapAttribution({super.key});
  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> open(String url) async {
      try {
        await ref.read(mapActionsProvider).open(Uri.parse(url));
      } on Object {
        /* The attribution remains available. */
      }
    }

    return Material(
      color: Colors.white.withValues(alpha: .92),
      borderRadius: const BorderRadius.only(bottomRight: Radius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Открыть Яндекс Карты',
            child: Semantics(
              link: true,
              child: InkWell(
                onTap: () => open('https://yandex.ru/maps/'),
                child: Image.asset(
                  'assets/map/yandex_logo_ru.png',
                  // Keep the official asset's aspect ratio and built-in margins.
                  width: height * 352 / 192,
                  height: height,
                  semanticLabel: 'Яндекс Карты',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'О карте',
            iconSize: 15,
            color: const Color(0xff536575),
            constraints: const BoxConstraints.tightFor(
              width: height,
              height: height,
            ),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            padding: const EdgeInsets.all(6),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Яндекс Карты'),
                content: const Text(
                  '© Яндекс. Данные карты предоставлены Яндексом.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => open('https://yandex.ru/legal/maps_api/'),
                    child: const Text('Условия использования'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Закрыть'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
    );
  }
}
