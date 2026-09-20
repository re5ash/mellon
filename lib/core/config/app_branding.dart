/// Use the current brand while older installations retain the original default.
/// Custom names set by a super administrator continue to take precedence.
String appDisplayName(Object? configuredName) {
  final name = configuredName is String ? configuredName.trim() : '';
  return name.isEmpty || name.toLowerCase() == 'мой приход' ? 'Mellon' : name;
}
