import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/app_theme.dart';
import '../../../design_system/appearance_palette.dart';
import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/club_backdrop.dart';
import '../../../design_system/mellon_theme.dart';
import '../../../design_system/theme_controller.dart';
import 'appearance_widgets.dart';
import 'chat_preview.dart';
import 'club_background_page.dart';
import 'theme_picker_page.dart';

class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceControllerProvider);
    final controller = ref.read(appearanceControllerProvider.notifier);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppearanceFrame(
      title: 'Оформление',
      children: [
        AppearanceCard(
          child: ListTile(
            key: const ValueKey('appearance-theme-picker'),
            leading: const Icon(Icons.style_outlined),
            title: const Text('Выбор темы'),
            subtitle: Text(MellonThemeStyle(settings.visualTheme).title),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const MellonThemePickerPage()),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Ваш приход. Ваше настроение.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        AppearanceCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChatPreview(
                key: const ValueKey('appearance-preview'),
                settings: settings,
              ),
              const AppearanceSection('Цветовая тема'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final preset in AppearancePreset.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 132,
                          child: Semantics(
                            button: true,
                            selected: settings.preset == preset,
                            child: InkWell(
                              key: ValueKey('appearance-theme-${preset.name}'),
                              borderRadius: BorderRadius.circular(18),
                              onTap: () =>
                                  unawaited(controller.setPreset(preset)),
                              child: Column(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(19),
                                      border: Border.all(
                                        width: 2.5,
                                        color: settings.preset == preset
                                            ? colors.primary
                                            : colors.outlineVariant.withValues(
                                                alpha: .35,
                                              ),
                                      ),
                                    ),
                                    child: Theme(
                                      data: AppTheme.forAppearance(
                                        settings.copyWith(preset: preset),
                                        preset == AppearancePreset.night
                                            ? Brightness.dark
                                            : Brightness.light,
                                      ),
                                      child: ThemeMiniature(
                                        settings: settings.copyWith(
                                          preset: preset,
                                        ),
                                        system:
                                            preset == AppearancePreset.system,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      2,
                                      8,
                                      2,
                                      4,
                                    ),
                                    child: Text(
                                      AppearancePalette.presetLabel(preset),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: settings.preset == preset
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (settings.preset == AppearancePreset.system)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Светлая и тёмная темы меняются вместе с устройством.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              const AppearanceSection('Акцентный цвет'),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < AppearancePalette.colors.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: AccentDot(
                          key: ValueKey('appearance-accent-$i'),
                          index: i,
                          selected: settings.accentIndex == i,
                          onTap: () => unawaited(controller.setAccent(i)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        const AppearanceSection('Детали оформления'),
        AppearanceCard(
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('appearance-dark'),
                title: const Text('Тёмное оформление'),
                secondary: Icon(
                  Icons.dark_mode_outlined,
                  color: colors.primary,
                ),
                value: theme.brightness == Brightness.dark,
                onChanged: (value) => unawaited(controller.setDark(value)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              SwitchListTile(
                key: const ValueKey('appearance-blocks'),
                title: const Text('Сообщения блоками'),
                secondary: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: colors.primary,
                ),
                value: settings.messageBlocks,
                onChanged: (value) => unawaited(controller.setBlocks(value)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('appearance-wallpaper'),
                leading: Icon(Icons.wallpaper_rounded, color: colors.primary),
                title: const Text('Фон чата'),
                subtitle: Text(
                  AppearancePalette.wallpaperLabel(settings.wallpaper),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/profile/appearance/wallpaper'),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('appearance-club-background'),
                leading: Icon(Icons.landscape_outlined, color: colors.primary),
                title: const Text('Выбрать фон'),
                subtitle: Text(
                  'Молодёжный клуб · ${clubBackgroundLabel(settings.clubBackground)}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ClubBackgroundPage()),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('appearance-name-color'),
                leading: Icon(
                  Icons.person_outline_rounded,
                  color: colors.primary,
                ),
                title: const Text('Цвет имени'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppearancePalette.color(
                          settings.nameColorIndex,
                          dark: theme.brightness == Brightness.dark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () => context.push('/profile/appearance/name-color'),
              ),
            ],
          ),
        ),
        const AppearanceSection('Размер текста'),
        AppearanceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  const ExcludeSemantics(
                    child: Text('A', style: TextStyle(fontSize: 13)),
                  ),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('appearance-text-size'),
                      value: settings.textStep.toDouble(),
                      min: 0,
                      max: (AppearanceSettings.textScales.length - 1)
                          .toDouble(),
                      divisions: AppearanceSettings.textScales.length - 1,
                      label: '${(settings.textScale * 100).round()}%',
                      semanticFormatterCallback: (value) =>
                          '${(AppearanceSettings.textScales[value.round()] * 100).round()} процентов',
                      onChanged: (value) =>
                          unawaited(controller.setTextStep(value.round())),
                    ),
                  ),
                  const ExcludeSemantics(
                    child: Text('A', style: TextStyle(fontSize: 25)),
                  ),
                ],
              ),
              Text(
                '${(settings.textScale * 100).round()}% · во всём приложении',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const AppearanceSection('Смена темы ночью'),
        AppearanceCard(
          child: ListTile(
            key: const ValueKey('appearance-night-settings'),
            leading: Icon(Icons.nights_stay_outlined, color: colors.primary),
            title: const Text('Настроить ночную тему'),
            subtitle: Text(AppearancePalette.scheduleLabel(settings)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/profile/appearance/night'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
          child: Text(
            'Изменения применяются сразу и сохраняются на этом устройстве.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
