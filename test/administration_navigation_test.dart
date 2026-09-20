import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moy_prihod/app/router/app_router.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';

void main() {
  const parishPath = '/admin/parishes/20000000-0000-0000-0000-000000000001';
  const routes = <({String label, String suffix})>[
    (label: 'chat administration', suffix: 'chats'),
    (label: 'create chat', suffix: 'chats/new'),
    (label: 'edit chat', suffix: 'chats/30000000-0000-0000-0000-000000000001'),
    (label: 'edit parish', suffix: 'edit'),
    (label: 'membership requests', suffix: 'requests'),
    (label: 'create publication', suffix: 'posts/new'),
    (
      label: 'edit publication',
      suffix: 'posts/30000000-0000-0000-0000-000000000001',
    ),
  ];

  for (final route in routes) {
    testWidgets('${route.label} opens above the parish in the real app router', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          // Route-stack tests isolate authentication/access from live Supabase.
          accountAccessProvider.overrideWith(
            (ref) => Stream.value(
              const AccountAccess(superAdmin: true, canManageRoles: true),
            ),
          ),
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser('navigation-test-user')),
          ),
        ],
      );
      final subscription = container.listen(routerProvider, (_, next) {});
      try {
        final router = subscription.read();
        await tester.pump();

        final location = '$parishPath/${route.suffix}';
        final matches = router.configuration.findMatch(Uri.parse(location));
        // Inspect the actual root stack, not only a matching URL. Without an
        // explicit root navigator, the editor matches inside the covered shell
        // and the parish page remains on top even though the URL changes.
        expect(matches.matches.first, isA<ShellRouteMatch>());
        final rootPages = matches.matches
            .whereType<RouteMatch>()
            .map((match) => match.matchedLocation)
            .toList();
        expect(rootPages, [
          parishPath,
          if (route.suffix.startsWith('chats/')) '$parishPath/chats',
          location,
        ]);
        expect(matches.matches.last.matchedLocation, location);

        final back = router.configuration.findMatch(Uri.parse(parishPath));
        expect(
          back.matches
              .whereType<RouteMatch>()
              .map((match) => match.matchedLocation)
              .toList(),
          [parishPath],
        );
        expect(tester.takeException(), isNull);
      } finally {
        subscription.close();
        container.dispose();
        // Flush work queued by Riverpod before the invariant check runs.
        await tester.pump();
      }
    });
  }
}
