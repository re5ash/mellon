import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/shell/app_shell.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/chats/presentation/chat_route.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';

import 'chat_switch_loading_test.dart' show mountSwitches, room;
import 'design_navigation_test.dart' show mountApp, RecordingFeed;

void main() {
  testWidgets('chat opens across intermediate frames over a stationary club', (tester) async {
    await mountSwitches(tester, second: Future.value(room(1)),
      size: const Size(390, 844), openFirst: false);
    final club = find.byType(ClubIdentity, skipOffstage: false);
    final clubElement = tester.element(club);
    final clubRect = tester.getRect(club);
    await tester.tap(find.byKey(const ValueKey('club-chat-room-0')));
    await tester.pump();
    // Navigator/Hero preparation may keep the incoming route offstage for
    // its first layout. Flush that frame without advancing animation time.
    await tester.pump();
    final chat = find.byType(ChatPage);
    await tester.pump(const Duration(milliseconds: 85));
    expect(find.byKey(const ValueKey('mellon-chat-slide')), findsOneWidget);
    final first = tester.getTopLeft(chat).dx;
    expect(first, inExclusiveRange(0.0, 390.0));
    expect(tester.getSize(chat), const Size(390, 844));
    expect(tester.getRect(club), clubRect);
    await tester.pump(const Duration(milliseconds: 85));
    final next = tester.getTopLeft(chat).dx;
    expect(next, inExclusiveRange(0.0, first));
    expect(tester.getRect(club), clubRect);
    await tester.pumpAndSettle();
    expect(tester.getRect(chat), const Rect.fromLTWH(0, 0, 390, 844));
    expect(find.byType(ClubIdentity), findsNothing);
    await tester.tap(find.byTooltip('К списку чатов'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(chat).dx, inExclusiveRange(0.0, 390.0));
    expect(tester.getRect(club), clubRect);
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    expect(tester.element(club), same(clubElement));
    expect(tester.getRect(club), clubRect);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edge follows the finger, cancels without a jump and keeps the draft', (tester) async {
    var sectionDrags = 0;
    await mountSwitches(tester, second: Future.value(room(1)),
      size: const Size(390, 844), onSectionDrag: (_) => sectionDrags++);
    final chat = find.byType(ChatPage);
    final input = find.byKey(const ValueKey('chat-message-input'));
    final club = find.byType(ClubIdentity, skipOffstage: false);
    final clubRect = tester.getRect(club);
    await tester.enterText(input, 'Черновик после отмены свайпа');
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(chat));
    final gesture = await tester.startGesture(const Offset(2, 220));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    final first = tester.getTopLeft(chat).dx;
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final dragged = tester.getTopLeft(chat).dx;
    expect(dragged - first, closeTo(30, .1));
    expect(tester.getRect(club), clubRect);
    expect(tester.getSize(chat), const Size(390, 844));
    await tester.pump(const Duration(milliseconds: 350));
    await gesture.up();
    await tester.pump();
    // Releasing a short drag must not remap its current offset through a curve.
    expect(tester.getTopLeft(chat).dx, closeTo(dragged, .1));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(chat), Offset.zero);
    expect(find.text('Черновик после отмены свайпа'), findsOneWidget);
    expect(navigator.userGestureInProgress, isFalse);
    await tester.dragFrom(const Offset(150, 220), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(chat, findsOneWidget);
    expect(sectionDrags, 0);
    await tester.dragFrom(const Offset(2, 220), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(chat, findsNothing);
    expect(tester.getRect(club), clubRect);
    expect(navigator.userGestureInProgress, isFalse);
    expect(sectionDrags, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shell leading and navigation remain stationary under a root chat', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = await mountApp(tester, RecordingFeed(),
      signedIn: true, membershipStatus: 'active');
    router.go('/my-youth');
    await tester.pumpAndSettle();
    final shell = find.byType(AppShell, skipOffstage: false);
    final leading = find.descendant(of: shell,
      matching: find.byIcon(Icons.church_outlined, skipOffstage: false));
    final navigation = find.byKey(const ValueKey('floating-navigation-surface'), skipOffstage: false);
    expect(navigation, findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(leading, findsOneWidget);
    final leadingRect = tester.getRect(leading);
    final navigationRect = tester.getRect(navigation);
    final navigator = Navigator.of(tester.element(shell), rootNavigator: true);
    unawaited(navigator.push<void>(MellonChatRoute(
      reducedMotion: false,
      builder: (_) => const Scaffold(body: Center(child: Text('Тестовый чат'))),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(leading, findsOneWidget);
    expect(tester.getRect(leading), leadingRect);
    expect(tester.getRect(navigation), navigationRect);
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(leading, findsOneWidget);
    expect(tester.getRect(leading), leadingRect);
    expect(tester.getRect(navigation), navigationRect);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion opens immediately and system back still closes', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Список чатов'))));
    unawaited(navigatorKey.currentState!.push<void>(MellonChatRoute(
      reducedMotion: true,
      builder: (_) => const Scaffold(key: ValueKey('reduced-chat'), body: Text('Чат')),
    )));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('reduced-chat'))), Offset.zero);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Список чатов'), findsOneWidget);
    expect(find.byKey(const ValueKey('reduced-chat')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
