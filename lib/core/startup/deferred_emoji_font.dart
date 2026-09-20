import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The web packaging step removes ONLY MellonEmoji from FontManifest.json.
/// Keep native builds and ordinary `flutter run` on their normal font path.
void scheduleMellonEmojiFont() {
  if (!kIsWeb ||
      !const bool.fromEnvironment('MELLON_DEFER_EMOJI', defaultValue: false)) {
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_loadEmojiFont());
  });
}

Future<void> _loadEmojiFont() async {
  // Network failures must never replace or delay the application screen.
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final loader = FontLoader('MellonEmoji')
        ..addFont(rootBundle.load('assets/fonts/NotoColorEmoji.ttf'));
      await loader.load();
      return;
    } on Object {
      if (attempt < 2) {
        await Future<void>.delayed(Duration(seconds: 3 * (attempt + 1)));
      }
    }
  }
}
