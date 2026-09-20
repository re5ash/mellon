import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/shell/club_navigation_bar.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/design_system/components/club_backdrop.dart';
import 'package:moy_prihod/design_system/theme_controller.dart';
import 'package:moy_prihod/features/appearance/presentation/club_background_page.dart';
import 'package:moy_prihod/features/community/club_photo.dart';

import 'club_dashboard_test.dart'
    show RecordingClubChats, dashboardFixture, mountDashboard, tapVisible;

class _Store implements AppearanceStore {
  String? saved;
  bool fail = false;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('unavailable');
    saved = value;
  }
}

Future<ProviderContainer> mountPicker(
  WidgetTester tester,
  _Store store, {
  double scale = 1,
  AppearanceSettings initial = const AppearanceSettings(),
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appearanceStoreProvider.overrideWithValue(store),
        initialAppearanceProvider.overrideWithValue(initial),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ClubBackgroundPage()),
                ),
                child: const Text('Выбор'),
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
  await tester.tap(find.text('Выбор'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> choose(WidgetTester tester, ClubBackground background) async {
  final finder = find.byKey(ValueKey('club-background-${background.name}'));
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  // Scroll offsets change before layout; cached tiles can still lie behind
  // the fixed action bar. Settle, then center the actual tap target.
  await tester.pumpAndSettle();
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: finder, matching: find.byIcon(Icons.check_circle)),
    findsOneWidget,
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'old preferences keep their current background and all chat settings',
    () {
      final settings = AppearanceSettings.decode(
        '{"version":1,"wallpaper":"candlesNight","accent":3,"blocks":false}',
      );
      expect(settings.clubBackground, ClubBackground.current);
      for (final value in ClubBackground.values) {
        final restored = AppearanceSettings.decode(
          settings.copyWith(clubBackground: value).encode(),
        );
        expect(restored.clubBackground, value);
        expect(restored.wallpaper, ChatWallpaper.candlesNight);
        expect(restored.accentIndex, 3);
        expect(restored.messageBlocks, isFalse);
      }
    },
  );

  testWidgets('preview and cancel do not apply or persist a background', (
    tester,
  ) async {
    phone(tester);
    final store = _Store();
    final container = await mountPicker(tester, store);
    await choose(tester, ClubBackground.sky);
    expect(
      container.read(appearanceControllerProvider).clubBackground,
      ClubBackground.current,
    );
    expect(store.saved, isNull);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(find.byType(ClubBackgroundPage), findsNothing);
    expect(
      container.read(appearanceControllerProvider).clubBackground,
      ClubBackground.current,
    );
  });

  testWidgets(
    'apply persists selection, reopening marks it and preserves chat wallpaper',
    (tester) async {
      phone(tester);
      final store = _Store();
      final container = await mountPicker(
        tester,
        store,
        initial: const AppearanceSettings(wallpaper: ChatWallpaper.domesNight),
      );
      await choose(tester, ClubBackground.linen);
      await tester.tap(find.byKey(const ValueKey('apply-club-background')));
      await tester.pumpAndSettle();
      expect(find.byType(ClubBackgroundPage), findsNothing);
      final restored = AppearanceSettings.decode(store.saved);
      expect(restored.clubBackground, ClubBackground.linen);
      expect(restored.wallpaper, ChatWallpaper.domesNight);
      expect(
        container.read(appearanceControllerProvider).clubBackground,
        ClubBackground.linen,
      );
      await tester.tap(find.text('Выбор'));
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey('club-background-linen'));
      await tester.scrollUntilVisible(
        tile,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Сейчас установлен')),
        findsOneWidget,
      );
      await choose(tester, ClubBackground.current);
      await tester.tap(find.byKey(const ValueKey('apply-club-background')));
      await tester.pumpAndSettle();
      expect(
        AppearanceSettings.decode(store.saved).clubBackground,
        ClubBackground.current,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed persistence offers retry and enlarged controls stay usable',
    (tester) async {
      phone(tester);
      final store = _Store()..fail = true;
      await mountPicker(tester, store, scale: 1.8);
      await choose(tester, ClubBackground.olive);
      await tester.tap(find.byKey(const ValueKey('apply-club-background')));
      await tester.pumpAndSettle();
      expect(find.byType(ClubBackgroundPage), findsOneWidget);
      expect(
        find.textContaining('Не удалось запомнить оформление'),
        findsOneWidget,
      );
      expect(store.saved, isNull);
      store.fail = false;
      await tester.tap(find.byKey(const ValueKey('apply-club-background')));
      await tester.pumpAndSettle();
      expect(
        AppearanceSettings.decode(store.saved).clubBackground,
        ClubBackground.olive,
      );
      expect(find.byType(ClubBackgroundPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('changing background preserves the existing scroll position', (
    tester,
  ) async {
    final store = _Store();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appearanceStoreProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: ClubScreenBackground(
              child: ListView.builder(
                controller: scroll,
                itemCount: 100,
                itemBuilder: (_, index) =>
                    SizedBox(height: 70, child: Text('$index')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(700);
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ClubScreenBackground)),
      listen: false,
    );
    await container
        .read(appearanceControllerProvider.notifier)
        .setClubBackground(ClubBackground.lavender);
    await tester.pumpAndSettle();
    expect(scroll.offset, 700);
    expect(tester.takeException(), isNull);
  });

  testWidgets('halo preserves photo edit and stories actions', (tester) async {
    var edited = 0, added = 0, viewed = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 152,
                child: ClubPhoto(
                  halo: true,
                  hasStories: true,
                  onEdit: () => edited++,
                  onAddStory: () => added++,
                  onViewStories: () => viewed++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('club-photo-halo')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('club-photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-club-photo')));
    await tester.tap(find.byKey(const ValueKey('add-club-story')));
    await tester.tap(find.byKey(const ValueKey('club-photo')));
    expect([edited, added, viewed], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'solid navigation covers content and changes destination immediately',
    (tester) async {
      phone(tester);
      var selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            extendBody: true,
            body: const ColoredBox(
              color: Colors.blue,
              child: SizedBox.expand(),
            ),
            bottomNavigationBar: ClubNavigationBar(
              selectedIndex: selected,
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      );
      final surface = find.byKey(const ValueKey('floating-navigation-surface'));
      expect(tester.widget<Material>(surface).color!.a, 1);
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
      expect(selected, 2);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'club redesign uses supplied records and keeps four equal working tabs',
    (tester) async {
      phone(tester);
      final data = dashboardFixture();
      final repo = RecordingClubChats(data);
      await mountDashboard(tester, repo);
      expect(find.text('Болталка'), findsOneWidget);
      expect(find.text('Полезные материалы'), findsOneWidget);
      expect(find.text('Волонтёры'), findsNothing);
      expect(find.byKey(const ValueKey('club-photo-halo')), findsOneWidget);
      final first = tester.getSize(find.byKey(const ValueKey('club-tab-0')));
      for (var index = 1; index < 4; index++) {
        expect(tester.getSize(find.byKey(ValueKey('club-tab-$index'))), first);
        await tapVisible(tester, find.byKey(ValueKey('club-tab-$index')));
      }
      expect(repo.requests, isEmpty);
      expect(find.text('Помощь на занятиях'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
