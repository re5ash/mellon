import 'dart:convert';

enum MellonVisualTheme { current, cathedral, radiance, azure }

enum AppearancePreset { classic, day, night, system }

enum ChatWallpaper {
  automatic,
  plain,
  sky,
  olive,
  sand,
  lavender,
  templesDawn,
  templesLinen,
  templesNight,
  templesDusk,
  domesDawn,
  domesLinen,
  domesNight,
  domesDusk,
  crossesDawn,
  crossesLinen,
  crossesNight,
  crossesDusk,
  candlesDawn,
  candlesLinen,
  candlesNight,
  candlesDusk,
  ornamentsDawn,
  ornamentsLinen,
  ornamentsNight,
  ornamentsDusk,
  quietDawn,
  quietLinen,
  quietNight,
  quietDusk,
}

enum ClubBackground { current, sky, linen, olive, lavender, evening }

enum NightPalette { blue, graphite }

/// Device-local preferences stored together, so writes cannot mix revisions.
class AppearanceSettings {
  const AppearanceSettings({
    this.visualTheme = MellonVisualTheme.current,
    this.themeAccentOverride = false,
    this.preset = AppearancePreset.system,
    this.lightPreset = AppearancePreset.classic,
    this.accentIndex = 0,
    this.nameColorIndex = 4,
    this.messageBlocks = true,
    this.wallpaper = ChatWallpaper.automatic,
    this.clubBackground = ClubBackground.current,
    this.textStep = 2,
    this.nightEnabled = false,
    this.nightStart = 22 * 60,
    this.nightEnd = 7 * 60,
    this.nightPalette = NightPalette.blue,
  });
  static const storageKey = 'appearance_v1';
  static const textScales = [.85, .925, 1.0, 1.075, 1.15, 1.225, 1.3];
  static const colorCount = 8;
  final MellonVisualTheme visualTheme;
  final bool themeAccentOverride;
  final AppearancePreset preset, lightPreset;
  final int accentIndex, nameColorIndex, textStep;
  final bool messageBlocks, nightEnabled;
  final ChatWallpaper wallpaper;
  final ClubBackground clubBackground;
  final int nightStart, nightEnd;
  final NightPalette nightPalette;
  double get textScale =>
      textScales[textStep.clamp(0, textScales.length - 1).toInt()];

  bool isNightAt(DateTime localTime) {
    if (!nightEnabled || nightStart == nightEnd) return false;
    final minute = localTime.hour * 60 + localTime.minute;
    return nightStart < nightEnd
        ? minute >= nightStart && minute < nightEnd
        : minute >= nightStart || minute < nightEnd;
  }

  AppearancePreset effectivePreset(DateTime localTime) =>
      isNightAt(localTime) ? AppearancePreset.night : preset;

  AppearanceSettings copyWith({
    MellonVisualTheme? visualTheme,
    bool? themeAccentOverride,
    AppearancePreset? preset,
    AppearancePreset? lightPreset,
    int? accentIndex,
    int? nameColorIndex,
    bool? messageBlocks,
    ChatWallpaper? wallpaper,
    ClubBackground? clubBackground,
    int? textStep,
    bool? nightEnabled,
    int? nightStart,
    int? nightEnd,
    NightPalette? nightPalette,
  }) => AppearanceSettings(
    visualTheme: visualTheme ?? this.visualTheme,
    themeAccentOverride: themeAccentOverride ?? this.themeAccentOverride,
    preset: preset ?? this.preset,
    lightPreset: lightPreset ?? this.lightPreset,
    accentIndex: accentIndex ?? this.accentIndex,
    nameColorIndex: nameColorIndex ?? this.nameColorIndex,
    messageBlocks: messageBlocks ?? this.messageBlocks,
    wallpaper: wallpaper ?? this.wallpaper,
    clubBackground: clubBackground ?? this.clubBackground,
    textStep: textStep ?? this.textStep,
    nightEnabled: nightEnabled ?? this.nightEnabled,
    nightStart: nightStart ?? this.nightStart,
    nightEnd: nightEnd ?? this.nightEnd,
    nightPalette: nightPalette ?? this.nightPalette,
  );
  String encode() => jsonEncode({
    'version': 1,
    'visualTheme': visualTheme.name,
    'themeAccentOverride': themeAccentOverride,
    'preset': preset.name,
    'lightPreset': lightPreset.name,
    'accent': accentIndex,
    'nameColor': nameColorIndex,
    'blocks': messageBlocks,
    'wallpaper': wallpaper.name,
    'clubBackground': clubBackground.name,
    'textStep': textStep,
    'nightEnabled': nightEnabled,
    'nightStart': nightStart,
    'nightEnd': nightEnd,
    'nightPalette': nightPalette.name,
  });

  static AppearanceSettings decode(String? raw, {String? legacyTheme}) {
    final fallback = AppearanceSettings(
      preset: switch (legacyTheme) {
        'light' => AppearancePreset.day,
        'dark' => AppearancePreset.night,
        _ => AppearancePreset.system,
      },
      lightPreset: legacyTheme == 'light'
          ? AppearancePreset.day
          : AppearancePreset.classic,
    );
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1)
        return fallback;
      T option<T extends Enum>(String key, List<T> values, T defaultValue) =>
          values.where((item) => item.name == decoded[key]).firstOrNull ??
          defaultValue;
      int number(String key, int max, int defaultValue) {
        final value = decoded[key];
        return value is int && value >= 0 && value <= max
            ? value
            : defaultValue;
      }

      bool flag(String key, bool defaultValue) =>
          decoded[key] is bool ? decoded[key] as bool : defaultValue;
      final light = option(
        'lightPreset',
        AppearancePreset.values,
        fallback.lightPreset,
      );
      final start = number('nightStart', 1439, 1320);
      final end = number('nightEnd', 1439, 420);
      return AppearanceSettings(
        themeAccentOverride: flag('themeAccentOverride', false),
        visualTheme: option(
          'visualTheme',
          MellonVisualTheme.values,
          MellonVisualTheme.current,
        ),
        preset: option('preset', AppearancePreset.values, fallback.preset),
        lightPreset: light == AppearancePreset.day
            ? light
            : AppearancePreset.classic,
        accentIndex: number('accent', colorCount - 1, 0),
        nameColorIndex: number('nameColor', colorCount - 1, 4),
        messageBlocks: flag('blocks', true),
        wallpaper: option(
          'wallpaper',
          ChatWallpaper.values,
          ChatWallpaper.automatic,
        ),
        clubBackground: option(
          'clubBackground',
          ClubBackground.values,
          ClubBackground.current,
        ),
        textStep: number('textStep', textScales.length - 1, 2),
        nightEnabled: start != end && flag('nightEnabled', false),
        nightStart: start,
        nightEnd: end,
        nightPalette: option(
          'nightPalette',
          NightPalette.values,
          NightPalette.blue,
        ),
      );
    } on Object {
      return fallback;
    }
  }
}
