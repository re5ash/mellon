import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_information_editor.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/feed/presentation/publication_fields.dart';

class PublicationRecorder implements CommunityRepository {
  final calls = <JsonRow>[];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  Future<dynamic> call(String name, [JsonRow params = const {}]) async {
    expect(name, 'save_club_publication');
    calls.add(params);
    return params['p_id'];
  }
}

Future<void> mountEditor(
  WidgetTester tester,
  PublicationRecorder repo,
  String kind, {
  JsonRow? row,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser('actor')),
        ),
        communityRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ClubInformationEditor(
                  club: 'club',
                  actor: 'actor',
                  kind: kind,
                  row: row,
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
}

void main() {
  for (final kind in ['events', 'schedule']) {
    testWidgets(
      '$kind publication defaults off; manual icon and toggle are saved together',
      (tester) async {
        final repo = PublicationRecorder();
        await mountEditor(tester, repo, kind);
        expect(
          tester
              .widget<PublicationFields>(find.byType(PublicationFields))
              .published,
          false,
        );
        await tester.enterText(
          find.byKey(const ValueKey('club-information-title')),
          'Лекция и обучение',
        );
        await tester.pump();
        expect(
          tester
              .widget<PublicationFields>(find.byType(PublicationFields))
              .icon
              .group,
          'Обучение',
        );
        await tester.ensureVisible(find.text('Сменить'));
        await tester.tap(find.text('Сменить'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ActionChip, 'Храм'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('publish-to-general-feed')),
        );
        await tester.tap(find.byKey(const ValueKey('publish-to-general-feed')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('save-club-information')));
        await tester.pumpAndSettle();
        expect(repo.calls, hasLength(1));
        final data = repo.calls.single['p_data'] as JsonRow;
        expect(data['publish_to_feed'], true);
        expect(data['icon_id'], 'faith_church');
        expect(data['icon_manual'], true);
        expect(repo.calls.single['p_kind'], kind);
        expect(repo.calls.single['p_expected'], isNull);
        expect(
          DateTime.parse(
            data['ends_at'] as String,
          ).isAfter(DateTime.parse(data['starts_at'] as String)),
          true,
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      '$kind edit preserves the record ID and sends an explicit unpublish',
      (tester) async {
        final repo = PublicationRecorder();
        await mountEditor(
          tester,
          repo,
          kind,
          row: {
            'id': 'record-id',
            'title': 'Встреча',
            'description': 'Текст',
            'publish_to_feed': true,
            'icon_id': 'learn_book',
            'icon_manual': true,
            'updated_at': '2026-09-19T10:00:00Z',
          },
        );
        final field = find.byKey(const ValueKey('publish-to-general-feed'));
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('save-club-information')));
        await tester.pumpAndSettle();
        expect(repo.calls.single['p_id'], 'record-id');
        expect(repo.calls.single['p_expected'], '2026-09-19T10:00:00Z');
        expect(
          (repo.calls.single['p_data'] as JsonRow)['publish_to_feed'],
          false,
        );
        expect(
          (repo.calls.single['p_data'] as JsonRow)['icon_id'],
          'learn_book',
        );
      },
    );
  }
}
