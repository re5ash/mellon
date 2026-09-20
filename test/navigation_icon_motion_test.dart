import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/app/shell/club_navigation_bar.dart';

void main() {
  testWidgets('one capsule travels continuously and navigation does not await icons', (tester) async {
    var selected = 0, taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      bottomNavigationBar: StatefulBuilder(builder: (context, change) => ClubNavigationBar(
        selectedIndex: selected,
        onSelected: (value) { taps++; change(() => selected = value); },
      )),
    )));
    final capsule = find.byKey(const ValueKey('navigation-active-capsule'));
    final element = tester.element(capsule);
    final before = tester.getCenter(capsule).dx;
    await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
    expect(selected, 2);
    expect(taps, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final during = tester.getCenter(capsule).dx;
    expect(during, greaterThan(before));
    expect(identical(tester.element(capsule), element), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    final after = tester.getCenter(capsule).dx;
    expect(after, greaterThan(during));
    final spin = tester.widget<Transform>(find.byKey(const ValueKey('navigation-map-icon')));
    expect(spin.transform.entry(0, 0), lessThan(.5));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
    expect(taps, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<Transform>(find.byKey(const ValueKey('navigation-map-icon'))).transform.entry(0, 0), lessThan(.5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('club lifts to 110 percent and feed rolls within fixed icon bounds', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar:
      ClubNavigationBar(selectedIndex: 0, onSelected: (_) {}),
    )));
    await tester.tap(find.byKey(const ValueKey('main-navigation-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    final lift = tester.widget<Transform>(find.byKey(const ValueKey('navigation-club-icon')));
    expect(lift.transform.entry(1, 3), closeTo(-2.5, .01));
    expect((lift.child! as Transform).transform.entry(0, 0), closeTo(1.1, .001));
    await tester.pumpAndSettle();
    final film = find.byKey(const ValueKey('navigation-film-icon'));
    final bounds = tester.getRect(film);
    await tester.tap(find.byKey(const ValueKey('main-navigation-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getRect(film), bounds);
    List<Positioned> frames() => tester.widgetList<Positioned>(
      find.descendant(of: film, matching: find.byType(Positioned)),
    ).toList();
    // An eased animation need not travel exactly half its distance at half
    // its duration. Verify visible movement, continuity and the final frame.
    final halfway = frames();
    expect(halfway, hasLength(2));
    expect(halfway.first.top!, inExclusiveRange(-26.0, 0.0));
    expect(halfway.last.top! - halfway.first.top!, closeTo(26, .001));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    final later = frames();
    expect(later.first.top!, lessThan(halfway.first.top!));
    expect(later.first.top!, greaterThan(-26));
    expect(later.last.top! - later.first.top!, closeTo(26, .001));
    expect(tester.getRect(film), bounds);
    await tester.pump(const Duration(milliseconds: 350));
    final finished = frames();
    expect(finished.first.top, closeTo(-26, .001));
    expect(finished.last.top, closeTo(0, .001));
    expect(tester.getRect(film), bounds);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps icons still and changes selection immediately', (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!,
    ), home: Scaffold(bottomNavigationBar: StatefulBuilder(builder: (context, change) =>
      ClubNavigationBar(selectedIndex: selected, onSelected: (value) => change(() => selected = value)),
    ))));
    await tester.tap(find.byKey(const ValueKey('main-navigation-2')));
    expect(selected, 2);
    await tester.pump();
    final spin = tester.widget<Transform>(find.byKey(const ValueKey('navigation-map-icon')));
    expect(spin.transform.entry(0, 0), closeTo(1, .000001));
    final capsule = tester.getCenter(find.byKey(const ValueKey('navigation-active-capsule')));
    final button = tester.getCenter(find.byKey(const ValueKey('main-navigation-2')));
    expect(capsule.dx, closeTo(button.dx, .1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
