class PageCursor {
  const PageCursor(this.timestamp, this.id);
  final DateTime timestamp;
  final String id;
  String beforeFilter(String column) {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id))
      throw const FormatException('Invalid cursor');
    return '$column.lt.${timestamp.toUtc().toIso8601String()},and($column.eq.${timestamp.toUtc().toIso8601String()},id.lt.$id)';
  }
}

class CursorPage<T> {
  const CursorPage({required this.items, this.next});
  final List<T> items;
  final PageCursor? next;
}
