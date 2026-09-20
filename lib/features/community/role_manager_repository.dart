import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend/backend_provider.dart';
import '../../core/errors/app_failure.dart';

class RoleOption {
  const RoleOption({
    required this.key,
    required this.title,
    this.baseline,
    this.assignable = false,
  });
  factory RoleOption.fromJson(Map<String, dynamic> j) => RoleOption(
    key: j['key'] as String,
    title: j['title'] as String,
    baseline: j['baseline'] as String?,
    assignable: j['assignable'] == true,
  );
  final String key, title;
  final String? baseline;
  final bool assignable;
  bool get isGuest => baseline == 'guest';
  bool get isMember => baseline == 'authenticated';
}

List<RoleOption> _roleOptions(Object? value) => (value as List<dynamic>)
    .map(
      (r) => RoleOption.fromJson(
        Map<String, dynamic>.from(r as Map<String, dynamic>),
      ),
    )
    .toList(growable: false);

class RolePerson {
  const RolePerson({
    required this.id,
    required this.name,
    required this.summary,
    this.avatar,
  });
  factory RolePerson.fromJson(Map<String, dynamic> j) => RolePerson(
    id: j['user_id'] as String,
    name: j['display_name'] as String,
    summary: j['summary'] as String? ?? '',
    avatar: j['avatar_path'] as String?,
  );
  final String id, name, summary;
  final String? avatar;
}

class RoleClub {
  const RoleClub({
    required this.id,
    required this.name,
    required this.roles,
    this.role,
    this.canEdit = false,
    this.multipleRoles = false,
    this.archived = false,
    this.inheritedRights = false,
  });
  factory RoleClub.fromJson(Map<String, dynamic> j) => RoleClub(
    id: j['id'] as String,
    name: j['name'] as String,
    roles: _roleOptions(j['roles']),
    role: j['role'] as String?,
    canEdit: j['can_edit'] == true,
    multipleRoles: j['multiple_roles'] == true,
    archived: j['archived'] == true,
    inheritedRights: j['inherited_rights'] == true,
  );
  final String id, name;
  final String? role;
  final List<RoleOption> roles;
  final bool canEdit, multipleRoles, archived, inheritedRights;
  String roleTitle(String? key) =>
      roles.where((r) => r.key == key).firstOrNull?.title ?? key ?? '';
}

class RolePersonDetails {
  const RolePersonDetails({
    required this.person,
    required this.email,
    required this.globalRole,
    required this.revision,
    required this.clubs,
    required this.canGlobal,
    required this.globalRoles,
    this.globalMultipleRoles = false,
  });
  factory RolePersonDetails.fromJson(Map<String, dynamic> j) =>
      RolePersonDetails(
        person: RolePerson.fromJson(j),
        email: j['email'] as String? ?? '',
        globalRole: j['global_role'] as String,
        revision: j['revision'] as String,
        canGlobal: j['can_global'] == true,
        globalRoles: _roleOptions(j['global_roles']),
        globalMultipleRoles: j['global_multiple_roles'] == true,
        clubs: (j['clubs'] as List<dynamic>)
            .map(
              (c) => RoleClub.fromJson(
                Map<String, dynamic>.from(c as Map<String, dynamic>),
              ),
            )
            .toList(),
      );
  final RolePerson person;
  final String email, globalRole, revision;
  final bool canGlobal, globalMultipleRoles;
  final List<RoleOption> globalRoles;
  final List<RoleClub> clubs;
}

abstract class RoleManagerRepository {
  Future<List<RolePerson>> people(String search, String? after);
  Future<RolePersonDetails> person(String id);
  Future<void> save({
    required String user,
    required String actor,
    required String revision,
    required String request,
    required String? globalRole,
    required Map<String, String> clubs,
  });
  Future<String?> avatarUrl(String path);
}

final roleManagerRepositoryProvider = Provider<RoleManagerRepository>(
  (ref) => SupabaseRoleManagerRepository(ref.watch(backendProvider)),
);
final roleAvatarProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, path) => ref.watch(roleManagerRepositoryProvider).avatarUrl(path),
  retry: (_, error) => null,
);

Future<T> _catalogRequest<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on PostgrestException catch (error) {
    if (error.code == 'PGRST202' || error.code == '42883') {
      throw const AppFailure(
        'Управление ролями ещё не обновлено на сервере. Обратитесь к администратору приложения.',
      );
    }
    if (error.message == 'role_edit_conflict') {
      throw const AppFailure(
        'Права или каталог ролей изменились. Ваш выбор сохранён на экране. Загрузите актуальные права перед повторным редактированием.',
      );
    }
    rethrow;
  }
}

class SupabaseRoleManagerRepository implements RoleManagerRepository {
  const SupabaseRoleManagerRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<RolePerson>> people(String search, String? after) async =>
      (await client.rpc<List<dynamic>>(
            'role_manager_people',
            params: {'p_search': search, 'p_after': after},
          ))
          .map(
            (r) => RolePerson.fromJson(
              Map<String, dynamic>.from(r as Map<String, dynamic>),
            ),
          )
          .toList();
  @override
  Future<RolePersonDetails> person(String id) =>
      _catalogRequest<RolePersonDetails>(
        () async => RolePersonDetails.fromJson(
          await client.rpc<Map<String, dynamic>>(
            'role_manager_person_v2',
            params: {'p_user': id},
          ),
        ),
      );
  @override
  Future<void> save({
    required String user,
    required String actor,
    required String revision,
    required String request,
    required String? globalRole,
    required Map<String, String> clubs,
  }) => _catalogRequest<void>(() async {
    await client.rpc<dynamic>(
      'save_person_roles_v2',
      params: {
        'p_user': user,
        'p_expected_actor': actor,
        'p_revision': revision,
        'p_request': request,
        'p_global_role': globalRole,
        'p_clubs': [
          for (final entry in clubs.entries)
            {'id': entry.key, 'role': entry.value},
        ],
      },
    );
  });

  @override
  Future<String?> avatarUrl(String path) =>
      client.storage.from('profile-avatars').createSignedUrl(path, 300);
}
