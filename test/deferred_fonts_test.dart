import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/design_system/deferred_fonts.dart';

class SlowFontBundle extends CachingAssetBundle {
  final result = Completer<ByteData>();
  bool requested = false;

  @override
  Future<ByteData> load(String key) {
    requested = true;
    return result.future;
  }
}

void main() {
  testWidgets('slow or failed emoji download does not block the first screen', (
    tester,
  ) async {
    final bundle = SlowFontBundle();
    scheduleEmojiFontLoading(bundle: bundle);
    expect(bundle.requested, isFalse);

    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GestureDetector(
          onTap: () => taps++,
          child: const Text('Mellon'),
        ),
      ),
    );
    expect(bundle.requested, isTrue);
    expect(bundle.result.isCompleted, isFalse);
    await tester.tap(find.text('Mellon'));
    expect(taps, 1);

    bundle.result.completeError(StateError('Font network request failed'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Mellon'), findsOneWidget);
  });
}
