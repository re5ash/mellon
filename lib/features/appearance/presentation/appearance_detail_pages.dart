import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/app_theme.dart';
import '../../../design_system/appearance_palette.dart';
import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/chat_surface.dart';
import '../../../design_system/theme_controller.dart';
import 'appearance_widgets.dart';
import 'chat_preview.dart';

class ChatWallpaperPage extends ConsumerStatefulWidget {
  const ChatWallpaperPage({super.key});
  @override
  ConsumerState<ChatWallpaperPage> createState() => _ChatWallpaperPageState();
}

class _ChatWallpaperPageState extends ConsumerState<ChatWallpaperPage> {
  late ChatWallpaper _draft;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _draft = ref.read(appearanceControllerProvider).wallpaper;
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    await ref.read(appearanceControllerProvider.notifier).setWallpaper(_draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ref.read(appearanceSaveErrorProvider) == null) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref
        .watch(appearanceControllerProvider)
        .copyWith(wallpaper: _draft);
    final colors = Theme.of(context).colorScheme;
    final error = ref.watch(appearanceSaveErrorProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Фон чата')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Отмена'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('apply-wallpaper'),
                  onPressed: _saving ? null : _apply,
                  child: Text(_saving ? 'Сохраняем…' : 'Применить'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final textScaler = MediaQuery.textScalerOf(context);
            final labelStyle = DefaultTextStyle.of(
              context,
            ).style.merge(Theme.of(context).textTheme.bodyMedium);
            final labelSize = textScaler.scale(labelStyle.fontSize ?? 14);
            final minTileWidth = 140 * (labelSize / 14).clamp(1.0, 3.0);
            final availableWidth = constraints.maxWidth - 32;
            final columns = ((availableWidth + gap) / (minTileWidth + gap))
                .floor()
                .clamp(1, 4)
                .toInt();
            final tileWidth = (availableWidth - gap * (columns - 1)) / columns;
            // Measure full labels once per page build, outside scroll layout.
            // Padding and the 2px border consume 20px inside each tile.
            var labelHeight = 0.0;
            final painter = TextPainter(
              textDirection: Directionality.of(context),
              textScaler: textScaler,
            );
            try {
              for (final wallpaper in ChatWallpaper.values) {
                painter.text = TextSpan(
                  text: AppearancePalette.wallpaperLabel(wallpaper),
                  style: labelStyle,
                );
                painter.layout(maxWidth: tileWidth - 20);
                if (painter.height > labelHeight) labelHeight = painter.height;
              }
            } finally {
              painter.dispose();
            }
            return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        ChatPreview(
                          key: const ValueKey('wallpaper-preview'),
                          settings: settings,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Выберите фон и посмотрите, как на нём выглядят сообщения.',
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  sliver: SliverGrid.builder(
                    itemCount: ChatWallpaper.values.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 100 + 8 + labelHeight.ceilToDouble() + 22,
                      crossAxisSpacing: gap,
                      mainAxisSpacing: gap,
                    ),
                    itemBuilder: (context, index) {
                      final wallpaper = ChatWallpaper.values[index];
                      final selected = _draft == wallpaper;
                      return Semantics(
                        button: true,
                        selected: selected,
                        child: InkWell(
                          key: ValueKey('wallpaper-${wallpaper.name}'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: _saving
                              ? null
                              : () => setState(() => _draft = wallpaper),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                width: 2,
                                color: selected
                                    ? colors.primary
                                    : colors.outlineVariant.withValues(
                                        alpha: .35,
                                      ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ChatBackdrop(
                                      settings: settings.copyWith(
                                        wallpaper: wallpaper,
                                      ),
                                      child: const SizedBox.expand(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppearancePalette.wallpaperLabel(wallpaper),
                                  textAlign: TextAlign.center,
                                  style: labelStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class NameColorPage extends ConsumerWidget {
  const NameColorPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceControllerProvider);
    return AppearanceFrame(
      title: 'Цвет имени',
      children: [
        AppearanceCard(
          padding: const EdgeInsets.all(12),
          child: ChatPreview(settings: settings),
        ),
        const AppearanceSection('Цвет имён в ваших чатах'),
        AppearanceCard(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < AppearancePalette.colors.length; i++)
                AccentDot(
                  key: ValueKey('name-color-$i'),
                  index: i,
                  selected: settings.nameColorIndex == i,
                  onTap: () => unawaited(
                    ref
                        .read(appearanceControllerProvider.notifier)
                        .setNameColor(i),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Этот цвет меняет отображение имён только на вашем устройстве.',
        ),
      ],
    );
  }
}

class NightAppearancePage extends ConsumerWidget {
  const NightAppearancePage({super.key});
  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    bool start,
  ) async {
    final settings = ref.read(appearanceControllerProvider);
    final minute = start ? settings.nightStart : settings.nightEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      helpText: start ? 'Включать ночную тему' : 'Возвращать дневную тему',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !context.mounted) return;
    final value = picked.hour * 60 + picked.minute;
    final current = ref.read(appearanceControllerProvider);
    if (value == (start ? current.nightEnd : current.nightStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Выберите разное время начала и окончания.'),
        ),
      );
      return;
    }
    await ref
        .read(appearanceControllerProvider.notifier)
        .setNightTime(start: start ? value : null, end: start ? null : value);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appearanceControllerProvider);
    final controller = ref.read(appearanceControllerProvider.notifier);
    final colors = Theme.of(context).colorScheme;
    return AppearanceFrame(
      title: 'Ночная тема',
      children: [
        AppearanceCard(
          padding: const EdgeInsets.all(12),
          child: Theme(
            data: AppTheme.forAppearance(settings, Brightness.dark),
            child: ChatPreview(
              settings: settings.copyWith(preset: AppearancePreset.night),
            ),
          ),
        ),
        const AppearanceSection('Автоматическое переключение'),
        AppearanceCard(
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('night-enabled'),
                title: const Text('По расписанию'),
                subtitle: const Text('По местному времени устройства'),
                value: settings.nightEnabled,
                onChanged: (value) =>
                    unawaited(controller.setNightEnabled(value)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('night-start'),
                title: const Text('Начало'),
                subtitle: Text(
                  AppearancePalette.timeLabel(settings.nightStart),
                ),
                trailing: const Icon(Icons.schedule_rounded),
                onTap: () => unawaited(_pickTime(context, ref, true)),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('night-end'),
                title: const Text('Окончание'),
                subtitle: Text(AppearancePalette.timeLabel(settings.nightEnd)),
                trailing: const Icon(Icons.wb_sunny_outlined),
                onTap: () => unawaited(_pickTime(context, ref, false)),
              ),
            ],
          ),
        ),
        const AppearanceSection('Ночная палитра'),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final palette in NightPalette.values)
              SizedBox(
                width: 156,
                child: Semantics(
                  button: true,
                  selected: settings.nightPalette == palette,
                  child: InkWell(
                    key: ValueKey('night-palette-${palette.name}'),
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => unawaited(controller.setNightPalette(palette)),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          width: 2,
                          color: settings.nightPalette == palette
                              ? colors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: Column(
                        children: [
                          Theme(
                            data: AppTheme.forAppearance(
                              settings.copyWith(nightPalette: palette),
                              Brightness.dark,
                            ),
                            child: ThemeMiniature(
                              settings: settings.copyWith(
                                preset: AppearancePreset.night,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(AppearancePalette.nightLabel(palette)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'В конце расписания вернётся выбранная дневная или системная тема. Ручной выбор темы отключает расписание.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
