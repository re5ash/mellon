-- Mellon: unified role management. Run the whole file after club applications.
begin;
select pg_advisory_xact_lock(120015);
create table if not exists app_private.installed_features(feature text primary key,checksum text not null,installed_at timestamptz not null default now());
revoke all on app_private.installed_features from public,anon,authenticated;
do $install$
begin
 if exists(select 1 from app_private.installed_features where feature='role_manager_20260912') then
  if not exists(select 1 from app_private.installed_features where feature='role_manager_20260912' and checksum='cc35b6b533efa3515ae76d4599f6e1a1b570df2cb763cc2a5482d4ccc6acbaea') then raise exception 'Другая версия обновления управления ролями уже установлена'; end if;
  raise notice 'Управление ролями уже обновлено';
 else
  if to_regprocedure('public.review_youth_join_request(uuid,text,uuid)') is null or to_regprocedure('public.my_profile_v2()') is null then
   raise exception 'Сначала установите предыдущие обновления ролей, профиля и заявок в клуб (миграции 001–014)';
  end if;
  execute $role_migration$
-- Access restriction is account state, not an additional role. Existing club settings survive it.
create table app_private.account_access (
 user_id uuid primary key references public.profiles on delete cascade,
 guest_only boolean not null default false, changed_by uuid references public.profiles,
 updated_at timestamptz not null default now()
);
create table app_private.role_change_receipts (
 actor_id uuid not null references public.profiles on delete cascade, request_id uuid not null,
 user_id uuid not null references public.profiles on delete cascade, payload_hash text not null,
 created_at timestamptz not null default now(), primary key(actor_id,request_id)
);
alter table app_private.account_access enable row level security;
alter table app_private.role_change_receipts enable row level security;
revoke all on app_private.account_access,app_private.role_change_receipts from public,anon,authenticated;
create function app_private.is_restricted_guest(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.account_access where user_id=p_user and guest_only);
$$;
-- A member can belong to several clubs, including clubs at different parishes.
-- Parish membership itself is unchanged and does not confer club membership.
drop index public.youth_one_current;

create or replace function app_private.is_member(p_parish uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and (select auth.uid() is not null and exists(select 1 from public.memberships m
 where m.user_id=auth.uid() and m.parish_id=p_parish and m.status='active'));
$$;
create or replace function app_private.is_super_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and (select auth.uid() is not null and exists(select 1 from app_private.role_assignments a
 join app_private.roles r on r.id=a.role_id where a.user_id=auth.uid() and r.key='super_admin'
 and a.parish_id is null and a.youth_id is null and (a.expires_at is null or a.expires_at>now())));
$$;
create or replace function app_private.has_permission(p_key text,p_parish uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select case when app_private.is_restricted_guest(auth.uid()) then p_key='public.read' else (select exists(select 1 from app_private.permissions p where p.key=p_key
 and (p.scope='both' or (p.scope='global' and p_parish is null) or (p.scope='parish' and p_parish is not null))
 and (app_private.is_super_admin() or exists(
 select 1 from app_private.role_permissions rp join app_private.roles r on r.id=rp.role_id
 where rp.permission_key=p.key and r.scope<>'youth' and (
 (r.baseline=case when auth.uid() is null then 'guest' else 'authenticated' end and (p.scope<>'parish' or app_private.is_member(p_parish)))
 or exists(select 1 from app_private.role_assignments a where a.role_id=r.id and a.user_id=auth.uid() and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now())
 and ((r.scope='global' and a.parish_id is null) or (r.scope='parish' and a.parish_id=p_parish and app_private.is_member(p_parish))))))))) end;
$$;
create or replace function app_private.has_scope_permission(p_key text,p_parish uuid,p_youth uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and (select case when p_youth is null then app_private.has_permission(p_key,p_parish) else
 exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish and (
 app_private.is_super_admin() or app_private.has_permission(p_key,p_parish) and exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 join app_private.role_permissions rp on rp.role_id=r.id where a.user_id=auth.uid() and a.youth_id is null
 and r.baseline is null and rp.permission_key=p_key and (a.expires_at is null or a.expires_at>now())
 and ((r.scope='global' and a.parish_id is null) or (r.scope='parish' and a.parish_id=p_parish)))
 or (app_private.is_youth_member(p_youth) and (
 p_key in ('parish.read','chat.read','chat.send','messages.delete_own','events.attend')
 or exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 join app_private.role_permissions rp on rp.role_id=r.id where a.user_id=auth.uid() and a.youth_id=p_youth
 and a.parish_id=p_parish and r.scope='youth' and rp.permission_key=p_key and (a.expires_at is null or a.expires_at>now())))))) end);
