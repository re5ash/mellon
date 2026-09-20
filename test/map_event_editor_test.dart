import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/community/club_information_editor.dart';
import 'package:moy_prihod/features/community/community_repository.dart';
import 'package:moy_prihod/features/community/content_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _UnusedSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected backend call');
}

class MapEditorRepository extends CommunityRepository {
  MapEditorRepository() : super(_UnusedSupabase());
  String? method;
  JsonRow? params;
  @override
  Future<dynamic> call(String name, [JsonRow data = const {}]) async {
    method = name;
    params = data;
    return data['p_id'];
  }
}

void main() {
  for (final club in [true, false]) {
    testWidgets(
      '${club ? 'club' : 'scope'} editor sends map changes with the original revision',
      (tester) async {
        final repo = MapEditorRepository();
        const scope = (parish: 'parish', youth: 'club');
        final row = <String, dynamic>{
          'id': 'event',
          'title': 'Встреча',
          'description': 'Описание',
          'status': 'published',
          'visibility': 'parish',
          'starts_at': '2026-09-13T16:00:00Z',
          'ends_at': '2026-09-13T18:00:00Z',
          'updated_at': '2026-09-12T12:00:00Z',
          'show_on_map': true,
          'map_latitude': 54.723306,
          'map_longitude': 20.526467,
        };
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              communityRepositoryProvider.overrideWithValue(repo),
              authUserProvider.overrideWith(
                (ref) => Stream.value(const AppUser('me')),
              ),
              scopePermissionsProvider(
                scope,
              ).overrideWith((ref) async => {'events.edit'}),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  final actor = ref.watch(authUserProvider).asData?.value;
                  return Scaffold(
                    body: Center(
                      child: FilledButton(
                        onPressed: actor == null
                            ? null
                            : () {
                                final Widget editor = club
                                    ? ClubInformationEditor(
                                        club: 'club',
                                        actor: 'me',
                                        kind: 'events',
                                        row: row,
                                      )
                                    : ContentEditor(
                                        scope: scope,
                                        kind: 'events',
                                        row: row,
                                      );
                                Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(builder: (_) => editor),
                                );
                              },
                        child: const Text('Открыть'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('show-event-on-map'));
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        final save = find.text('Сохранить');
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          repo.method,
          club ? 'save_club_information' : 'save_scope_content',
        );
        expect(repo.params!['p_expected'], row['updated_at']);
        expect(repo.params!['p_expected_user'], 'me');
        final sent = repo.params!['p_data'] as JsonRow;
        expect(sent['show_on_map'], false);
        expect(sent['map_latitude'], 54.723306);
        expect(sent['map_longitude'], 20.526467);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
