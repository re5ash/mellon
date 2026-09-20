import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/access/account_access_provider.dart';
import 'package:moy_prihod/features/administration/presentation/admin_page.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_directory_repository.dart';
import 'package:moy_prihod/features/community/managed_clubs_page.dart';
import 'package:moy_prihod/features/community/registration_intake_card.dart';

import 'club_registration_test.dart' as registration;

void main() {
  testWidgets(
    'registration from general entry never loads clubs or silently sends an application',
    (tester) async {
      final repo = registration.RecordingRegistration();
      var loads = 0;
      await registration.mountRegistration(
        tester,
        repo,
        accountOnly: true,
        loadClubs: () async {
          loads++;
          throw StateError('The account form must not load the club catalog.');
        },
      );
      await registration.fillRegistration(tester);
      await tester.ensureVisible(find.text('Продолжить'));
      await tester.tap(find.text('Продолжить'));
      await tester.pump();
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single.youthId, isNull);
      expect(
        (repo.requests.single.metadata['club_registration']
                as Map<String, dynamic>)
            .containsKey('youth_id'),
        isFalse,
      );
      expect(
        (repo.requests.single.metadata['club_registration']
                as Map<String, dynamic>)
            .containsKey('receipt_key'),
        isFalse,
      );
      expect(loads, 0);
      repo.response.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Проверьте почту'), findsOneWidget);
      expect(find.text('Заявка отправлена'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final superAdmin in [false, true]) {
    testWidgets(
      'club management entry and editor require superadmin: $superAdmin',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWith(
                (ref) => Stream.value(const AppUser('actor')),
              ),
              accountAccessProvider.overrideWith(
                (ref) => Stream.value(
                  AccountAccess(superAdmin: superAdmin, canManageRoles: true),
                ),
              ),
              clubWorkspacesProvider.overrideWith((ref) async => []),
              managedClubsProvider.overrideWith((ref) async => []),
              registrationIntakeProvider.overrideWith(
                (ref) async => {'youth_id': null, 'waiting_count': 0},
              ),
            ],
            child: const MaterialApp(home: Scaffold(body: AdminPage())),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('manage-youth-clubs')),
          superAdmin ? findsOneWidget : findsNothing,
        );
        expect(find.text('Роли'), findsOneWidget);
        expect(find.text('Приходы'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authUserProvider.overrideWith(
                (ref) => Stream.value(const AppUser('actor')),
              ),
              accountAccessProvider.overrideWith(
                (ref) => Stream.value(AccountAccess(superAdmin: superAdmin)),
              ),
              managedClubsProvider.overrideWith((ref) async => []),
              registrationIntakeProvider.overrideWith(
                (ref) async => {'youth_id': null, 'waiting_count': 0},
              ),
            ],
            child: const MaterialApp(home: ManagedYouthPage()),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('create-youth-club')),
          superAdmin ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Доступ только для суперадмина'),
          superAdmin ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