$$;
create or replace function app_private.is_youth_member(p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and exists(
 select 1 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 where g.id=p_youth and m.user_id=auth.uid() and m.is_member and not g.is_archived);
$$;

create or replace function app_private.validate_role_assignment() returns trigger
language plpgsql security definer set search_path='' as $$
declare r app_private.roles;
begin
 select * into strict r from app_private.roles where id=new.role_id;
 if r.baseline is not null or (r.scope='global' and (new.parish_id is not null or new.youth_id is not null))
 or (r.scope='parish' and (new.parish_id is null or new.youth_id is not null))
 or (r.scope='youth' and (new.parish_id is null or new.youth_id is null)) then raise exception 'invalid_role_scope' using errcode='23514'; end if;
 if r.key='super_admin' and new.expires_at is not null then raise exception 'protected_role' using errcode='42501'; end if;
 if new.youth_id is null and new.parish_id is not null and not exists(select 1 from public.memberships m where m.user_id=new.user_id and m.parish_id=new.parish_id and m.status='active') then
 raise exception 'active_membership_required' using errcode='23514'; end if;
 if new.youth_id is not null and not exists(select 1 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 where m.user_id=new.user_id and m.youth_id=new.youth_id and m.is_member and g.parish_id=new.parish_id and not g.is_archived) then
 raise exception 'active_youth_membership_required' using errcode='23514'; end if;
 return new;
end $$;
create or replace function app_private.youth_membership_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.is_member and not exists(select 1 from public.youth_groups g where g.id=new.youth_id and not g.is_archived) then raise exception 'club_unavailable' using errcode='23514'; end if;
 if tg_op='UPDATE' and old.is_member and not new.is_member then
 delete from app_private.role_assignments where user_id=new.user_id and youth_id=new.youth_id;
 delete from public.chat_members where user_id=new.user_id and room_id in(select id from public.chat_rooms where youth_id=new.youth_id);
 end if; return new;
end $$;
create or replace function app_private.on_membership_end() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.status='active' and new.status<>'active' then
 delete from app_private.role_assignments where user_id=new.user_id and parish_id=new.parish_id and youth_id is null;
 delete from public.chat_members where user_id=new.user_id and room_id in(
 select id from public.chat_rooms where parish_id=new.parish_id and youth_id is null);
 end if; return new;
end $$;

create or replace function app_private.can_review_youth_request(p_user uuid,p_parish uuid,p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select p_user is not null and not app_private.is_restricted_guest(p_user) and exists(
 select 1 from app_private.role_assignments a
 join app_private.roles r on r.id=a.role_id
 join app_private.role_permissions rp on rp.role_id=r.id and rp.permission_key='youth.requests.review'
 where a.user_id=p_user and (a.expires_at is null or a.expires_at>now())
 and ((r.scope='global' and a.parish_id is null and a.youth_id is null)
 or (r.scope='parish' and a.parish_id=p_parish and a.youth_id is null and exists(select 1 from public.memberships m where m.user_id=p_user and m.parish_id=p_parish and m.status='active'))
 or (r.scope='youth' and a.parish_id=p_parish and a.youth_id=p_youth and exists(
 select 1 from public.youth_memberships m
 join public.youth_groups g on g.id=m.youth_id and not g.is_archived
 where m.user_id=p_user and m.youth_id=p_youth and m.is_member))));
$$;
create or replace function public.my_profile_v2() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
 select to_jsonb(p) into v from public.my_profile() p;
 return v || (select jsonb_build_object('phone',d.phone,'avatar_path',p.avatar_path,'email',coalesce(to_jsonb(u)->>'email',''),
 'parish_name',(select pa.name from public.memberships m join public.parishes pa on pa.id=m.parish_id where m.user_id=p.id and m.status='active'),
 'youth_name',(select string_agg(g.name, ', ' order by g.name,g.id) from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id where m.user_id=p.id and m.is_member and not g.is_archived))
 from public.profiles p join app_private.profile_private d on d.user_id=p.id join auth.users u on u.id=p.id where p.id=auth.uid());
end $$;
create or replace function public.revoke_role(p_assignment uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.role_assignments; v_key text;
begin
 perform pg_advisory_xact_lock(120010);
 select * into v from app_private.role_assignments where id=p_assignment for update;
 if not found or not app_private.can_assign_role(v.role_id,v.parish_id,v.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 select key into v_key from app_private.roles where id=v.role_id;
 if v_key='super_admin' and not exists(select 1 from app_private.role_assignments a where a.role_id=v.role_id and a.user_id<>v.user_id and not app_private.is_restricted_guest(a.user_id)
 and (a.expires_at is null or a.expires_at>now())) then raise exception 'last_super_admin' using errcode='23514'; end if;
 delete from app_private.role_assignments where id=v.id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'role.revoke','role_assignment',v.id,v.parish_id);
end $$;

create function app_private.can_manage_club_roles(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and exists(select 1 from public.youth_groups g where g.id=p_club
 and (app_private.is_super_admin() or app_private.has_permission('roles.assign',g.parish_id)
 or app_private.has_scope_permission('youth.roles.manage',g.parish_id,g.id)));
$$;
create function app_private.can_manage_person(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (app_private.is_super_admin() or exists(
 select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id) and (
 exists(select 1 from public.youth_memberships m where m.user_id=p_user and m.youth_id=g.id and m.is_member)
 or exists(select 1 from public.memberships m where m.user_id=p_user and m.parish_id=g.parish_id and m.status='active'))));
$$;
create function app_private.person_global_role(p_user uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when app_private.is_restricted_guest(p_user) then 'guest'
 when exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and r.key='super_admin' and a.parish_id is null and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now())) then 'super_admin' else 'user' end;
$$;
create function app_private.person_club_role(p_user uuid,p_club uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when not exists(select 1 from public.youth_memberships m where m.user_id=p_user and m.youth_id=p_club and m.is_member) then null
 when exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and a.youth_id=p_club and r.key='youth_leader' and (a.expires_at is null or a.expires_at>now())) then 'youth_leader'
 when exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and a.youth_id=p_club and r.key='youth_moderator' and (a.expires_at is null or a.expires_at>now())) then 'youth_moderator' else 'user' end;
$$;
create function app_private.person_roles_revision(p_user uuid) returns text
language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object(
 'access',(select to_jsonb(a) from app_private.account_access a where a.user_id=p_user),
 'roles',(select jsonb_agg(to_jsonb(a) order by a.id) from app_private.role_assignments a where a.user_id=p_user),
 'clubs',(select jsonb_agg(to_jsonb(m) order by m.youth_id) from public.youth_memberships m where m.user_id=p_user),
 'parishes',(select jsonb_agg(to_jsonb(m) order by m.id) from public.memberships m where m.user_id=p_user)
 )::text);
$$;
create function public.my_account_access() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('restricted_guest',app_private.is_restricted_guest(auth.uid()),
 'super_admin',app_private.is_super_admin(),
 'can_manage_roles',app_private.is_super_admin() or exists(select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id)));
