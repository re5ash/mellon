const publicRoots = {
  'feed',
  'parishes',
  'events',
  'help',
  'map',
  'more',
  'profile',
  'my-youth',
  'auth',
};
bool requiresSignIn(String path) {
  final root = Uri.parse(path).pathSegments.firstOrNull ?? 'feed';
  return !publicRoots.contains(root);
}

String safeDestination(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.contains('\\'))
    return '/feed';
  if (uri.path == '/feed' &&
      const {
        'general',
        'parish',
        'events',
        'help',
      }.contains(uri.queryParameters['tab'])) {
    return Uri(
      path: '/feed',
      queryParameters: {'tab': uri.queryParameters['tab']!},
    ).toString();
  }
  if (RegExp(r'^/youth-requests/[0-9a-fA-F-]{36}$').hasMatch(uri.path)) {
    final request = uri.queryParameters['request'];
    return Uri(
      path: uri.path,
      queryParameters:
          request != null && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(request)
          ? {'request': request}
          : null,
    ).toString();
  }
  if (const {
    '/profile/details',
    '/my-youth',
    '/manage',
    '/admin/youth-clubs',
    '/my-parish/news',
    '/my-parish/events',
    '/my-parish/schedule',
  }.contains(uri.path))
    return uri.path;
  if (RegExp(
        r'^/(feed|my-parish|map|chats|more|parishes|events|help|notifications|profile|admin)$',
      ).hasMatch(uri.path) ||
      RegExp(
        r'^/(parishes|chats|join|youth-requests)/[0-9a-fA-F-]{36}$',
      ).hasMatch(uri.path) ||
      uri.path == '/admin/parishes/new' ||
      RegExp(
        r'^/admin/parishes/[0-9a-fA-F-]{36}(/(edit|requests|posts/(new|[0-9a-fA-F-]{36})|chats(/(new|[0-9a-fA-F-]{36}))?))?$',
      ).hasMatch(uri.path))
    return uri.path;
  return '/feed';
}

// Public details reached from the feed and map remain readable.
bool allowedForRestrictedGuest(String path) {
  final uri = Uri.parse(path);
  // This entry page renders only the review card for restricted guests.
  // Do not allow internal club routes through the same prefix.
  if (uri.path == '/my-youth') return true;
  final root = uri.pathSegments.firstOrNull ?? 'feed';
  return const {
    'feed',
    'map',
    'parishes',
    'events',
    'help',
    'notifications',
    'profile',
    'more',
    'auth',
  }.contains(root);
}

// Keep old bookmarks useful while retiring the parish screens from the product.
String? retiredParishDestination(String path) {
  if (path == '/parishes' ||
      path.startsWith('/parishes/') ||
      path == '/my-parish' ||
      path.startsWith('/my-parish/') ||
      path.startsWith('/join/'))
    return '/my-youth';
  if (path.startsWith('/admin/parishes/')) return '/admin';
  return null;
}
