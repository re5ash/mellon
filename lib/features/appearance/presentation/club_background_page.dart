import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/club_backdrop.dart';
import '../../../design_system/components/club_glass_surface.dart';
import '../../../design_system/theme_controller.dart';

class ClubBackgroundPage extends ConsumerStatefulWidget {
  const ClubBackgroundPage({super.key});
  @override
  ConsumerState<ClubBackgroundPage> createState() => _ClubBackgroundPageState();
}

class _ClubBackgroundPageState extends ConsumerState<ClubBackgroundPage> {
  late ClubBackground _draft;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(appearanceControllerProvider).clubBackground;
  }

  Future<void> _apply() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    await ref
        .read(appearanceControllerProvider.notifier)
        .setClubBackground(_draft);
    if (!mounted) return;
    final error = ref.read(appearanceSaveErrorProvider);
    if (error == null) {
      setState(() => _saving = false);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final applied = ref.watch(
      appearanceControllerProvider.select((value) => value.clubBackground),
    );
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(title: const Text('Выбрать фон')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Только для экрана «Молодёжный клуб».',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 12),
                        Semantics(
                          label:
                              'Предпросмотр фона: ${clubBackgroundLabel(_draft)}',
                          child: ExcludeSemantics(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: ColoredBox(
                                color: Theme.of(context)
                                    .scaffoldBackgroundColor,
                                child: SizedBox(
                                  height: 228,
                                  child: ClubBackdrop(
                                    key: const ValueKey(
                                      'club-background-preview',
                                    ),
                                    background: _draft,
                                    child: const _ClubPreview(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        for (final option in ClubBackground.values)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Semantics(
                              selected: _draft == option,
                              button: true,
                              child: ClubGlassSurface(
                                selected: _draft == option,
                                child: ListTile(
                                  key: ValueKey(
                                    'club-background-${option.name}',
                                  ),
                                  enabled: !_saving,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ColoredBox(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      child: SizedBox.square(
                                        dimension: 44,
                                        child: ClubBackdrop(
                                          background: option,
                                          child: Center(
                                            child: Icon(
                                              option == ClubBackground.current
                                                  ? Icons.restore_rounded
                                                  : Icons.landscape_outlined,
                                              color: colors.primary,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  title: Text(clubBackgroundLabel(option)),
                                  subtitle: option == applied
                                      ? const Text('Сейчас установлен')
                                      : null,
                                  trailing: _draft == option
                                      ? Icon(
                                          Icons.check_circle,
                                          color: colors.primary,
                                        )
                                      : const Icon(Icons.circle_outlined),
                                  onTap: _saving
                                      ? null
                                      : () => setState(() => _draft = option),
                                ),
                              ),
                            ),
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
                          Text(_error!, style: TextStyle(color: colors.error)),
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
                                key: const ValueKey('apply-club-background'),
                                onPressed: _saving ? null : _apply,
                                child: Text(
                                  _saving ? 'Сохраняем…' : 'Применить',
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

/// Layout-only preview; it never fetches or creates demo club records.
class _ClubPreview extends StatelessWidget {
  const _ClubPreview();
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget line(double width) => Container(
      width: width,
      height: 7,
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          ClubGlassSurface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.church_rounded, size: 48, color: colors.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        line(110),
                        const SizedBox(height: 10),
                        line(70),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final icon in [
                Icons.chat,
                Icons.calendar_month,
                Icons.event,
                Icons.volunteer_activism,
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ClubGlassSurface(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(icon, size: 23, color: colors.primary),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClubGlassSurface(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.chat_bubble_rounded,
                    size: 25,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: line(150)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
