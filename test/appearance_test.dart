import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/app.dart';
import 'package:moy_prihod/app/router/app_router.dart';
import 'package:moy_prihod/core/access/permission_providers.dart';
import 'package:moy_prihod/design_system/appearance_palette.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/design_system/components/chat_surface.dart';
import 'package:moy_prihod/design_system/parish_menu_theme.dart';
import 'package:moy_prihod/design_system/theme_controller.dart';
import 'package:moy_prihod/features/appearance/presentation/appearance_detail_pages.dart';
import 'package:moy_prihod/features/appearance/presentation/appearance_page.dart';
import 'package:moy_prihod/features/appearance/presentation/chat_preview.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/chats/application/chat_moderation.dart';
import 'package:moy_prihod/features/chats/application/chat_providers.dart';
import 'package:moy_prihod/features/chats/application/chat_read_store.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/community_repository.dart';

import 'support/fake_chat_moderation.dart';
import 'support/fake_chat_reads.dart';

class MemoryAppearanceStore implements AppearanceStore {
  String? saved;
  Completer<void>? pending;
  bool fail = false;
  final writes = <String>[];
  @override
  Future<void> write(String value) async {
    writes.add(value);
    if (pending != null) await pending!.future;
    if (fail) throw StateError('storage unavailable');
    saved = value;
  }
}

ProviderContainer appearanceContainer(
  MemoryAppearanceStore store, [
  AppearanceSettings settings = const AppearanceSettings(),
]) => ProviderContainer(
  overrides: [
    chatReadStoreProvider.overrideWithValue(FakeChatReads()),
    appearanceStoreProvider.overrideWithValue(store),
    initialAppearanceProvider.overrideWithValue(settings),
  ],
);

Future<void> showControl(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 35,
    );
  }
  await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
  await tester.pumpAndSettle();
}

Future<void> tapControl(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await showControl(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<
  ({ProviderContainer container, GoRouter router, MemoryAppearanceStore store})
>
mountAppearance(
  WidgetTester tester, {
  AppearanceSettings settings = const AppearanceSettings(),
  String location = '/profile/appearance',
  DateTime Function()? now,
}) async {
  final store = MemoryAppearanceStore();
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/profile/appearance',
        builder: (_, _) => const AppearancePage(),
        routes: [
          GoRoute(
            path: 'wallpaper',
            builder: (_, _) => const ChatWallpaperPage(),
          ),
          GoRoute(path: 'name-color', builder: (_, _) => const NameColorPage()),
          GoRoute(
            path: 'night',
            builder: (_, _) => const NightAppearancePage(),
          ),
        ],
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('Профиль')),
      ),
      GoRoute(
        path: '/chat',
        builder: (_, _) => const ChatPage(roomId: 'room'),
      ),
      GoRoute(
        path: '/feed',
        builder: (context, _) => Theme(
          data: ParishMenuTheme.from(Theme.of(context)),
          child: const Scaffold(
            body: Text('Другая страница', key: ValueKey('other-page')),
          ),
        ),
      ),
    ],
  );
  final scope = ProviderScope(
    overrides: [
      chatReadStoreProvider.overrideWithValue(FakeChatReads()),
      appConfigurationProvider.overrideWith(
        (ref) async => {'app_name': 'Мой приход'},
      ),
      appearanceStoreProvider.overrideWithValue(store),
      initialAppearanceProvider.overrideWithValue(settings),
      routerProvider.overrideWithValue(router),
      if (now != null) appearanceNowProvider.overrideWithValue(now),
      authUserProvider.overrideWith((ref) => Stream.value(const AppUser('me'))),
      chatRoomProvider('room').overrideWith(
        (ref) async => const ChatRoom(
          id: 'room',
          title: 'Тестовый чат',
          kind: 'chat',
          parishId: 'parish',
        ),
      ),
      chatMessagesProvider('room').overrideWith(
        (ref) => Stream.value([
          ChatMessage(
            id: 'out',
            authorId: 'me',
            body: 'Моё сообщение',
            createdAt: DateTime(2026, 9, 12, 12, 2),
          ),
          ChatMessage(
            id: 'in',
            authorId: 'other',
            body: 'Ответ прихода',
            createdAt: DateTime(2026, 9, 12, 12),
          ),
        ]),
      ),
      chatAccessProvider(
        'room',
      ).overrideWith((ref) => Stream.value({'send': true})),
      chatModerationProvider.overrideWithValue(FakeChatModeration()),
      permissionsProvider('parish').overrideWith((ref) async => {'chat.send'}),
    ],
    child: const MoyPrihodApp(),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(scope);
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MoyPrihodApp)),
  );
  return (container: container, router: router, store: store);
}