$$;
create function public.role_manager_people(p_search text default '',p_after uuid default null) returns table(
 user_id uuid,display_name text,avatar_path text,summary text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not (app_private.is_super_admin() or exists(select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id))) then
 raise exception 'forbidden' using errcode='42501'; end if;
 return query select p.id,p.display_name,p.avatar_path,
 case app_private.person_global_role(p.id) when 'super_admin' then 'Суперадмин' when 'guest' then 'Гость' else coalesce(
 (select string_agg(case app_private.person_club_role(p.id,g.id) when 'youth_leader' then 'Руководитель' when 'youth_moderator' then 'Модератор' else 'Участник' end || ' · ' || g.name, '; ' order by g.name,g.id)
 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 where m.user_id=p.id and m.is_member and (app_private.is_super_admin() or app_private.can_manage_club_roles(g.id))), 'Участник') || case when exists(select 1 from app_private.role_assignments inherited where inherited.user_id=p.id
 and inherited.youth_id is null and inherited.parish_id is not null and (inherited.expires_at is null or inherited.expires_at>now()))
 then ' · Есть дополнительные права' else '' end end
 from public.profiles p where app_private.can_manage_person(p.id) and (p_after is null or p.id>p_after)
 and position(lower(btrim(coalesce(p_search,''))) in lower(p.display_name))>0
 order by p.id limit 31;
