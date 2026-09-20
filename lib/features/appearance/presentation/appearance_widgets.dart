import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/appearance_palette.dart';
import '../../../design_system/appearance_settings.dart';
import '../../../design_system/components/chat_surface.dart';
import '../../../design_system/theme_controller.dart';

class AppearanceFrame extends ConsumerWidget {
  const AppearanceFrame({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(appearanceSaveErrorProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/profile'),
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 720,
            child: ListView(
              key: PageStorageKey('appearance-$title'),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MaterialBanner(
                      content: Text(error),
                      actions: [
                        TextButton(
                          onPressed: () => unawaited(
                            ref
                                .read(appearanceControllerProvider.notifier)
                                .retrySave(),
                          ),
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  ),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppearanceCard extends StatelessWidget {
  const AppearanceCard({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    child: Padding(padding: padding, child: child),
  );
}

class AppearanceSection extends StatelessWidget {
  const AppearanceSection(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
    child: Text(
      title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class AccentDot extends StatelessWidget {
  const AccentDot({
    required this.index,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final int index;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = AppearancePalette.colors[index].color;
    return Semantics(
      button: true,
      selected: selected,
      label: AppearancePalette.colors[index].label,
      child: Tooltip(
        message: AppearancePalette.colors[index].label,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2.5,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 22,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeMiniature extends StatelessWidget {
  const ThemeMiniature({
    required this.settings,
    this.system = false,
    super.key,
  });
  final AppearanceSettings settings;
  final bool system;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 78,
        child: ChatBackdrop(
          settings: settings,
          child: Stack(
            children: [
              if (system)
                Positioned.fill(
                  left: 58,
                  child: ColoredBox(
                    color: const Color(0xFF182C3C).withValues(alpha: .8),
                  ),
                ),
              Positioned(
                left: 10,
                top: 15,
                child: Container(
                  width: 63,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 15,
                child: Container(
                  width: 57,
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
