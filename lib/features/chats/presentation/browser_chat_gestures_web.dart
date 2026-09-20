import 'dart:js_interop';

@JS('window.mellonChatGestures')
external JSFunction? get _browserGuard;

int _openChats = 0;

/// Keep WebKit's history swipe from racing the Flutter edge-back gesture.
/// A missing bridge in an older cached HTML document must not break the chat.
void Function() protectChatBrowserGestures() {
  _openChats++;
  _browserGuard?.callAsFunction(null, true.toJS);
  var released = false;
  return () {
    if (released) return;
    released = true;
    _openChats--;
    if (_openChats == 0) _browserGuard?.callAsFunction(null, false.toJS);
  };
}