end $$;
create function public.role_manager_person(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.can_manage_person(p_user) then raise exception 'forbidden' using errcode='42501'; end if;
 return (select jsonb_build_object('user_id',p.id,'display_name',p.display_name,'avatar_path',p.avatar_path,
 'email',coalesce(to_jsonb(u)->>'email',''),'global_role',app_private.person_global_role(p.id),
 'can_global',app_private.is_super_admin(),'revision',app_private.person_roles_revision(p.id),
 'clubs',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'archived',g.is_archived,
 'role',case when app_private.can_manage_club_roles(g.id) then app_private.person_club_role(p.id,g.id) else null end,'can_edit',not g.is_archived and app_private.can_manage_club_roles(g.id),
 'can_lead',app_private.is_super_admin() or app_private.has_permission('roles.assign',g.parish_id),
 'inherited_rights',app_private.can_manage_club_roles(g.id) and exists(select 1 from app_private.role_assignments inherited
 where inherited.user_id=p.id and inherited.youth_id is null and inherited.parish_id=g.parish_id
 and (inherited.expires_at is null or inherited.expires_at>now()))) order by g.name,g.id)
 from public.youth_groups g join public.parishes pa on pa.id=g.parish_id
 where app_private.is_super_admin() or app_private.can_manage_club_roles(g.id) or pa.is_published and not g.is_archived),'[]'::jsonb))
 from public.profiles p join auth.users u on u.id=p.id where p.id=p_user);
end $$;
create function public.save_person_roles(p_user uuid,p_global_role text,p_clubs jsonb,p_revision text,p_request uuid,p_expected_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_global boolean; v_hash text; v_receipt app_private.role_change_receipts;
 v_item jsonb; v_club uuid; v_group public.youth_groups; v_role text; v_old text; v_role_id uuid;
begin
 if v_actor is null or v_actor is distinct from p_expected_actor then raise exception 'forbidden' using errcode='42501'; end if;
 if p_user is null or p_request is null or p_revision is null or p_clubs is null or jsonb_typeof(p_clubs)<>'array'
 or jsonb_array_length(p_clubs)>100 or (p_global_role is not null and p_global_role not in ('super_admin','user','guest')) then
 raise exception 'invalid_role' using errcode='22023'; end if;
 v_hash:=md5(jsonb_build_object('user',p_user,'global',p_global_role,'clubs',p_clubs,'revision',p_revision)::text);
 -- Shared lock with all previous role/membership RPCs. No partial role saves.
 perform pg_advisory_xact_lock(120010);
 select * into v_receipt from app_private.role_change_receipts where actor_id=v_actor and request_id=p_request;
 if found then
 if v_receipt.payload_hash<>v_hash or v_receipt.user_id<>p_user then raise exception 'role_request_conflict' using errcode='40001'; end if;
 return jsonb_build_object('saved',true);
 end if;
 if not app_private.can_manage_person(p_user) then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_user for update;
 if not found then raise exception 'profile_unavailable' using errcode='22023'; end if;
 if app_private.person_roles_revision(p_user) is distinct from p_revision then raise exception 'role_edit_conflict' using errcode='40001'; end if;
 v_global:=app_private.is_super_admin();
 if p_global_role is not null and not v_global then raise exception 'forbidden' using errcode='42501'; end if;
 if p_global_role in ('user','guest') and app_private.person_global_role(p_user)='super_admin' and not exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id<>p_user and r.key='super_admin' and a.parish_id is null and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now()) and not app_private.is_restricted_guest(a.user_id)) then
 raise exception 'last_super_admin' using errcode='23514'; end if;
 if exists(select 1 from jsonb_array_elements(p_clubs) x group by x->>'id' having count(*)>1) then raise exception 'invalid_role' using errcode='22023'; end if;
 -- Validate the entire patch using the actor's existing permissions first.
 for v_item in select * from jsonb_array_elements(p_clubs) loop
 begin v_club:=(v_item->>'id')::uuid; exception when invalid_text_representation then raise exception 'invalid_role' using errcode='22023'; end;
 v_role:=v_item->>'role';
 if v_club is null or v_role is null or v_role not in ('youth_leader','youth_moderator','user') then raise exception 'invalid_role' using errcode='22023'; end if;
 select * into v_group from public.youth_groups where id=v_club for share;
 if not found or v_group.is_archived then raise exception 'club_unavailable' using errcode='22023'; end if;
 if not app_private.can_manage_club_roles(v_club) then raise exception 'forbidden' using errcode='42501'; end if;
 v_old:=app_private.person_club_role(p_user,v_club);
 if (v_role='youth_leader' or v_old='youth_leader') and not(v_global or app_private.has_permission('roles.assign',v_group.parish_id)) then raise exception 'forbidden' using errcode='42501'; end if;
 -- Existing custom club grants cannot be removed by an actor lacking those rights.
 if not v_global and exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and a.youth_id=v_club and not app_private.can_assign_role(r.id,v_group.parish_id,v_club)) then raise exception 'forbidden' using errcode='42501'; end if;
 end loop;
 for v_item in select * from jsonb_array_elements(p_clubs) loop
 v_club:=(v_item->>'id')::uuid;v_role:=v_item->>'role';
 select * into strict v_group from public.youth_groups where id=v_club;
 insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(v_club,p_user,true,false)
 on conflict(youth_id,user_id) do update set is_member=true,updated_at=now();
 -- Only this selected club changes. Active status and other clubs survive.
 delete from app_private.role_assignments where user_id=p_user and youth_id=v_club;
 if v_role<>'user' then
 select id into strict v_role_id from app_private.roles where key=v_role;
 insert into app_private.role_assignments(user_id,role_id,parish_id,youth_id,granted_by)
 values(p_user,v_role_id,v_group.parish_id,v_club,v_actor);
 end if;
 end loop;
 if p_global_role is not null then
 delete from app_private.role_assignments where user_id=p_user and parish_id is null and youth_id is null;
 insert into app_private.account_access(user_id,guest_only,changed_by) values(p_user,p_global_role='guest',v_actor)
 on conflict(user_id) do update set guest_only=excluded.guest_only,changed_by=excluded.changed_by,updated_at=now();
 if p_global_role='super_admin' then
 select id into strict v_role_id from app_private.roles where key='super_admin';
 insert into app_private.role_assignments(user_id,role_id,granted_by) values(p_user,v_role_id,v_actor);
 end if;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,metadata)
 values(v_actor,'roles.save','profile',p_user,jsonb_build_object('global',p_global_role,'clubs',p_clubs));
 insert into app_private.role_change_receipts(actor_id,request_id,user_id,payload_hash) values(v_actor,p_request,p_user,v_hash);
 return jsonb_build_object('saved',true);
