import 'dart:js_interop';

import '../lib/features/chats/presentation/browser_chat_gestures_web.dart';

@JS('window.mellonChatGestureTestActive')
external JSBoolean get _active;

@JS('window.mellonChatGestureTestDropBridge')
external void _dropBridge();

void main() {
  final first = protectChatBrowserGestures();
  assert(_active.toDart);
  final second = protectChatBrowserGestures();
  first();
  assert(_active.toDart);
  first(); // Closing the same route twice must not release another route.
  assert(_active.toDart);
  second();
  assert(!_active.toDart);
  final third = protectChatBrowserGestures();
  assert(_active.toDart);
  third();
  assert(!_active.toDart);
  _dropBridge(); // A stale HTML document must not throw or trap the chat.
  protectChatBrowserGestures()();
  // Standalone test runner output, not application logging.
  // ignore: avoid_print
  print('PASS Dart bridge: nested routes, repeat release, reopen, missing JS');
}
