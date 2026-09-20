import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/app_theme.dart';
import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/club_glass_surface.dart';
import '../../../design_system/components/mellon_theme_backdrop.dart';
import '../../../design_system/mellon_theme.dart';
import '../../../design_system/theme_controller.dart';
import '../../chats/presentation/chat_icon_badge.dart';

class MellonThemePickerPage extends ConsumerStatefulWidget {
  const MellonThemePickerPage({super.key});
  @override
  ConsumerState<MellonThemePickerPage> createState() =>
      _MellonThemePickerPageState();
}

class _MellonThemePickerPageState extends ConsumerState<MellonThemePickerPage> {
  static const choices = [
    MellonVisualTheme.cathedral,
    MellonVisualTheme.radiance,
    MellonVisualTheme.azure,
  ];
  MellonVisualTheme? _draft;
  bool _saving = false;
  bool _warming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final current = ref.read(appearanceControllerProvider).visualTheme;
    _draft = choices.contains(current) ? current : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_warming) return;
    _warming = true;
    // Assets are tiny and local. Never delay app startup to load unchosen themes.
    for (final choice in choices) {
      unawaited(
        precacheImage(
          AssetImage(MellonThemeStyle(choice).asset),
          context,
          onError: (_, _) {},
        ),
      );
    }
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    Object? assetError;
    await precacheImage(
      AssetImage(MellonThemeStyle(draft).asset),
      context,
      onError: (error, _) => assetError = error,
    );
    if (!mounted) return;
    if (assetError != null) {
      setState(() {
        _saving = false;
        _error = 'Фон не найден. Переустановите обновление тем.';
      });
      return;
    }
    await ref.read(appearanceControllerProvider.notifier).setVisualTheme(draft);
    if (!mounted) return;
    final error = ref.read(appearanceSaveErrorProvider);
    setState(() {
      _saving = false;
      _error = error;
    });
    if (error == null) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final applied = ref.watch(appearanceControllerProvider).visualTheme;
    final selected = _draft ?? MellonVisualTheme.azure;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Выбор темы')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text('Выберите оформление и нажмите «Готово».'),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < choices.length; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(
                                child: Semantics(
                                  button: true,
                                  selected: _draft == choices[i],
                                  label: MellonThemeStyle(choices[i]).title,
                                  child: InkWell(
                                    key: ValueKey(
                                      'mellon-theme-${choices[i].name}',
                                    ),
                                    borderRadius: BorderRadius.circular(15),
                                    onTap: _saving
                                        ? null
                                        : () => setState(() {
                                            _draft = choices[i];
                                            _error = null;
                                          }),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 140,
                                                ),
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              15,
                                            ),
                                            border: Border.all(
                                              width: 2,
                                              color: _draft == choices[i]
                                                  ? colors.primary
                                                  : colors.outlineVariant,
                                            ),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: MellonThemePreview(
                                              theme: choices[i],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          MellonThemeStyle(choices[i]).title,
                                          textAlign: TextAlign.center,
                                        ),
                                        if (_draft == choices[i])
                                          Icon(
                                            Icons.check_circle,
                                            color: colors.primary,
                                          ),
                                        if (applied == choices[i])
                                          const Text(
                                            'Применена',
                                            textAlign: TextAlign.center,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Предпросмотр: ${MellonThemeStyle(selected).title}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 390),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: MellonThemePreview(theme: selected),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Превью показывает оформление. В приложении останутся ваши фото, чаты и данные.',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _error!,
                              key: const ValueKey('theme-save-error'),
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Отмена'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('mellon-theme-done'),
                                onPressed: _saving || _draft == null
                                    ? null
                                    : _apply,
                                child: Text(
                                  _saving
                                      ? 'Сохраняем…'
                                      : _error != null
                                      ? 'Повторить'
                                      : 'Готово',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A read-only miniature made of the same surfaces/icons as the live screen.
/// It has no repositories, subscriptions, navigation callbacks or fake records.
class MellonThemePreview extends StatelessWidget {
  const MellonThemePreview({required this.theme, super.key});
  final MellonVisualTheme theme;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 360 / 660,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 360,
            height: 660,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.noScaling,
                padding: EdgeInsets.zero,
              ),
              child: Theme(
                data: AppTheme.forAppearance(
                  AppearanceSettings(visualTheme: theme),
                  Brightness.light,
                ),
                child: const _PreviewBody(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody();
  @override
  Widget build(BuildContext context) {
    final design = MellonThemeStyle.of(context);
    final text = Theme.of(context).textTheme;
    return MellonThemeBackdrop(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: design.pageInset,
          vertical: 20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => FittedBox(
                  // The preview's typography can change its natural height.
                  // Fit the complete body above the fixed navigation instead
                  // of clipping cards or assuming a particular font metric.
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.church_outlined,
                              color: design.classical
                                  ? Colors.white
                                  : design.ink,
                            ),
                            Expanded(
                              child: Text(
                                'Mellon',
                                textAlign: TextAlign.center,
                                style: text.titleLarge?.copyWith(
                                  color: design.classical
                                      ? Colors.white
                                      : design.ink,
                                ),
                              ),
                            ),
                            const Icon(Icons.notifications_none),
                            const SizedBox(width: 12),
                            const Icon(Icons.more_vert),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClubGlassSurface(
                          flat: design.luminous,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: design.luminous ? 68 : 86,
                                  height: design.luminous ? 68 : 86,
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: design.halo,
                                      width: design.haloWidth,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x99fff4d7),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/map/alexander_nevsky.jpg',
                                      fit: BoxFit.cover,
                                      cacheWidth: 180,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Молодёжный клуб',
                                        style: text.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                          color: design.accent.withValues(
                                            alpha: .1,
                                          ),
                                          border: Border.all(
                                            color: Colors.white,
                                          ),
                                        ),
                                        child: Text(
                                          'ⓘ  О храме  ›',
                                          style: TextStyle(
                                            color: design.accent,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.place_outlined,
                                            size: 15,
                                            color: design.muted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Адрес храма',
                                            style: TextStyle(
                                              color: design.muted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClubGlassSurface(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                MellonFeatureIcon(
                                  icon: Icons.calendar_month,
                                  color: design.accent,
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Ближайшее событие',
                                    style: text.titleSmall,
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: design.accent),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (var i = 0; i < 4; i++) ...[
                              if (i > 0) const SizedBox(width: 5),
                              Expanded(
                                child: ClubGlassSurface(
                                  selected: i == 0,
                                  radius: 14,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Column(
                                      children: [
                                        MellonFeatureIcon(
                                          icon: const [
                                            Icons.chat_rounded,
                                            Icons.calendar_month,
                                            Icons.event_available,
                                            Icons.volunteer_activism,
                                          ][i],
                                          color: const [
                                            Color(0xff178cff),
                                            Color(0xff00b8aa),
                                            Color(0xffff7625),
                                            Color(0xfff52e97),
                                          ][i],
                                          size: 23,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          const [
                                            'Чаты',
                                            'Расписание',
                                            'События',
                                            'Помощь',
                                          ][i],
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClubGlassSurface(
                          flat: !design.luminous,
                          child: Column(
                            children: [
                              for (var i = 0; i < 4; i++)
                                Padding(
                                  padding: EdgeInsets.only(
                                    bottom: design.luminous ? 0 : 6,
                                  ),
                                  child: ClubGlassSurface(
                                    flat: design.luminous,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        children: [
                                          ChatIconBadge(
                                            iconKey: const [
                                              'chat',
                                              'news',
                                              'help',
                                              'book',
                                            ][i],
                                            size: design.luminous ? 42 : 32,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Название чата',
                                                  style: text.titleSmall
                                                      ?.copyWith(
                                                        fontFamily: design
                                                            .headingFamily,
                                                      ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  'Последнее сообщение',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: design.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Icon(
                                            Icons.more_vert,
                                            color: design.accent,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClubGlassSurface(
              radius: 99,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                        flex: i == 1 ? 2 : 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: i == 1
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      design.accent.withValues(alpha: .17),
                                      Colors.white,
                                    ],
                                  ),
                                  border: Border.all(color: Colors.white),
                                  boxShadow: [
                                    BoxShadow(
                                      color: design.accent.withValues(
                                        alpha: .2,
                                      ),
                                      blurRadius: 6,
                                    ),
                                  ],
                                )
                              : null,
                          child: Column(
                            children: [
                              Icon(
                                const [
                                  Icons.view_day_outlined,
                                  Icons.church,
                                  Icons.place_outlined,
                                ][i],
                                color: design.accent,
                                size: 23,
                              ),
                              Text(
                                const ['Лента', 'Молодёжный клуб', 'Карта'][i],
                                style: TextStyle(
                                  fontSize: 10,
                                  color: design.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
