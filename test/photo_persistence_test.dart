import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/images/photo_store.dart';

void main() {
  testWidgets(
    'browser photo storage survives a new store instance and isolates accounts',
    (tester) async {
      await tester.runAsync(() async {
        final scope = 'block8-test-${DateTime.now().microsecondsSinceEpoch}';
        final first = createPhotoStore('$scope-a');
        final second = createPhotoStore('$scope-b');
        try {
          await first.write('same-path', Uint8List.fromList([1, 2, 3]));
          final reopened = createPhotoStore('$scope-a');
          expect(await reopened.read('same-path'), [1, 2, 3]);
          expect(await second.read('same-path'), isNull);
          await reopened.remove('same-path');
          expect(await first.read('same-path'), isNull);
        } finally {
          await first.clear();
          await second.clear();
        }
      });
    },
    skip: !kIsWeb,
  );
}
