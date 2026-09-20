import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/shell/club_navigation_bar.dart';
import 'package:moy_prihod/design_system/app_theme.dart';

Finder destination(int index) => find.byKey(ValueKey('main-navigation-$index'));
Finder get capsule => find.byKey(const ValueKey('navigation-active-capsule'));
Finder get surface => find.byKey(const ValueKey('floating-navigation-surface'));

// Measure the fixed icon slot, not the repeated film frames or rotating glyph.
Finder iconFrame(int index) => find.ancestor(
  of: find.byKey(
    ValueKey(
      [
        'navigation-film-icon',
        'navigation-club-icon',
        'navigation-map-icon',
      ][index],
    ),
  ),
  matching: find.byWidgetPredicate(
    (widget) => widget is SizedBox && widget.width == 26 && widget.height == 26,
  ),
);

Future<void> mountBar(
  WidgetTester tester,
  ValueNotifier<int> selected,
  List<int> calls, {
  bool commitSelection = true,
  bool reducedMotion = false,
  bool dark = false,
  bool showClubs = true,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  VoidCallback? bodyBuilt,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(bottom: 24),
        ),
        child: Directionality(textDirection: direction, child: child!),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            bodyBuilt?.call();
            return const SizedBox.expand();
          },
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: selected,
          builder: (context, index, child) => ClubNavigationBar(
            selectedIndex: index,
            showClubs: showClubs,
            onSelected: (next) {
              calls.add(next);
              if (commitSelection) selected.value = next;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void phone(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'selector stretches and settles; panel, labels and body stay stable',
    (tester) async {
      phone(tester, const Size(390, 844));
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final calls = <int>[];
      var bodyBuilds = 0;
      await mountBar(tester, selected, calls, bodyBuilt: () => bodyBuilds++);
      final bodyBefore = bodyBuilds;
      final panel = tester.getRect(surface);
      final initial = tester.getRect(capsule);
      final icons = [
        for (
          var index = 0;
          index < ClubNavigationBar.destinations.length;
          index++
        )
          tester.getCenter(iconFrame(index)),
      ];
      final labels = [
        for (final d in ClubNavigationBar.destinations)
          tester.getCenter(find.text(d.label)),
      ];
      expect(panel.left, greaterThanOrEqualTo(12));
      expect(panel.right, lessThanOrEqualTo(378));
      expect(panel.bottom, lessThanOrEqualTo(820));
      await tester.tap(destination(2));
      await tester.pump();
      expect(tester.getRect(capsule), initial);
      await tester.pump(const Duration(milliseconds: 80));
      final moving = tester.getRect(capsule);
      expect(moving.left, greaterThan(initial.left));
      expect(moving.width, greaterThan(initial.width + 2));
      expect(capsule, findsOneWidget);
      expect(tester.getRect(surface), panel);
      await tester.pump(const Duration(milliseconds: 40));
      for (var index = 0; index < 3; index++) {
        expect(iconFrame(index), findsOneWidget);
        expect(tester.getSize(iconFrame(index)), const Size(26, 26));
        expect(tester.getCenter(iconFrame(index)), icons[index]);
        expect(
          tester.getCenter(
            find.text(ClubNavigationBar.destinations[index].label),
          ),
          labels[index],
        );
      }
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getRect(capsule).width, closeTo(initial.width, .01));
      expect(
        tester.getCenter(capsule).dx,
        closeTo(tester.getCenter(destination(2)).dx, .01),
      );
      expect(calls, [2]);
      expect(bodyBuilds, bodyBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid reversal starts from the displayed shape; external selection stays authoritative',
    (tester) async {
      phone(tester, const Size(390, 844));
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final calls = <int>[];
      await mountBar(tester, selected, calls);
      final initial = tester.getRect(capsule);
      await tester.tap(destination(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final inFlight = tester.getRect(capsule);
      selected.value = 0;
      await tester.pump();
      expect(tester.getRect(capsule), inFlight);
      await tester.pump(const Duration(milliseconds: 340));
      expect(tester.getRect(capsule), initial);
      selected.value = 1;
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(capsule).dx,
        closeTo(tester.getCenter(destination(1)).dx, .01),
      );
      expect(tester.getRect(capsule).width, greaterThan(initial.width));
      expect(calls, [2]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a modal-only tap presses gently without moving the active selector; cancel does not navigate',
    (tester) async {
      phone(tester, const Size(390, 844));
      final selected = ValueNotifier(0);
      addTearDown(selected.dispose);
      final calls = <int>[];
      await mountBar(tester, selected, calls, commitSelection: false);
      final initial = tester.getRect(capsule);
      final gesture = await tester.startGesture(
        tester.getCenter(destination(1)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final press = find.descendant(
        of: destination(1),
        matching: find.byType(ScaleTransition),
      );
      expect(
        tester.widget<ScaleTransition>(press).scale.value,
        closeTo(.97, .001),
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<ScaleTransition>(press).scale.value, 1);
      expect(calls, [1]);
      expect(tester.getRect(capsule), initial);
      final cancelled = await tester.startGesture(
        tester.getCenter(destination(2)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(calls, [1]);
      expect(tester.takeException(), isNull);
    },
  );

  for (final direction in TextDirection.values) {
    testWidgets(
      'large text, safe areas, reduced motion and direction: $direction',
      (tester) async {
        phone(tester, const Size(320, 568));
        final selected = ValueNotifier(0);
        addTearDown(selected.dispose);
        final calls = <int>[];
        await mountBar(
          tester,
          selected,
          calls,
          scale: 1.8,
          reducedMotion: true,
          dark: direction == TextDirection.rtl,
          direction: direction,
        );
        final panel = tester.getRect(surface);
        for (final d in ClubNavigationBar.destinations) {
          expect(find.text(d.label), findsOneWidget);
          final text = tester.getRect(find.text(d.label));
          expect(panel.contains(text.topLeft), isTrue);
          expect(panel.contains(text.bottomRight), isTrue);
        }
        await tester.tap(destination(2));
        await tester.pump();
        expect(
          tester.getCenter(capsule).dx,
          closeTo(tester.getCenter(destination(2)).dx, .01),
        );
        expect(tester.getRect(surface), panel);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('optional two-item layout preserves original callback indices', (
    tester,
  ) async {
    phone(tester, const Size(390, 844));
    final selected = ValueNotifier(0);
    addTearDown(selected.dispose);
    final calls = <int>[];
    await mountBar(tester, selected, calls, showClubs: false);
    expect(destination(1), findsNothing);
    await tester.tap(destination(2));
    await tester.pumpAndSettle();
    expect(calls, [2]);
    expect(
      tester.getCenter(capsule).dx,
      closeTo(tester.getCenter(destination(2)).dx, .01),
    );
    expect(tester.takeException(), isNull);
  });
}
