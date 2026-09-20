import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/chats/presentation/chat_page.dart';
import 'package:moy_prihod/features/community/club_dashboard.dart';
import 'chat_switch_loading_test.dart' show mountSwitches, room;

Future<void> capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['MELLON_CAPTURE_DIR'];
  if (folder == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('chat-test-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final sdk = Platform.environment['MELLON_FLUTTER_SDK'];
    if (sdk == null) return;
    for (final entry in {
      'Roboto': '$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
      'MaterialIcons':
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'PTSerif': 'assets/fonts/PTSerif-Regular.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });

  for (final size in [const Size(390, 844), const Size(1280, 1000)]) {
    testWidgets(
      'opaque fullscreen chat isolates section drags and only left edge goes back: $size',
      (tester) async {
        var sectionDrags = 0;
        await mountSwitches(
          tester,
          second: Future.value(room(1)),
          size: size,
          editablePhoto: true,
          onSectionDrag: (_) => sectionDrags++,
        );
        final chat = find.byType(ChatPage);
        expect(tester.getRect(chat), Offset.zero & size);
        expect(
          find.ancestor(of: chat, matching: find.byType(ClipRRect)),
          findsNothing,
        );
        expect(find.byType(ClubIdentity), findsNothing);
        expect(find.text('Расписание'), findsNothing);
        final input = find.byKey(const ValueKey('chat-message-input'));
        await tester.enterText(input, 'Сохранённый черновик');
        await tester.pumpAndSettle();
        if (size.width == 390) {
          await tester.runAsync(() => capture(tester, 'chat_fullscreen'));
        }
        await tester.dragFrom(
          Offset(size.width * .4, 220),
          Offset(size.width * .4, 0),
        );
        await tester.pumpAndSettle();
        expect(chat, findsOneWidget);
        expect(sectionDrags, 0);
        final gesture = await tester.startGesture(const Offset(2, 220));
        await gesture.moveBy(Offset(size.width * .18, 0));
        await tester.pump();
        expect(tester.getTopLeft(chat).dx, greaterThan(0));
        expect(tester.getSize(chat), size);
        await tester.pump(const Duration(milliseconds: 350));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.getRect(chat), Offset.zero & size);
        expect(find.text('Сохранённый черновик'), findsOneWidget);
        await tester.dragFrom(const Offset(2, 220), Offset(size.width * .8, 0));
        await tester.pumpAndSettle();
        expect(chat, findsNothing);
        expect(find.byType(ClubIdentity), findsOneWidget);
        expect(sectionDrags, 0);
        if (size.width == 390) {
          await tester.tap(find.byKey(const ValueKey('club-photo')));
          await tester.pumpAndSettle();
          await tester.runAsync(() => capture(tester, 'club_avatar'));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