end $$;
-- An authorised manager may load a signed avatar; there is no public avatar bucket.
create function app_private.can_view_role_avatar(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.avatar_path=p_path and app_private.can_manage_person(p.id));
$$;
revoke all on function app_private.can_view_role_avatar(text) from public,anon,authenticated;
grant execute on function app_private.can_view_role_avatar(text) to authenticated;
create policy role_manager_avatar_read on storage.objects for select to authenticated using(
 bucket_id='profile-avatars' and app_private.can_view_role_avatar(name));
-- Guest access must not use self-readable memberships or cached room entitlements.
create policy guest_memberships_limit on public.memberships as restrictive for select to authenticated using(not app_private.is_restricted_guest(auth.uid()));
create policy guest_youth_memberships_limit on public.youth_memberships as restrictive for select to authenticated using(not app_private.is_restricted_guest(auth.uid()));
create policy guest_notifications_limit on public.notifications as restrictive for select to authenticated using(not app_private.is_restricted_guest(auth.uid()));
create or replace function public.my_club_applications() returns table(id uuid,youth_name text,status text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.id,g.name,r.status,r.created_at from app_private.youth_join_requests r join public.youth_groups g on g.id=r.youth_id
 where r.user_id=auth.uid() and not app_private.is_restricted_guest(auth.uid()) order by r.created_at desc limit 20;
$$;
revoke all on function app_private.is_restricted_guest(uuid),app_private.can_manage_club_roles(uuid),app_private.can_manage_person(uuid),
 app_private.person_global_role(uuid),app_private.person_club_role(uuid,uuid),app_private.person_roles_revision(uuid),
 public.my_account_access(),public.role_manager_people(text,uuid),public.role_manager_person(uuid),public.save_person_roles(uuid,text,jsonb,text,uuid,uuid) from public,anon,authenticated;
grant execute on function app_private.is_restricted_guest(uuid),app_private.can_manage_person(uuid) to authenticated;
grant execute on function public.my_account_access() to anon,authenticated;
grant execute on function public.role_manager_people(text,uuid),public.role_manager_person(uuid),public.save_person_roles(uuid,text,jsonb,text,uuid,uuid) to authenticated;

$role_migration$;
  insert into app_private.installed_features(feature,checksum) values('role_manager_20260912','cc35b6b533efa3515ae76d4599f6e1a1b570df2cb763cc2a5482d4ccc6acbaea');
 end if;
end $install$;
commit;