void main() {
  test(
    'appearance survives restart, migrates old theme and rejects malformed settings',
    () {
      const original = AppearanceSettings(
        preset: AppearancePreset.day,
        lightPreset: AppearancePreset.day,
        accentIndex: 3,
        nameColorIndex: 6,
        messageBlocks: false,
        wallpaper: ChatWallpaper.olive,
        textStep: 5,
        nightEnabled: true,
        nightStart: 1290,
        nightEnd: 390,
        nightPalette: NightPalette.graphite,
      );
      expect(
        AppearanceSettings.decode(original.encode()).encode(),
        original.encode(),
      );
      expect(
        AppearanceSettings.decode(null, legacyTheme: 'dark').preset,
        AppearancePreset.night,
      );
      expect(
        AppearanceSettings.decode(null, legacyTheme: 'light').preset,
        AppearancePreset.day,
      );
      expect(
        AppearanceSettings.decode('broken').preset,
        AppearancePreset.system,
      );
      final invalid = AppearanceSettings.decode(
        '{"version":1,"accent":-1,"textStep":999,"nameColor":"red","nightStart":2000,"nightEnd":1320,"nightEnabled":true}',
      );
      expect(invalid.accentIndex, 0);
      expect(invalid.nameColorIndex, 4);
      expect(invalid.textScale, 1);
      expect(invalid.nightEnabled, isFalse);
    },
  );

  test('night schedule handles midnight and exact boundaries', () {
    const settings = AppearanceSettings(
      preset: AppearancePreset.day,
      nightEnabled: true,
    );
    expect(settings.isNightAt(DateTime(2026, 9, 12, 21, 59)), isFalse);
    expect(settings.isNightAt(DateTime(2026, 9, 12, 22)), isTrue);
    expect(settings.isNightAt(DateTime(2026, 9, 13, 0)), isTrue);
    expect(settings.isNightAt(DateTime(2026, 9, 13, 6, 59)), isTrue);
    expect(
      settings.effectivePreset(DateTime(2026, 9, 13, 7)),
      AppearancePreset.day,
    );
    final daytime = settings.copyWith(nightStart: 60, nightEnd: 180);
    expect(daytime.isNightAt(DateTime(2026, 9, 12, 2)), isTrue);
    expect(daytime.isNightAt(DateTime(2026, 9, 12, 23)), isFalse);
    expect(
      settings.copyWith(nightEnd: 1320).isNightAt(DateTime(2026, 9, 12, 23)),
      isFalse,
    );
  });

  test(
    'rapid edits apply before disk completes and the latest complete snapshot survives restart',
    () async {
      final store = MemoryAppearanceStore()..pending = Completer<void>();
      final container = appearanceContainer(store);
      addTearDown(container.dispose);
      final controller = container.read(appearanceControllerProvider.notifier);
      final first = controller.setAccent(5);
      await Future<void>.delayed(Duration.zero);
      final second = controller.setTextStep(6);
      final third = controller.setWallpaper(ChatWallpaper.sand);
      expect(container.read(appearanceControllerProvider).textStep, 6);
      expect(container.read(appearanceControllerProvider).accentIndex, 5);
      expect(store.saved, isNull);
      expect(store.writes.length, 1);
      store.pending!.complete();
      await Future.wait([first, second, third]);
      final restarted = appearanceContainer(
        store,
        AppearanceSettings.decode(store.saved),
      );
      addTearDown(restarted.dispose);
      final restored = restarted.read(appearanceControllerProvider);
      expect(restored.accentIndex, 5);
      expect(restored.textStep, 6);
      expect(restored.wallpaper, ChatWallpaper.sand);
    },
  );

  test(
    'storage failures stay visible until retry succeeds without reverting the live settings',
    () async {
      final store = MemoryAppearanceStore()..fail = true;
      final container = appearanceContainer(store);
      addTearDown(container.dispose);
      final controller = container.read(appearanceControllerProvider.notifier);
      await controller.setBlocks(false);
      expect(
        container.read(appearanceControllerProvider).messageBlocks,
        isFalse,
      );
      expect(container.read(appearanceSaveErrorProvider), isNotNull);
      store.fail = false;
      await controller.retrySave();
      expect(container.read(appearanceSaveErrorProvider), isNull);
      expect(AppearanceSettings.decode(store.saved).messageBlocks, isFalse);
    },
  );

  test(
    'manual theme cancels the schedule and dark toggle remembers the daytime choice',
    () async {
      final container = appearanceContainer(
        MemoryAppearanceStore(),
        const AppearanceSettings(nightEnabled: true),
      );
      addTearDown(container.dispose);
      final controller = container.read(appearanceControllerProvider.notifier);
      await controller.setPreset(AppearancePreset.day);
      expect(
        container.read(appearanceControllerProvider).nightEnabled,
        isFalse,
      );
      await controller.setDark(true);
      await controller.setDark(false);
      expect(
        container.read(appearanceControllerProvider).preset,
        AppearancePreset.day,
      );
      await controller.setDark(true);
      await controller.setNightEnabled(true);
      expect(
        container.read(appearanceControllerProvider).preset,
        AppearancePreset.day,
      );
      final start = container.read(appearanceControllerProvider).nightStart;
      await controller.setNightTime(end: start);
      expect(container.read(appearanceControllerProvider).nightEnd, 420);
    },
  );

  testWidgets(
    'theme, accent and text size update preview and another app route immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = await mountAppearance(tester);
      await tapControl(tester, 'appearance-theme-night');
      final preview = find.byType(ChatPreview);
      expect(Theme.of(tester.element(preview)).brightness, Brightness.dark);
      await tapControl(tester, 'appearance-accent-4');
      expect(
        Theme.of(tester.element(preview)).colorScheme.primary,
        AppearancePalette.color(4, dark: true),
      );
      final slider = find.byKey(const ValueKey('appearance-text-size'));
      await showControl(tester, slider);
      tester.widget<Slider>(slider).onChanged!(6);
      await tester.pumpAndSettle();
      expect(app.container.read(appearanceControllerProvider).textScale, 1.3);
      app.router.go('/feed');
      await tester.pumpAndSettle();
      final elsewhere = tester.element(
        find.byKey(const ValueKey('other-page')),
      );
      expect(Theme.of(elsewhere).brightness, Brightness.dark);
      expect(
        Theme.of(elsewhere).colorScheme.primary,
        AppearancePalette.color(4, dark: true),
      );
      expect(MediaQuery.textScalerOf(elsewhere).scale(20), closeTo(26, .01));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system theme reacts to device brightness changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await mountAppearance(tester);
    expect(
      Theme.of(tester.element(find.byType(ChatPreview))).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(ChatPreview))).brightness,
      Brightness.dark,
    );
  });

  testWidgets(
    'wallpaper, name and block settings are used by real incoming and outgoing chat messages',
    (tester) async {
      final app = await mountAppearance(tester);
      await tapControl(tester, 'appearance-wallpaper');
      await tapControl(tester, 'wallpaper-olive');
      expect(app.store.writes, isEmpty);
      await tapControl(tester, 'apply-wallpaper');
      expect(
        app.container.read(appearanceControllerProvider).wallpaper,
        ChatWallpaper.olive,
      );
      await tester.pumpAndSettle();
      await tapControl(tester, 'appearance-name-color');
      await tapControl(tester, 'name-color-6');
      app.router.go('/chat');
      await tester.pumpAndSettle();
      final cards = tester
          .widgetList<ChatMessageCard>(find.byType(ChatMessageCard))
          .toList();
      expect(cards.length, 2);
      expect(cards.where((card) => card.outgoing).single.body, 'Моё сообщение');
      expect(
        cards.where((card) => !card.outgoing).single.body,
        'Ответ прихода',
      );
      expect(cards.every((card) => card.settings.nameColorIndex == 6), isTrue);
      expect(
        tester
            .widget<ChatBackdrop>(find.byType(ChatBackdrop))
            .settings
            .wallpaper,
        ChatWallpaper.olive,
      );
      unawaited(
        app.container
            .read(appearanceControllerProvider.notifier)
            .setBlocks(false),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<ChatMessageCard>(find.byType(ChatMessageCard))
            .every((card) => !card.settings.messageBlocks),
        isTrue,
      );
      expect(find.text('Моё сообщение'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'night schedule switches while the app remains open and restores day after resume',
    (tester) async {
      var now = DateTime(2026, 9, 12, 21, 59, 59);
      final app = await mountAppearance(
        tester,
        settings: const AppearanceSettings(
          preset: AppearancePreset.day,
          nightEnabled: true,
        ),
        now: () => now,
      );
      expect(app.container.read(effectiveThemeModeProvider), ThemeMode.light);
      now = DateTime(2026, 9, 12, 22);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(app.container.read(effectiveThemeModeProvider), ThemeMode.dark);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = DateTime(2026, 9, 13, 7);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(app.container.read(effectiveThemeModeProvider), ThemeMode.light);
      // Stop the clock before widget-test invariant checks run.
      await app.container
          .read(appearanceControllerProvider.notifier)
          .setNightEnabled(false);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(320, 640), const Size(1280, 800)]) {
    testWidgets(
      'appearance pages remain scrollable with maximum app size and accessible text at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = await mountAppearance(
          tester,
          settings: const AppearanceSettings(
            textStep: 6,
            preset: AppearancePreset.night,
          ),
        );
        expect(tester.takeException(), isNull);
        await tapControl(tester, 'appearance-night-settings');
        await showControl(
          tester,
          find.byKey(const ValueKey('night-palette-graphite')),
        );
        expect(tester.takeException(), isNull);
        app.router.go('/profile/appearance/wallpaper');
        await tester.pumpAndSettle();
        await showControl(
          tester,
          find.byKey(const ValueKey('wallpaper-lavender')),
        );
        expect(tester.takeException(), isNull);
        app.router.go('/profile/appearance/name-color');
        await tester.pumpAndSettle();
        await showControl(tester, find.byKey(const ValueKey('name-color-7')));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
