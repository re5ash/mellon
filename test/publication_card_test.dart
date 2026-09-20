import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/components/record_card.dart';
import 'package:moy_prihod/features/feed/domain/publication_icon.dart';

void main() {
  test(
    'icon selection recognizes themes and remains stable across reloads',
    () {
      const cases = {
        'Сбор вещей для семьи': 'Помощь',
        'Праздник Рождества Богородицы': 'Праздник',
        'Футбольная встреча': 'Спорт',
        'Паломническая поездка': 'Поездка',
        'Лекция со священником': 'Обучение',
        'Встреча молодёжки': 'Встреча',
        'Объявление': 'Событие',
      };
      for (final entry in cases.entries) {
        final icon = suggestPublicationIcon(entry.key, '', seed: 'event-id');
        expect(icon.group, entry.value);
        expect(
          suggestPublicationIcon(entry.key, '', seed: 'event-id').id,
          icon.id,
        );
      }
      expect(
        {
          for (var i = 0; i < 10; i++)
            suggestPublicationIcon('Помощь семье', '', seed: '$i').id,
        }.length,
        greaterThan(1),
      );
      expect(publicationIconById('unknown'), isNull);
    },
  );

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('photo and header stay fixed while details expand at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final body = List.filled(
        24,
        'Приглашаем на встречу. Подробное описание события и место проведения.',
      ).join(' ');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  RecordCard(
                    title: 'Встреча молодёжного клуба',
                    body: body,
                    category: 'Встреча',
                    icon: Icons.groups_outlined,
                    photo: const ColoredBox(
                      key: ValueKey('test-photo'),
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 1000),
                ],
              ),
            ),
          ),
        ),
      );
      final card = find.byType(RecordCard);
      final compact = tester.getSize(card).height;
      final photoRect = tester.getRect(
        find.byKey(const ValueKey('test-photo')),
      );
      final titleRect = tester.getRect(find.text('Встреча молодёжного клуба'));
      await tester.tap(find.text('Подробнее'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getSize(card).height, greaterThan(compact));
      expect(
        tester.getRect(find.byKey(const ValueKey('test-photo'))),
        photoRect,
      );
      expect(tester.getRect(find.text('Встреча молодёжного клуба')), titleRect);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('publication-continuation')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('publication-continuation')))
            .width,
        greaterThan(photoRect.width),
      );
      expect(find.text('Свернуть'), findsOneWidget);
      expect(find.text('Подробнее'), findsNothing);
      final collapse = find.byKey(const ValueKey('publication-collapse'));
      await tester.ensureVisible(collapse);
      await tester.pumpAndSettle();
      await tester.tap(collapse);
      await tester.pumpAndSettle();
      expect(tester.getSize(card).height, closeTo(compact, .5));
      expect(
        tester.getRect(find.byKey(const ValueKey('test-photo'))),
        photoRect,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('reduced motion and enlarged text remain readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            textScaler: TextScaler.linear(1.7),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: RecordCard(
                  title: 'Очень длинное название праздника',
                  body: List.filled(20, 'Полный текст события.').join(' '),
                  category: 'Праздник',
                  icon: Icons.church_outlined,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final card = find.byType(RecordCard);
    final compactHeight = tester.getSize(card).height;
    final reveal = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Align &&
            widget.alignment == Alignment.topCenter &&
            widget.heightFactor != null,
      ),
    );
    expect(reveal, findsOneWidget);
    await tester.tap(find.text('Подробнее'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('publication-continuation')),
      findsOneWidget,
    );
    // Check the card itself: Material button feedback can still own a ticker.
    // Reduced motion must reveal all details in the very first frame.
    expect(tester.widget<Align>(reveal).heightFactor, 1);
    expect(
      find.descendant(of: card, matching: find.byType(ShaderMask)),
      findsNothing,
    );
    final expandedHeight = tester.getSize(card).height;
    expect(expandedHeight, greaterThan(compactHeight));
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<Align>(reveal).heightFactor, 1);
    expect(tester.getSize(card).height, expandedHeight);
    final collapse = find.byKey(const ValueKey('publication-collapse'));
    expect(find.text('Свернуть'), findsOneWidget);
    await tester.ensureVisible(collapse);
    await tester.pump();
    await tester.tap(collapse);
    await tester.pump();
    expect(tester.widget<Align>(reveal).heightFactor, 0);
    expect(
      find.byKey(const ValueKey('publication-continuation')),
      findsNothing,
    );
    expect(tester.getSize(card).height, compactHeight);
    expect(tester.takeException(), isNull);
  });
}
