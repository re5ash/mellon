import 'package:flutter/painting.dart';

/// One description flows beside the fixed photograph and then beneath it.
class PublicationTextLayout {
  const PublicationTextLayout({
    required this.preview,
    required this.beside,
    required this.below,
    required this.previewLines,
    required this.slotHeight,
    required this.hasDetails,
  });
  final String preview, beside, below;
  final int previewLines;
  final double slotHeight;
  final bool hasDetails;

  factory PublicationTextLayout.measure({
    required String text,
    required TextStyle style,
    required double width,
    required TextDirection direction,
    required TextScaler scaler,
    required double controlHeight,
    required double bottomPadding,
  }) {
    TextPainter measure(String value) => TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final full = measure(text);
    final lines = full.computeLineMetrics();
    try {
      int endOfLine(int index) {
        final line = lines[index];
        // A point inside the line avoids upstream affinity at a soft wrap.
        final position = full.getPositionForOffset(
          Offset(line.left + line.width / 2, line.baseline - line.ascent / 2),
        );
        return full.getLineBoundary(position).end.clamp(0, text.length).toInt();
      }

      final hasDetails = lines.length > 3;
      final previewEnd = hasDetails
          ? _wholeWordBoundary(text, endOfLine(2))
          : text.length;
      final preview = text.substring(0, previewEnd).trimRight();
      final compact = measure(preview);
      final compactHeight = compact.height;
      final compactLines = compact.computeLineMetrics().length;
      compact.dispose();
      final slot = compactHeight + 10 + controlHeight + bottomPadding;
      if (!hasDetails) {
        return PublicationTextLayout(
          preview: preview,
          beside: preview,
          below: '',
          previewLines: compactLines,
          slotHeight: compactHeight,
          hasDetails: false,
        );
      }
      var count = 0;
      while (count < lines.length &&
          lines[count].baseline + lines[count].descent <= slot + .01) {
        count++;
      }
      var cut = previewEnd;
      for (var i = count - 1; i >= 0; i--) {
        final candidate = i == lines.length - 1
            ? text.length
            : _wholeWordBoundary(text, endOfLine(i));
        if (candidate < previewEnd) break;
        final fitted = measure(text.substring(0, candidate).trimRight());
        final fits = fitted.height <= slot + .01;
        fitted.dispose();
        if (fits) {
          cut = candidate;
          break;
        }
      }
      return PublicationTextLayout(
        preview: preview,
        beside: text.substring(0, cut).trimRight(),
        below: text.substring(cut).trimLeft(),
        previewLines: compactLines,
        slotHeight: slot,
        hasDetails: true,
      );
    } finally {
      full.dispose();
    }
  }
}

final _space = RegExp(r'\s', unicode: true);

int _wholeWordBoundary(String text, int end) {
  if (end <= 0 || end >= text.length) return end;
  if (_space.hasMatch(text[end - 1]) || _space.hasMatch(text[end])) return end;
  var start = end;
  while (start > 0 && !_space.hasMatch(text[start - 1])) {
    start--;
  }
  // A single unbroken URL/word still needs normal line wrapping.
  return start > 0 ? start : end;
}
