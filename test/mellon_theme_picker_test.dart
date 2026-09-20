import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/shell/club_navigation_bar.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/design_system/components/mellon_theme_backdrop.dart';
import 'package:moy_prihod/design_system/theme_controller.dart';
import 'package:moy_prihod/features/appearance/presentation/theme_picker_page.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'package:moy_prihod/features/community/club_dashboard_repository.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

import 'club_dashboard_test.dart' show RecordingClubChats, dashboardFixture;

class _Store implements AppearanceStore {
  String? value;
  bool fail = false;
  @override
  Future<void> write(String data) async {
    if (fail) throw StateError('storage unavailable');
    value = data;
  }
}

Future<ProviderContainer> picker(
  WidgetTester tester,
  _Store store, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appearanceStoreProvider.overrideWithValue(store),
        initialAppearanceProvider.overrideWithValue(
          const AppearanceSettings(
            wallpaper: ChatWallpaper.candlesNight,
            messageBlocks: false,
          ),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: AppTheme.forAppearance(
            ref.watch(appearanceControllerProvider),
            Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const MellonThemePickerPage(),
                  ),
                ),
                child: const Text('Открыть выбор'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  await tester.tap(find.text('Открыть выбор'));
  await tester.pumpAndSettle();
  return container;
}

void phone(WidgetTester tester, {double width = 393}) {
  tester.view.physicalSize = Size(width, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'old and future settings retain chats and default to current styling',
    () {
      final old = AppearanceSettings.decode(
        '{"version":1,"wallpaper":"candlesNight","visualTheme":"future"}',
      );
      expect(old.visualTheme, MellonVisualTheme.current);
      expect(old.wallpaper, ChatWallpaper.candlesNight);
      for (final kind in MellonVisualTheme.values) {
        final saved = AppearanceSettings.decode(
          old.copyWith(visualTheme: kind).encode(),
        );
        expect(saved.visualTheme, kind);
        expect(saved.wallpaper, old.wallpaper);
      }
    },
  );

  testWidgets('three live previews, draft selection and cancel never save', (
    tester,
  ) async {
    phone(tester);
    final store = _Store();
    final container = await picker(tester, store);
    for (final name in ['cathedral', 'radiance', 'azure']) {
      expect(find.byKey(ValueKey('mellon-theme-$name')), findsOneWidget);
    }
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('mellon-theme-done')))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('mellon-theme-radiance')));
    await tester.pumpAndSettle();
    expect(
      container.read(appearanceControllerProvider).visualTheme,
      MellonVisualTheme.current,
    );
    expect(store.value, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(MellonThemePickerPage), findsNothing);
    expect(store.value, isNull);
  });

  testWidgets(
    'Done applies and restores theme while retaining chat preferences',
    (tester) async {
      phone(tester);
      final store = _Store();
      final container = await picker(tester, store);
      await tester.tap(find.byKey(const ValueKey('mellon-theme-azure')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mellon-theme-done')));
      await tester.pumpAndSettle();
      expect(find.byType(MellonThemePickerPage), findsNothing);
      final saved = AppearanceSettings.decode(store.value);
      expect(saved.visualTheme, MellonVisualTheme.azure);
      expect(saved.wallpaper, ChatWallpaper.candlesNight);
      expect(saved.messageBlocks, isFalse);
      final restart = ProviderContainer(
        overrides: [initialAppearanceProvider.overrideWithValue(saved)],
      );
      addTearDown(restart.dispose);
      expect(
        restart.read(appearanceControllerProvider).visualTheme,
        container.read(appearanceControllerProvider).visualTheme,
      );
    },
  );

  testWidgets('failed storage leaves retry available and succeeds on retry', (
    tester,
  ) async {
    phone(tester);
    final store = _Store()..fail = true;
    await picker(tester, store);
    await tester.tap(find.byKey(const ValueKey('mellon-theme-cathedral')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mellon-theme-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('theme-save-error')), findsOneWidget);
    expect(store.value, isNull);
    store.fail = false;
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.byType(MellonThemePickerPage), findsNothing);
    expect(
      AppearanceSettings.decode(store.value).visualTheme,
      MellonVisualTheme.cathedral,
    );
  });

  testWidgets(
    'large text and reduced motion keep selection and actions reachable',
    (tester) async {
      phone(tester, width: 320);
      await picker(tester, _Store(), scale: 1.8);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mellon-theme-radiance')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mellon-theme-done')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing theme retains active club tab, live data and dashboard state',
    (tester) async {
      phone(tester);
      final repo = RecordingClubChats(dashboardFixture(manager: true));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appearanceStoreProvider.overrideWithValue(_Store()),
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser('actor')),
            ),
            communityRepositoryProvider.overrideWithValue(repo),
            clubDashboardProvider('club-a')
                .overrideWith((ref) async => repo.data),
          ],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp(
              theme: AppTheme.forAppearance(
                ref.watch(appearanceControllerProvider),
                Brightness.light,
              ),
              home: Scaffold(
                body: MellonThemeBackdrop(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClubDashboard(club: 'club-a', onChooseClub: () {}),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(ClubDashboard));
      final container = ProviderScope.containerOf(element, listen: false);
      await tester.ensureVisible(find.byKey(const ValueKey('club-tab-1')));
      await tester.tap(find.byKey(const ValueKey('club-tab-1')));
      await tester.pumpAndSettle();
      for (final kind in [
        MellonVisualTheme.cathedral,
        MellonVisualTheme.radiance,
        MellonVisualTheme.azure,
      ]) {
        await container
            .read(appearanceControllerProvider.notifier)
            .setVisualTheme(kind);
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(ClubDashboard)), same(element));
        expect(find.byKey(const ValueKey('add-club-schedule')), findsOneWidget);
        expect(
          find.text('Молодёжный клуб храма Александра Невского'),
          findsOneWidget,
        );
        expect(repo.requests, isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'themed navigation keeps routing callbacks and readable solid high contrast',
    (tester) async {
      phone(tester, width: 320);
      final taps = <int>[];
      for (final kind in [
        MellonVisualTheme.cathedral,
        MellonVisualTheme.radiance,
        MellonVisualTheme.azure,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.forAppearance(
              AppearanceSettings(visualTheme: kind),
              Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(
                highContrast: true,
                disableAnimations: true,
              ),
              child: Scaffold(
                bottomNavigationBar: ClubNavigationBar(
                  selectedIndex: 1,
                  onSelected: taps.add,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.widget<Material>(
          find.byKey(const ValueKey('floating-navigation-surface')),
        );
        expect(surface.color!.a, 1);
        await tester.tap(find.byKey(const ValueKey('navigation-button-2')));
        expect(taps.last, 2);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
