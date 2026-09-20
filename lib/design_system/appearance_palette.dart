import 'package:flutter/material.dart';

import 'appearance_settings.dart';
import 'chat_wallpaper_catalog.dart';

abstract final class AppearancePalette {
  static const colors = <({String label, Color color})>[
    (label: 'Небесный', color: Color(0xFF246CA9)),
    (label: 'Бирюзовый', color: Color(0xFF14786E)),
    (label: 'Оливковый', color: Color(0xFF467631)),
    (label: 'Медовый', color: Color(0xFF976023)),
    (label: 'Лавандовый', color: Color(0xFF7456AE)),
    (label: 'Розовый', color: Color(0xFFA5466A)),
    (label: 'Индиго', color: Color(0xFF495DA5)),
    (label: 'Терракотовый', color: Color(0xFFA85533)),
  ];
  static Color color(int index, {bool dark = false}) {
    final base = colors[index.clamp(0, colors.length - 1).toInt()].color;
    return dark ? Color.lerp(base, Colors.white, .4)! : base;
  }

  static String presetLabel(AppearancePreset preset) => switch (preset) {
    AppearancePreset.classic => 'Классическая',
    AppearancePreset.day => 'Дневная',
    AppearancePreset.night => 'Ночная',
    AppearancePreset.system => 'Системная',
  };
  static String wallpaperLabel(ChatWallpaper wallpaper) => switch (wallpaper) {
    ChatWallpaper.automatic => 'В цвет темы',
    ChatWallpaper.plain => 'Без узора',
    ChatWallpaper.sky => 'Небо',
    ChatWallpaper.olive => 'Оливковые ветви',
    ChatWallpaper.sand => 'Тёплый свет',
    ChatWallpaper.lavender => 'Лаванда',
    _ => ChatWallpapers.designs[wallpaper]!.label,
  };
  static String nightLabel(NightPalette palette) => switch (palette) {
    NightPalette.blue => 'Синяя ночь',
    NightPalette.graphite => 'Графит',
  };
  static String timeLabel(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  static String scheduleLabel(AppearanceSettings settings) =>
      settings.nightEnabled
      ? '${timeLabel(settings.nightStart)} — ${timeLabel(settings.nightEnd)}'
      : 'Не используется';
}
