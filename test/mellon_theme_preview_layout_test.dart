import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/appearance_settings.dart';
import 'package:moy_prihod/features/appearance/presentation/theme_picker_page.dart';

// Use transformed corners: previews contain scaling, so an untransformed
// RenderBox.size does not describe the on-screen bounds of their text.
Rect screenBounds(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );
}

void main() {
  for (final theme in [
    MellonVisualTheme.cathedral,
    MellonVisualTheme.radiance,
    MellonVisualTheme.azure,
  ]) {
    testWidgets('${theme.name} preview fits every card and navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Cover a selection thumbnail and the larger phone previews. Keep the
      // default test font: its taller metrics exposed the original overflow.
      for (final width in [96.0, 320.0, 393.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(1.8),
                disableAnimations: true,
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: width,
                    child: MellonThemePreview(theme: theme),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final preview = find.byType(MellonThemePreview);
        final bounds = screenBounds(tester, preview).inflate(0.5);
        expect(find.text('Название чата'), findsNWidgets(4));
        expect(find.text('Последнее сообщение'), findsNWidgets(4));
        expect(find.text('Ближайшее событие'), findsOneWidget);
        expect(find.text('Лента'), findsOneWidget);
        expect(find.text('Карта'), findsOneWidget);

        final content = find.descendant(
          of: preview,
          matching: find.byWidgetPredicate(
            (widget) => widget is Text || widget is Image || widget is Icon,
          ),
        );
        for (final item in content.evaluate()) {
          final rect = screenBounds(
            tester,
            find.byElementPredicate((element) => identical(element, item)),
          );
          expect(rect.isEmpty, isFalse);
          expect(bounds.contains(rect.topLeft), isTrue);
          expect(bounds.contains(rect.bottomRight), isTrue);
        }

        final lastChat = screenBounds(
          tester,
          find.text('Последнее сообщение').last,
        );
        final navigation = screenBounds(tester, find.text('Лента'));
        expect(lastChat.bottom, lessThan(navigation.top));
      }
    });
  }
}
