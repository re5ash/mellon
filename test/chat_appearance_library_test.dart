import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/design_system/chat_wallpaper_catalog.dart';
import 'package:moy_prihod/design_system/theme_controller.dart';
import 'package:moy_prihod/features/appearance/presentation/appearance_detail_pages.dart';
import 'package:moy_prihod/features/appearance/presentation/chat_preview.dart';
import 'package:moy_prihod/features/chats/presentation/chat_appearance.dart';
import 'package:moy_prihod/features/chats/presentation/chat_icon_badge.dart';
import 'package:moy_prihod/features/chats/presentation/chat_icon_picker.dart';

class WallpaperStore implements AppearanceStore {
  final saved = <String>[];
  @override
  Future<void> write(String value) async {
    saved.add(value);
  }
}

void main() {
  test(
    '17 topics have at least five distinct colored choices; auto is stable',
    () {
      final catalog = ChatAppearance.library;
      final topics = catalog.map((i) => i.topic).toSet();
      expect(topics.length, 17);
      expect(catalog.length, 85);
      expect(catalog.map((i) => i.key).toSet().length, 85);
      expect(
        catalog.map((i) => i.color).toSet().length,
        greaterThanOrEqualTo(10),
      );
      for (final topic in topics) {
        final group = catalog.where((i) => i.topic == topic).toList();
        expect(group.length, greaterThanOrEqualTo(5));
        expect(
          group.map((i) => i.color).toSet().length,
          greaterThanOrEqualTo(4),
        );
      }
      expect(
        ChatAppearance.resolve(
          'auto',
          title: 'Поездка в монастырь',
          seed: 'r',
        ).key,
        ChatAppearance.resolve(
          'auto',
          title: 'Поездка в монастырь',
          seed: 'r',
        ).key,
      );
      expect(
        ChatAppearance.resolve('auto', title: 'Настольные игры').topic,
        'Настольные игры',
      );
      expect(ChatAppearance.resolve('book').key, 'books_1');
    },
  );
  test(
    '24 local patterned backgrounds cover six topics with light and dark palettes',
    () {
      expect(ChatWallpapers.designs.length, 24);
      for (var family = 0; family < 6; family++) {
        final options = ChatWallpapers.designs.values
            .where((d) => d.family == family)
            .toList();
        expect(options.where((d) => d.dark).length, 2);
        expect(options.where((d) => !d.dark).length, 2);
      }
      for (final background in ChatWallpaper.values) {
        final settings = AppearanceSettings(wallpaper: background);
        expect(
          AppearanceSettings.decode(settings.encode()).wallpaper,
          background,
        );
      }
    },
  );
  testWidgets(
    'icon picker previews actual color and commits only Apply; Cancel has no result',
    (tester) async {
      String? result;
      var completed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showChatIconPicker(
                    context,
                    selected: 'auto',
                    title: 'Болталка',
                  );
                  completed = true;
                },
                child: const Text('Выбрать'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-icon-chat_2')));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(
        tester
            .widgetList<ChatIconBadge>(find.byType(ChatIconBadge))
            .where((w) => w.size == 64)
            .single
            .iconKey,
        'chat_2',
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      completed = false;
      await tester.tap(find.text('Выбрать'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('chat-icon-chat_2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Применить'));
      await tester.pumpAndSettle();
      expect(result, 'chat_2');
    },
  );
  testWidgets(
    'icon animation is idle after one pulse and disabled with reduced motion',
    (tester) async {
      Widget badge(int token, bool reduced) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: ChatIconBadge(iconKey: 'music_3', motionToken: token),
          ),
        ),
      );
      await tester.pumpWidget(badge(0, false));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(badge(1, false));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(badge(2, true));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
    },
  );
  testWidgets(
    'wallpaper selection previews before saving and cancels without changing settings',
    (tester) async {
      final store = WallpaperStore();
      final container = ProviderContainer(
        overrides: [appearanceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChatWallpaperPage(),
                    ),
                  ),
                  child: const Text('Фоны'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Фоны'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('wallpaper-templesDawn')),
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 15,
      );
      await tester.tap(find.byKey(const ValueKey('wallpaper-templesDawn')));
      await tester.pumpAndSettle();
      expect(
        container.read(appearanceControllerProvider).wallpaper,
        ChatWallpaper.automatic,
      );
      expect(store.saved, isEmpty);
      // Preview remains the same shared renderer as the real chat.
      await tester.scrollUntilVisible(
        find.byType(ChatPreview),
        -250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 15,
      );
      expect(
        tester.widget<ChatPreview>(find.byType(ChatPreview)).settings.wallpaper,
        ChatWallpaper.templesDawn,
      );
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(store.saved, isEmpty);
      await tester.tap(find.text('Фоны'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('wallpaper-templesDawn')),
        250,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 15,
      );
      await tester.tap(find.byKey(const ValueKey('wallpaper-templesDawn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('apply-wallpaper')));
      await tester.pumpAndSettle();
      expect(
        AppearanceSettings.decode(store.saved.single).wallpaper,
        ChatWallpaper.templesDawn,
      );
      expect(find.byType(ChatWallpaperPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
