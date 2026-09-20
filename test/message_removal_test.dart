import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/chats/presentation/message_removal.dart';

const slotKey = ValueKey('message-slot');

Widget preview({
  required bool removed,
  required VoidCallback onRemoved,
  bool reduceMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MessageRemoval(
            key: slotKey,
            removed: removed,
            onRemoved: onRemoved,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(removed ? 'Сообщение удалено' : 'Текст сообщения'),
            ),
          ),
          const Text('Следующее сообщение'),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('bubble fades, collapses and leaves no placeholder or gap', (
    tester,
  ) async {
    var completed = 0;
    void onRemoved() => completed++;
    await tester.pumpWidget(preview(removed: false, onRemoved: onRemoved));
    await tester.pumpAndSettle();
    final slot = find.byKey(slotKey);
    final height = tester.getSize(slot).height;
    final followingTop = tester.getTopLeft(find.text('Следующее сообщение')).dy;
    await tester.pumpWidget(preview(removed: true, onRemoved: onRemoved));
    await tester.pump();
    expect(find.text('Текст сообщения'), findsOneWidget);
    expect(find.text('Сообщение удалено'), findsNothing);
    expect(find.text('Текст сообщения').hitTestable(), findsNothing);
    await tester.pump(const Duration(milliseconds: 140));
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: slot, matching: find.byType(FadeTransition)),
    );
    expect(fade.opacity.value, inExclusiveRange(0.0, 1.0));
    expect(tester.getSize(slot).height, inExclusiveRange(0.0, height));
    expect(
      tester.getTopLeft(find.text('Следующее сообщение')).dy,
      lessThan(followingTop),
    );
    expect(completed, 0);
    await tester.pumpAndSettle();
    expect(find.text('Текст сообщения'), findsNothing);
    expect(find.text('Сообщение удалено'), findsNothing);
    expect(tester.getSize(slot).height, 0);
    expect(
      tester.getTopLeft(find.text('Следующее сообщение')).dy,
      closeTo(followingTop - height, .01),
    );
    expect(completed, 1);
  });

  testWidgets('already deleted rows never flash their text', (tester) async {
    var completed = 0;
    await tester.pumpWidget(
      preview(removed: true, onRemoved: () => completed++),
    );
    expect(find.text('Сообщение удалено'), findsNothing);
    expect(tester.getSize(find.byKey(slotKey)).height, 0);
    await tester.pumpAndSettle();
    expect(completed, 1);
  });

  testWidgets(
    'reduced motion removes immediately and disposal cancels animation',
    (tester) async {
      var completed = 0;
      void onRemoved() => completed++;
      await tester.pumpWidget(
        preview(removed: false, reduceMotion: true, onRemoved: onRemoved),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        preview(removed: true, reduceMotion: true, onRemoved: onRemoved),
      );
      await tester.pump();
      expect(tester.getSize(find.byKey(slotKey)).height, 0);
      expect(completed, 1);
      await tester.pumpAndSettle();
      expect(completed, 1);

      // A different screen disposes the state and its ticker while fading.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(preview(removed: false, onRemoved: onRemoved));
      await tester.pumpAndSettle();
      await tester.pumpWidget(preview(removed: true, onRemoved: onRemoved));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('enabling reduced motion during removal completes only once', (
    tester,
  ) async {
    var completed = 0;
    void onRemoved() => completed++;
    await tester.pumpWidget(preview(removed: false, onRemoved: onRemoved));
    await tester.pumpAndSettle();
    await tester.pumpWidget(preview(removed: true, onRemoved: onRemoved));
    await tester.pump(const Duration(milliseconds: 100));
    expect(completed, 0);
    expect(tester.getSize(find.byKey(slotKey)).height, greaterThan(0));

    await tester.pumpWidget(
      preview(removed: true, reduceMotion: true, onRemoved: onRemoved),
    );
    expect(tester.getSize(find.byKey(slotKey)).height, 0);
    expect(completed, 1);
    expect(find.text('Текст сообщения'), findsNothing);
    expect(find.text('Сообщение удалено'), findsNothing);

    // Further rebuilds and the former animation deadline must not remove twice.
    await tester.pumpWidget(
      preview(removed: true, reduceMotion: true, onRemoved: onRemoved),
    );
    await tester.pumpWidget(preview(removed: true, onRemoved: onRemoved));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(completed, 1);
    expect(tester.getSize(find.byKey(slotKey)).height, 0);
    expect(tester.takeException(), isNull);
  });
}
