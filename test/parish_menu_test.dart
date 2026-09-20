import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/design_system/app_theme.dart';
import 'package:moy_prihod/design_system/parish_menu_theme.dart';
import 'package:moy_prihod/features/chats/domain/chat.dart';
import 'package:moy_prihod/features/membership/presentation/components/parish_chat_directory.dart';

import 'design_navigation_test.dart' as fixture;

void main() {
  testWidgets('retired parish tab deep links open the selected club', (
    tester,
  ) async {
    final router = await fixture.mountApp(
      tester,
      fixture.RecordingFeed(),
      signedIn: true,
      membershipStatus: 'active',
    );
    for (final route in [
      '/my-parish',
      '/my-parish/events',
      '/my-parish/help',
      '/my-parish/schedule',
    ]) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/my-youth');
      expect(find.text('Молодёжный клуб для проверки'), findsOneWidget);
      expect(find.text('Чаты клуба'), findsOneWidget);
      expect(find.text('Чаты прихода'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets('chat list searches actual rooms and opens one at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, state) => const Scaffold(
              body: SingleChildScrollView(
                child: ParishChatDirectory(
                  rooms: [
                    ChatRoom(id: 'a', title: 'Болталка', kind: 'group'),
                    ChatRoom(id: 'b', title: 'Объявления', kind: 'channel'),
                    ChatRoom(id: 'c', title: 'Рукоделие', kind: 'group'),
                  ],
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/chats/:id',
            builder: (_, state) => Scaffold(
              appBar: AppBar(),
              body: Text('Открыт ${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: ParishMenuTheme.from(AppTheme.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Поиск чатов'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'РУКО');
      await tester.pumpAndSettle();
      expect(find.text('Болталка'), findsNothing);
      expect(find.text('Рукоделие'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'нет такого чата');
      await tester.pumpAndSettle();
      expect(find.text('Чаты с таким названием не найдены.'), findsOneWidget);
      await tester.tap(find.byTooltip('Закрыть поиск чатов'));
      await tester.pumpAndSettle();
      expect(find.text('Болталка'), findsOneWidget);
      await tester.tap(find.text('Болталка'));
      await tester.pumpAndSettle();
      expect(find.text('Открыт a'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Рукоделие'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
