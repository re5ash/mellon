import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_branding.dart';
import '../design_system/app_theme.dart';
import '../design_system/appearance_settings.dart';
import '../design_system/theme_controller.dart';
import '../features/community/community_repository.dart';
import 'router/app_router.dart';

/// Compose app size with the device's accessible (possibly nonlinear) scaling.
class AppearanceTextScaler extends TextScaler {
  const AppearanceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppearanceTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

class MoyPrihodApp extends ConsumerWidget {
  const MoyPrihodApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceControllerProvider);
    return MaterialApp.router(
      title: appDisplayName(
        ref.watch(appConfigurationProvider).asData?.value['app_name'],
      ),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forAppearance(appearance, Brightness.light),
      darkTheme: AppTheme.forAppearance(appearance, Brightness.dark),
      themeMode: ref.watch(effectiveThemeModeProvider),
      themeAnimationDuration:
          appearance.visualTheme == MellonVisualTheme.current ||
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 180),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: AppearanceTextScaler(
              media.textScaler,
              appearance.textScale,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
