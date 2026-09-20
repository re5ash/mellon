import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_settings.dart';

final preferencesProvider = Provider<SharedPreferencesAsync>(
  (ref) => SharedPreferencesAsync(),
);
final initialAppearanceProvider = Provider<AppearanceSettings>(
  (ref) => const AppearanceSettings(),
);

abstract interface class AppearanceStore {
  Future<void> write(String value);
}

class PreferencesAppearanceStore implements AppearanceStore {
  PreferencesAppearanceStore(this.preferences);
  final SharedPreferencesAsync preferences;
  @override
  Future<void> write(String value) =>
      preferences.setString(AppearanceSettings.storageKey, value);
}

Future<AppearanceSettings> loadAppearance(
  SharedPreferencesAsync preferences,
) async {
  try {
    return AppearanceSettings.decode(
      await preferences.getString(AppearanceSettings.storageKey),
      legacyTheme: await preferences.getString('theme_mode'),
    );
  } on Object {
    return const AppearanceSettings();
  }
}

final appearanceStoreProvider = Provider<AppearanceStore>(
  (ref) => PreferencesAppearanceStore(ref.watch(preferencesProvider)),
);
final appearanceControllerProvider =
    NotifierProvider<AppearanceController, AppearanceSettings>(
      AppearanceController.new,
    );
final appearanceSaveErrorProvider =
    NotifierProvider<AppearanceSaveError, String?>(AppearanceSaveError.new);

class AppearanceSaveError extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

class AppearanceController extends Notifier<AppearanceSettings> {
  Future<void> _writes = Future<void>.value();
  bool _disposed = false;
  int _revision = 0;
  @override
  AppearanceSettings build() {
    ref.onDispose(() => _disposed = true);
    return ref.read(initialAppearanceProvider);
  }

  Future<void> _update(AppearanceSettings value) {
    state = value; // Apply first; storage speed must not delay the interface.
    final revision = ++_revision;
    final store = ref.read(appearanceStoreProvider);
    final encoded = value.encode();
    _writes = _writes.then((_) async {
      try {
        await store.write(encoded);
        if (!_disposed && revision == _revision)
          ref.read(appearanceSaveErrorProvider.notifier).set(null);
      } on Object {
        if (!_disposed && revision == _revision) {
          ref
              .read(appearanceSaveErrorProvider.notifier)
              .set(
                'Не удалось запомнить оформление. Проверьте доступ к хранилищу устройства и повторите.',
              );
        }
      }
    });
    return _writes;
  }

  Future<void> get flushed => _writes;
  Future<void> retrySave() => _update(state);
  Future<void> setPreset(AppearancePreset preset) => _update(
    state.copyWith(
      preset: preset,
      lightPreset:
          preset == AppearancePreset.classic || preset == AppearancePreset.day
          ? preset
          : state.lightPreset,
      nightEnabled: false,
    ),
  );
  Future<void> setDark(bool dark) =>
      setPreset(dark ? AppearancePreset.night : state.lightPreset);
  Future<void> setAccent(int value) => _update(
    state.copyWith(
      themeAccentOverride: true,
      accentIndex: value.clamp(0, AppearanceSettings.colorCount - 1).toInt(),
    ),
  );
  Future<void> setNameColor(int value) => _update(
    state.copyWith(
      nameColorIndex: value.clamp(0, AppearanceSettings.colorCount - 1).toInt(),
    ),
  );
  Future<void> setBlocks(bool value) =>
      _update(state.copyWith(messageBlocks: value));
  Future<void> setWallpaper(ChatWallpaper value) =>
      _update(state.copyWith(wallpaper: value));
  Future<void> setVisualTheme(MellonVisualTheme value) => _update(
    state.copyWith(
      visualTheme: value,
      themeAccentOverride: false,
      clubBackground: ClubBackground.current,
      // These three references are light compositions. A later explicit choice
      // of dark mode remains supported and does not forget the visual theme.
      preset: AppearancePreset.day,
      lightPreset: AppearancePreset.day,
      nightEnabled: false,
    ),
  );
  Future<void> setClubBackground(ClubBackground value) =>
      _update(state.copyWith(clubBackground: value));
  Future<void> setTextStep(int value) => _update(
    state.copyWith(
      textStep: value
          .clamp(0, AppearanceSettings.textScales.length - 1)
          .toInt(),
    ),
  );
  Future<void> setNightPalette(NightPalette value) =>
      _update(state.copyWith(nightPalette: value));
  Future<void> setNightEnabled(bool value) => _update(
    state.copyWith(
      nightEnabled: value,
      preset: value && state.preset == AppearancePreset.night
          ? state.lightPreset
          : state.preset,
    ),
  );
  Future<void> setNightTime({int? start, int? end}) {
    final from = start ?? state.nightStart;
    final until = end ?? state.nightEnd;
    if (from == until || from < 0 || from > 1439 || until < 0 || until > 1439)
      return Future<void>.value();
    return _update(state.copyWith(nightStart: from, nightEnd: until));
  }
}

final appearanceNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final appearanceClockProvider = NotifierProvider<AppearanceClock, DateTime>(
  AppearanceClock.new,
);

/// Tick at local minute boundaries and after returning to the app.
class AppearanceClock extends Notifier<DateTime> {
  @override
  DateTime build() {
    final enabled = ref.watch(
      appearanceControllerProvider.select((s) => s.nightEnabled),
    );
    final now = ref.read(appearanceNowProvider);
    if (enabled) {
      Timer? timer;
      var disposed = false;
      void tick() {
        if (disposed) return;
        final current = now();
        state = current;
        timer?.cancel();
        timer = Timer(
          Duration(
            milliseconds: 60000 - current.second * 1000 - current.millisecond,
          ),
          tick,
        );
      }

      final current = now();
      timer = Timer(
        Duration(
          milliseconds: 60000 - current.second * 1000 - current.millisecond,
        ),
        tick,
      );
      final listener = AppLifecycleListener(onResume: tick);
      ref.onDispose(() {
        disposed = true;
        timer?.cancel();
        listener.dispose();
      });
    }
    return now();
  }
}

final effectiveThemeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(appearanceControllerProvider);
  return switch (settings.effectivePreset(ref.watch(appearanceClockProvider))) {
    AppearancePreset.system => ThemeMode.system,
    AppearancePreset.night => ThemeMode.dark,
    _ => ThemeMode.light,
  };
});
