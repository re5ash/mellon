import 'package:flutter/material.dart';

/// Replace the selected text using Flutter's UTF-16 selection offsets, while
/// counting the message limit in user-perceived characters (including ZWJ emoji).
TextEditingValue insertChatEmoji(TextEditingValue value, String emoji) {
  final selection = value.selection;
  final valid = selection.isValid && selection.end <= value.text.length;
  final start = valid ? selection.start : value.text.length;
  final end = valid ? selection.end : value.text.length;
  final text = value.text.replaceRange(start, end, emoji);
  if (text.characters.length > 4000) return value;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + emoji.length),
    composing: TextRange.empty,
  );
}
