import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/map_place.dart';

final mapActionsProvider = Provider<MapActions>((ref) => const MapActions());

class MapActions {
  const MapActions();
  Future<LatLng> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AppFailure('Включите геолокацию в настройках устройства.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const AppFailure(
          'Разрешение на геолокацию не получено. Попробуйте ещё раз.',
        ),
      );
    }
    if (permission == LocationPermission.denied) {
      throw const AppFailure(
        'Доступ к геолокации не разрешён. Картой можно пользоваться без него.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AppFailure(
        'Разрешите геолокацию для Mellon в настройках браузера или приложения.',
      );
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      throw const AppFailure(
        'Не удалось определить местоположение. Попробуйте ещё раз.',
      );
    }
  }

  Future<void> open(Uri uri) async {
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    )) {
      throw const AppFailure('Не удалось открыть карту. Попробуйте ещё раз.');
    }
  }

  /// Returns true when a browser without system sharing copied the link.
  Future<bool> share(MapPlace place, Rect origin) async {
    final text = '${place.title}\n${place.address}\n${placeLink(place)}';
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: text,
          title: place.title,
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      return false;
    } on Exception {
      // Clipboard is available on platforms without a native share sheet.
    } on UnimplementedError {
      // Web Share is not supported by every desktop browser.
    }
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }
}
