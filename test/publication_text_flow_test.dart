import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/components/publication_text_layout.dart';
import 'package:moy_prihod/design_system/components/record_card.dart';

String words(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const description =
      'Храм святого благоверного великого князя Александра '
      'Невского в Калининграде — это современный пятиглавый православный храм '
      'в шатрово-купольном стиле. История храма и молодёжного клуба. '
      'Приглашаем всех на встречу, совместную молитву и беседу. ';

  for (final width in [150.0, 210.0, 500.0]) {
    test(
      'text fills the former button space and preserves words at $width',
      () {
        final text = List.filled(8, description).join();
        const style = TextStyle(fontSize: 14, height: 1.4);
        final flow = PublicationTextLayout.measure(
          text: text,
          style: style,
          width: width,
          direction: TextDirection.ltr,
          scaler: TextScaler.noScaling,
          controlHeight: 48,
          bottomPadding: 16,
        );
        expect(flow.hasDetails, isTrue);
        expect(flow.beside.length, greaterThan(flow.preview.length));
        expect(words('${flow.beside} ${flow.below}'), words(text));
        expect(flow.beside.endsWith('шатрово-'), isFalse);
        expect(flow.below.startsWith('купольном'), isFalse);
        final painter = TextPainter(
          text: TextSpan(text: flow.beside, style: style),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: width);
        expect(painter.height, lessThanOrEqualTo(flow.slotHeight + .01));
        // Whole-word wrapping may leave a line; no reserved button-sized strip.
        expect(
          flow.slotHeight - painter.height,
          lessThanOrEqualTo(painter.preferredLineHeight * 2 + .1),
        );
        painter.dispose();
      },
    );
  }

  for (final width in [320.0, 390.0, 1000.0]) {
    testWidgets('expanded description joins under the fixed photo at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final text = List.filled(8, description).join();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordCard(
                title: 'Храм',
                body: text,
                category: 'Событие',
                icon: Icons.church_outlined,
                photo: const ColoredBox(
                  key: ValueKey('flow-photo'),
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );
      final photo = find.byKey(const ValueKey('flow-photo'));
      final photoBefore = tester.getRect(photo);
      final preview = find.byKey(const ValueKey('publication-preview'));
      final previewBefore = tester.widget<Text>(preview).data!;
      await tester.tap(find.text('Подробнее'));
      await tester.pumpAndSettle();
      final continuation = find.byKey(
        const ValueKey('publication-continuation'),
      );
      final topText = tester.widget<Text>(preview);
      final belowText = tester.widget<Text>(continuation);
      expect(topText.data!.length, greaterThan(previewBefore.length));
      expect(words('${topText.data} ${belowText.data}'), words(text));
      expect(tester.getRect(photo), photoBefore);
      final gap =
          tester.getRect(continuation).top - tester.getRect(preview).bottom;
      final painter = TextPainter(
        text: TextSpan(text: 'Текст', style: topText.style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(gap, greaterThanOrEqualTo(-.1));
      expect(gap, lessThanOrEqualTo(painter.preferredLineHeight * 2 + .1));
      painter.dispose();
      expect(find.text('Подробнее'), findsNothing);
      expect(find.text('Свернуть'), findsOneWidget);
      final collapse = find.byKey(const ValueKey('publication-collapse'));
      await tester.ensureVisible(collapse);
      await tester.pumpAndSettle();
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(preview).data, previewBefore);
      expect(tester.getRect(photo), photoBefore);
      expect(find.text('Свернуть'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
