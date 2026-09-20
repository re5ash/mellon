import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/backend_provider.dart';
import '../auth/application/auth_providers.dart';

typedef CommunityScope = ({String? parish, String? youth});
typedef JsonRow = Map<String, dynamic>;

final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => CommunityRepository(ref.watch(backendProvider)),
);
final scopePermissionsProvider = FutureProvider.autoDispose
    .family<Set<String>, CommunityScope>((ref, scope) async {
      ref.watch(authUserProvider);
      return ref.watch(communityRepositoryProvider).permissions(scope);
    }, retry: (_, error) => null);
final myYouthProvider = FutureProvider.autoDispose<List<JsonRow>>((ref) async {
  if (ref.watch(authUserProvider).asData?.value == null) return [];
  return ref.watch(communityRepositoryProvider).rows('my_youth');
}, retry: (_, error) => null);
final appConfigurationProvider = FutureProvider.autoDispose<JsonRow>(
  (ref) => ref.watch(communityRepositoryProvider).configuration(),
  retry: (_, error) => null,
);

class CommunityRepository {
  const CommunityRepository(this.client);
  final SupabaseClient client;
  Future<dynamic> call(String name, [JsonRow params = const {}]) =>
      client.rpc<dynamic>(name, params: params);
  Future<List<JsonRow>> rows(String name, [JsonRow params = const {}]) async =>
      (await call(name, params) as List<dynamic>)
          .map((r) => Map<String, dynamic>.from(r as Map<String, dynamic>))
          .toList();
  JsonRow args(CommunityScope s) => {'p_parish': s.parish, 'p_youth': s.youth};
  Future<Set<String>> permissions(CommunityScope s) async => (await rows(
    s.parish == null ? 'my_permissions' : 'my_scope_permissions',
    s.parish == null ? {} : args(s),
  )).map((r) => r['permission_key'] as String).toSet();
  Future<JsonRow> configuration() async =>
      client.from('app_configuration').select().single();
  Future<List<JsonRow>> content(CommunityScope s, String kind, String? after) =>
      rows('scope_content', {...args(s), 'p_kind': kind, 'p_after': after});
  Future<List<JsonRow>> members(
    CommunityScope s,
    String search,
    String? after,
  ) =>
      rows('scope_members', {...args(s), 'p_search': search, 'p_after': after});
  Future<List<JsonRow>> roles(CommunityScope s) =>
      rows('assignable_roles', args(s));
  Future<void> saveContent(
    CommunityScope s,
    String kind,
    String id,
    JsonRow data,
    String? expected,
    String actor,
  ) async {
    await call('save_scope_content', {
      ...args(s),
      'p_kind': kind,
      'p_id': id,
      'p_data': data,
      'p_expected': expected,
      'p_expected_user': actor,
    });
  }
}

String scopeLabel(String scope) => switch (scope) {
  'global' => 'Всё приложение',
  'youth' => 'Молодёжка',
  _ => 'Приход',
};
String contentLabel(String kind) => switch (kind) {
  'events' => 'События и календарь',
  'posts' => 'Публикации',
  _ => 'Чаты',
};
String stateLabel(String? state) => switch (state) {
  'draft' => 'Черновик',
  'published' => 'Опубликовано',
  'cancelled' => 'Отменено',
  'archived' => 'В архиве',
  _ => '',
};
bool mayEdit(Set<String> rights, String kind) =>
    rights.contains('$kind.manage') || rights.contains('$kind.edit');
bool mayCreate(Set<String> rights, String kind) => kind == 'chats'
    ? rights.contains('chats.create')
    : rights.contains('$kind.manage') || rights.contains('$kind.create');
bool mayDelete(Set<String> rights, String kind) =>
    rights.contains('$kind.manage') || rights.contains('$kind.delete');
