import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The full emoji font is about 10 MB. It must not hold up the first screen.
/// FontLoader notifies Flutter when ready, so existing text is laid out again
/// with the same MellonEmoji family used by messages and the emoji picker.
void scheduleEmojiFontLoading({AssetBundle? bundle}) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final loader = FontLoader('MellonEmoji');
      loader.addFont(
        (bundle ?? rootBundle).load('assets/fonts/NotoColorEmoji.ttf'),
      );
      await loader.load();
    } on Object {
      // Text can still use the platform/engine fallback if the download fails.
      debugPrint('Mellon: optional emoji font could not be loaded.');
    }
  });
}
