-- Мой приход: роли, молодёжки, модерация и профиль. Run the whole file.
begin;
select pg_advisory_xact_lock(120012);
create table if not exists app_private.installed_features(feature text primary key,checksum text not null,installed_at timestamptz not null default now());
revoke all on app_private.installed_features from public,anon,authenticated;
do $install$
begin
 if exists(select 1 from app_private.installed_features where feature='roles_profile_20260912') then
  if not exists(select 1 from app_private.installed_features where feature='roles_profile_20260912' and checksum='5be755d7848cf987b9618113169624a94b48111c0c92378cd75dbfa84b15efc2') then raise exception 'A different roles/profile update is already installed'; end if;
  raise notice 'Обновление ролей и профиля уже установлено';
 else
  if to_regprocedure('public.admin_save_chat(uuid,uuid,boolean,text,text,text,text,integer,boolean,bigint,uuid)') is null then raise exception 'Сначала установите предыдущие миграции приложения 001–009'; end if;
  execute $migration_body$
create table public.youth_groups (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 name text not null check(length(btrim(name)) between 1 and 160),
 description text not null default '' check(length(description)<=5000),
 is_archived boolean not null default false, created_by uuid not null references public.profiles,
 created_at timestamptz not null default now(), revision bigint not null default 1,
 unique(id,parish_id)
);
create table public.youth_memberships (
 id uuid primary key default gen_random_uuid(), youth_id uuid not null references public.youth_groups,
 user_id uuid not null references public.profiles on delete cascade,
 is_member boolean not null default true, is_activist boolean not null default false,
 revision bigint not null default 1, updated_at timestamptz not null default now(),
 unique(youth_id,user_id), check(is_member or not is_activist)
);
create unique index youth_one_current on public.youth_memberships(user_id) where is_member;
create index youth_members_lookup on public.youth_memberships(youth_id,user_id) where is_member;
alter table public.youth_groups enable row level security;
alter table public.youth_memberships enable row level security;
revoke all on public.youth_groups,public.youth_memberships from public,anon,authenticated;
grant select on public.youth_groups to anon,authenticated;
grant select on public.youth_memberships to authenticated;
create trigger youth_group_revision before update on public.youth_groups for each row execute function app_private.chat_revision();
create trigger youth_member_revision before update on public.youth_memberships for each row execute function app_private.chat_revision();

alter table app_private.roles drop constraint roles_scope_check;
alter table app_private.roles add constraint roles_scope_check check(scope in ('global','parish','youth'));
alter table app_private.role_assignments add column youth_id uuid references public.youth_groups;
drop index app_private.role_assignment_parish;
create unique index role_assignment_parish on app_private.role_assignments(user_id,role_id,parish_id) where parish_id is not null and youth_id is null;
create unique index role_assignment_youth on app_private.role_assignments(user_id,role_id,youth_id) where youth_id is not null;

insert into app_private.permissions(key,description,scope) values
 ('roles.assign','Назначать роли в своём приходе','parish'),
 ('youths.manage','Создавать и изменять молодёжки прихода','parish'),
 ('youth.members.manage','Управлять участниками своей молодёжки','parish'),
 ('youth.roles.manage','Назначать модераторов своей молодёжки','parish'),
 ('youth.active.manage','Вести актив молодёжки','parish'),
 ('youth.requests.review','Рассматривать заявки в молодёжку (резерв)','parish'),
 ('chats.create','Создавать чаты отдельно от их администрирования','parish'),
 ('messages.delete_own','Удалять свои сообщения','parish'),
 ('messages.delete_any','Удалять любые сообщения','parish'),
 ('messages.pin','Закреплять и откреплять сообщения','parish'),
 ('events.create','Создавать события','parish'),
 ('events.edit','Редактировать события','parish'),
 ('events.delete','Удалять события','parish'),
 ('settings.manage','Глобальные настройки приложения','global');
insert into app_private.roles(key,title,scope) values
 ('youth_leader','Руководитель молодёжки','youth'),
 ('youth_moderator','Модератор молодёжки','youth');
insert into app_private.role_permissions(role_id,permission_key)
 select r.id,p.key from app_private.roles r cross join app_private.permissions p
 where (r.key='super_admin')
 or (r.key='parish_admin' and p.scope in ('parish','both'))
 or (r.key='user' and p.key='messages.delete_own')
 or (r.key='youth_leader' and p.key in ('parish.read','chat.read','chat.send','messages.delete_own','messages.delete_any','messages.pin','chats.moderate','chats.manage','chats.create','channels.publish','events.create','events.edit','events.delete','events.manage','posts.manage','youth.members.manage','youth.roles.manage','youth.active.manage','youth.requests.review'))
 or (r.key='youth_moderator' and p.key in ('parish.read','chat.read','chat.send','messages.delete_own','messages.delete_any','messages.pin','events.create','events.edit'))
 on conflict do nothing;
-- Existing custom chat managers retain their existing create capability.
insert into app_private.role_permissions(role_id,permission_key)
 select role_id,'chats.create' from app_private.role_permissions where permission_key='chats.manage' on conflict do nothing;

create function app_private.is_super_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from app_private.role_assignments a
 join app_private.roles r on r.id=a.role_id where a.user_id=auth.uid() and r.key='super_admin'
 and a.parish_id is null and a.youth_id is null and (a.expires_at is null or a.expires_at>now()));
$$;
create or replace function app_private.has_permission(p_key text,p_parish uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.permissions p where p.key=p_key
 and (p.scope='both' or (p.scope='global' and p_parish is null) or (p.scope='parish' and p_parish is not null))
 and (app_private.is_super_admin() or exists(
 select 1 from app_private.role_permissions rp join app_private.roles r on r.id=rp.role_id
 where rp.permission_key=p.key and r.scope<>'youth' and (
 (r.baseline=case when auth.uid() is null then 'guest' else 'authenticated' end and (p.scope<>'parish' or app_private.is_member(p_parish)))
 or exists(select 1 from app_private.role_assignments a where a.role_id=r.id and a.user_id=auth.uid() and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now())
 and ((r.scope='global' and a.parish_id is null) or (r.scope='parish' and a.parish_id=p_parish and app_private.is_member(p_parish))))))));
$$;
create function app_private.is_youth_member(p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 where g.id=p_youth and m.user_id=auth.uid() and m.is_member and not g.is_archived and app_private.is_member(g.parish_id));
$$;
create function app_private.has_scope_permission(p_key text,p_parish uuid,p_youth uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select case when p_youth is null then app_private.has_permission(p_key,p_parish) else
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
 and a.parish_id=p_parish and r.scope='youth' and rp.permission_key=p_key and (a.expires_at is null or a.expires_at>now())))))) end;
$$;
create function public.my_scope_permissions(p_parish uuid,p_youth uuid default null) returns table(permission_key text)
language sql stable security definer set search_path='' as $$
 select p.key from app_private.permissions p where app_private.has_scope_permission(p.key,p_parish,p_youth);
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
 if new.parish_id is not null and not exists(select 1 from public.memberships m where m.user_id=new.user_id and m.parish_id=new.parish_id and m.status='active') then
 raise exception 'active_membership_required' using errcode='23514'; end if;
 if new.youth_id is not null and not exists(select 1 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 where m.user_id=new.user_id and m.youth_id=new.youth_id and m.is_member and g.parish_id=new.parish_id and not g.is_archived) then
 raise exception 'active_youth_membership_required' using errcode='23514'; end if;
 return new;
end $$;
create or replace function app_private.on_membership_end() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.status='active' and new.status<>'active' then
 delete from app_private.role_assignments where user_id=new.user_id and parish_id=new.parish_id;
 delete from public.chat_members where user_id=new.user_id and room_id in(select id from public.chat_rooms where parish_id=new.parish_id);
 update public.youth_memberships set is_member=false,is_activist=false,updated_at=now()
 where user_id=new.user_id and youth_id in(select id from public.youth_groups where parish_id=new.parish_id) and is_member;
 end if;
 return new;
end $$;
create function app_private.youth_membership_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.is_member and not exists(select 1 from public.memberships m join public.youth_groups g on g.parish_id=m.parish_id
 where g.id=new.youth_id and m.user_id=new.user_id and m.status='active' and not g.is_archived) then
 raise exception 'active_membership_required' using errcode='23514'; end if;
 if tg_op='UPDATE' and old.is_member and not new.is_member then
 delete from app_private.role_assignments where user_id=new.user_id and youth_id=new.youth_id;
 end if;
 return new;
end $$;
create trigger youth_membership_guard before insert or update on public.youth_memberships for each row execute function app_private.youth_membership_guard();

create function app_private.can_assign_role(p_role uuid,p_parish uuid,p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.roles r where r.id=p_role and r.baseline is null
 and ((r.scope='global' and p_parish is null and p_youth is null)
 or (r.scope='parish' and p_parish is not null and p_youth is null)
 or (r.scope='youth' and p_youth is not null and exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish)))
 and (app_private.has_permission('roles.manage') or (
 r.scope<>'global' and (app_private.has_permission('roles.assign',p_parish)
 or r.scope='youth' and r.key<>'youth_leader' and app_private.has_scope_permission('youth.roles.manage',p_parish,p_youth))
 and not exists(select 1 from app_private.role_permissions rp where rp.role_id=r.id
 and not app_private.has_scope_permission(rp.permission_key,p_parish,p_youth)))));
$$;
create function public.assign_scoped_role(p_user uuid,p_role text,p_parish uuid default null,p_youth uuid default null,p_expires_at timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_role uuid; v_id uuid;
begin
 perform pg_advisory_xact_lock(120010);
 select id into v_role from app_private.roles where key=p_role;
 if v_role is null or not app_private.can_assign_role(v_role,p_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_user for update;
 if not found then raise exception 'profile_unavailable' using errcode='22023'; end if;
 select id into v_id from app_private.role_assignments where user_id=p_user and role_id=v_role
 and parish_id is not distinct from p_parish and youth_id is not distinct from p_youth;
 if v_id is null then
 insert into app_private.role_assignments(user_id,role_id,parish_id,youth_id,granted_by,expires_at)
 values(p_user,v_role,p_parish,p_youth,auth.uid(),p_expires_at) returning id into v_id;
 else update app_private.role_assignments set expires_at=p_expires_at,granted_by=auth.uid() where id=v_id; end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'role.grant','role_assignment',v_id,p_parish,jsonb_build_object('role',p_role,'user',p_user,'youth',p_youth));
 return v_id;
end $$;
create or replace function public.grant_role(p_user uuid,p_role text,p_parish uuid default null,p_expires_at timestamptz default null) returns uuid
language sql security definer set search_path='' as $$ select public.assign_scoped_role(p_user,p_role,p_parish,null,p_expires_at); $$;
create or replace function public.revoke_role(p_assignment uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.role_assignments; v_key text;
begin
 perform pg_advisory_xact_lock(120010);
 select * into v from app_private.role_assignments where id=p_assignment for update;
 if not found or not app_private.can_assign_role(v.role_id,v.parish_id,v.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 select key into v_key from app_private.roles where id=v.role_id;
 if v_key='super_admin' and not exists(select 1 from app_private.role_assignments a where a.role_id=v.role_id and a.id<>v.id
 and (a.expires_at is null or a.expires_at>now())) then raise exception 'last_super_admin' using errcode='23514'; end if;
 delete from app_private.role_assignments where id=v.id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'role.revoke','role_assignment',v.id,v.parish_id);
end $$;
create or replace function public.define_role(p_key text,p_title text,p_scope text,p_permissions text[]) returns uuid
language plpgsql security definer set search_path='' as $$
declare v app_private.roles; v_id uuid;
begin
 if not app_private.has_permission('roles.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 if p_key is null or p_key !~ '^[a-z][a-z0-9_]{2,63}$' or length(btrim(coalesce(p_title,''))) not between 1 and 100
 or p_scope is null or p_scope not in ('global','parish','youth') or p_permissions is null then raise exception 'invalid_role' using errcode='22023'; end if;
 if exists(select 1 from unnest(p_permissions) x left join app_private.permissions p on p.key=x where p.key is null
 or p_scope<>'global' and p.scope='global') then raise exception 'invalid_permissions' using errcode='22023'; end if;
 select * into v from app_private.roles where key=p_key for update;
 if found then
 if v.baseline is not null or v.key in ('super_admin','parish_admin','youth_leader','youth_moderator') or v.scope<>p_scope then raise exception 'protected_role' using errcode='42501'; end if;
 v_id=v.id; update app_private.roles set title=btrim(p_title) where id=v_id;
 delete from app_private.role_permissions where role_id=v_id;
 else insert into app_private.roles(key,title,scope) values(p_key,btrim(p_title),p_scope) returning id into v_id; end if;
 insert into app_private.role_permissions select distinct v_id,x from unnest(p_permissions) x;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'role.define','role',v_id,jsonb_build_object('key',p_key));
 return v_id;
end $$;
create function public.permission_catalog() returns table(key text,description text,scope text)
language sql stable security definer set search_path='' as $$
 select p.key,p.description,p.scope from app_private.permissions p where app_private.has_permission('roles.manage') order by p.key;
$$;
create function public.assignable_roles(p_parish uuid default null,p_youth uuid default null) returns table(role_key text,title text,scope text,permissions text[])
language sql stable security definer set search_path='' as $$
 select r.key,r.title,r.scope,array(select rp.permission_key from app_private.role_permissions rp where rp.role_id=r.id order by rp.permission_key)
 from app_private.roles r where app_private.can_assign_role(r.id,p_parish,p_youth) order by r.title;
$$;
create function public.scope_members(p_parish uuid default null,p_youth uuid default null,p_search text default '',p_after uuid default null) returns table(
 user_id uuid,display_name text,is_youth_member boolean,is_activist boolean,member_revision bigint,assignments jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
 if not(app_private.has_permission('roles.manage') or p_parish is not null and
 (app_private.has_permission('memberships.read',p_parish) or app_private.has_permission('roles.assign',p_parish)
 or p_youth is not null and (app_private.has_scope_permission('youth.members.manage',p_parish,p_youth) or app_private.has_scope_permission('youth.roles.manage',p_parish,p_youth)))) then
 raise exception 'forbidden' using errcode='42501'; end if;
 if p_youth is not null and not exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish) then raise exception 'invalid_scope' using errcode='22023'; end if;
 return query select p.id,p.display_name,coalesce(m.is_member,false),coalesce(m.is_activist,false),coalesce(m.revision,0),
 coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'key',r.key,'title',r.title,'expires_at',a.expires_at,'can_revoke',app_private.can_assign_role(r.id,p_parish,p_youth)))
 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id where a.user_id=p.id
 and a.parish_id is not distinct from p_parish and a.youth_id is not distinct from p_youth and (a.expires_at is null or a.expires_at>now())),'[]'::jsonb)
 from public.profiles p left join public.youth_memberships m on m.user_id=p.id and m.youth_id=p_youth
 where (p_parish is null or exists(select 1 from public.memberships pm where pm.user_id=p.id and pm.parish_id=p_parish and pm.status='active'))
 and (p_after is null or p.id>p_after) and (coalesce(btrim(p_search),'')='' or position(lower(btrim(p_search)) in lower(p.display_name||' '||p.id::text))>0)
 order by p.id limit 31;
end $$;
create function public.set_youth_member(p_youth uuid,p_user uuid,p_member boolean,p_activist boolean,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare v_parish uuid; v public.youth_memberships;
begin
 select parish_id into v_parish from public.youth_groups where id=p_youth and not is_archived;
 if v_parish is null or not app_private.has_scope_permission('youth.members.manage',v_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_member is null or p_activist is null or not p_member and p_activist then raise exception 'invalid_membership' using errcode='22023'; end if;
 perform 1 from public.profiles where id=p_user for update;
 select * into v from public.youth_memberships where youth_id=p_youth and user_id=p_user for update;
 if (coalesce(v.is_activist,false) is distinct from p_activist) and not app_private.has_scope_permission('youth.active.manage',v_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if found and v.is_member=p_member and v.is_activist=p_activist then return; end if;
 if coalesce(v.revision,0) is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(p_youth,p_user,p_member,p_activist)
 on conflict(youth_id,user_id) do update set is_member=excluded.is_member,is_activist=excluded.is_activist,updated_at=now();
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'youth.member','youth_group',p_youth,v_parish,jsonb_build_object('user',p_user,'member',p_member,'active',p_activist));
end $$;
create function public.my_youth() returns setof public.youth_groups
language sql stable security definer set search_path='' as $$
 select g.* from public.youth_groups g where app_private.is_youth_member(g.id);
$$;
create function public.managed_youth_groups(p_parish uuid default null) returns setof public.youth_groups
language sql stable security definer set search_path='' as $$
 select g.* from public.youth_groups g where (p_parish is null or g.parish_id=p_parish)
 and (app_private.has_permission('youths.manage',g.parish_id) or app_private.has_scope_permission('youth.members.manage',g.parish_id,g.id)
 or app_private.has_scope_permission('messages.pin',g.parish_id,g.id) or app_private.has_scope_permission('events.edit',g.parish_id,g.id)) order by g.name,g.id;
$$;
create function public.save_youth_group(p_id uuid,p_parish uuid,p_name text,p_description text,p_archived boolean,p_revision bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.youth_groups;
begin
 if not app_private.has_permission('youths.manage',p_parish) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or length(btrim(coalesce(p_name,''))) not between 1 and 160 or p_description is null or length(p_description)>5000 or p_archived is null then raise exception 'invalid_youth' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,10));
 select * into v from public.youth_groups where id=p_id for update;
 if found then
 if v.parish_id<>p_parish then raise exception 'forbidden' using errcode='42501'; end if;
 if (v.name,v.description,v.is_archived) is not distinct from (btrim(p_name),btrim(p_description),p_archived) then return v.id; end if;
 if v.revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.youth_groups set name=btrim(p_name),description=btrim(p_description),is_archived=p_archived where id=p_id;
 else
 if p_revision<>0 then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.youth_groups(id,parish_id,name,description,is_archived,created_by) values(p_id,p_parish,btrim(p_name),btrim(p_description),p_archived,auth.uid());
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'youth.save','youth_group',p_id,p_parish);
 return p_id;
end $$;
create policy youth_groups_read on public.youth_groups for select to anon,authenticated using(
 not is_archived and app_private.parish_public(parish_id) or app_private.has_permission('youths.manage',parish_id) or app_private.is_youth_member(id));
create policy youth_members_read on public.youth_memberships for select to authenticated using(
 user_id=auth.uid() or exists(select 1 from public.youth_groups g where g.id=youth_id and app_private.has_scope_permission('youth.members.manage',g.parish_id,g.id)));

-- New RPCs and internal helpers do not inherit PostgreSQL's PUBLIC execute default.
do $privileges$
declare fn record;
begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname in ('app_private.is_super_admin','app_private.is_youth_member','app_private.has_scope_permission','public.my_scope_permissions','app_private.youth_membership_guard','app_private.can_assign_role','public.assign_scoped_role','public.permission_catalog','public.assignable_roles','public.scope_members','public.set_youth_member','public.my_youth','public.managed_youth_groups','public.save_youth_group') loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $privileges$;
grant execute on function app_private.is_super_admin(),app_private.is_youth_member(uuid),app_private.has_scope_permission(text,uuid,uuid) to anon,authenticated;
grant execute on function public.my_scope_permissions(uuid,uuid) to anon,authenticated;
grant execute on function public.assign_scoped_role(uuid,text,uuid,uuid,timestamptz),public.permission_catalog(),public.assignable_roles(uuid,uuid),
 public.scope_members(uuid,uuid,text,uuid),public.set_youth_member(uuid,uuid,boolean,boolean,bigint),public.my_youth(),public.managed_youth_groups(uuid),
 public.save_youth_group(uuid,uuid,text,text,boolean,bigint) to authenticated;

alter table public.chat_rooms add column youth_id uuid, add constraint room_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
alter table public.chat_rooms drop constraint chat_rooms_access_check;
alter table public.chat_rooms add constraint chat_rooms_access_check check(access in ('parish','restricted','active')),
 add constraint active_chat_has_youth check(access<>'active' or youth_id is not null);
alter table public.posts add column youth_id uuid,add constraint post_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
alter table public.events add column youth_id uuid,add column location_label text not null default '' check(length(location_label)<=500),
 add constraint event_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
create index rooms_youth on public.chat_rooms(youth_id,sort_order,id);
create index posts_youth on public.posts(youth_id,published_at desc,id desc);
create index events_youth on public.events(youth_id,starts_at,id);
alter table public.chat_messages add constraint message_room_identity unique(room_id,id);
create table public.chat_pins (
 room_id uuid primary key references public.chat_rooms on delete cascade,
 message_id uuid not null, pinned_by uuid not null references public.profiles,
 pinned_at timestamptz not null default now(), revision bigint not null default 1,
 foreign key(room_id,message_id) references public.chat_messages(room_id,id)
);
alter table public.chat_pins enable row level security;
revoke all on public.chat_pins from public,anon,authenticated;
grant select on public.chat_pins to authenticated;
create policy pins_read on public.chat_pins for select to authenticated using(app_private.can_read_room(room_id));
alter publication supabase_realtime add table public.chat_pins;

create or replace function app_private.can_read_room(p_room uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_rooms r where r.id=p_room and (
 app_private.has_scope_permission('chats.manage',r.parish_id,r.youth_id) or
 (app_private.has_scope_permission('chat.read',r.parish_id,r.youth_id) and
 (r.youth_id is null or app_private.is_youth_member(r.youth_id)) and
 (r.access='parish' or r.access='restricted' and exists(select 1 from public.chat_members m where m.room_id=r.id and m.user_id=auth.uid())
 or r.access='active' and (app_private.has_scope_permission('youth.active.manage',r.parish_id,r.youth_id)
 or exists(select 1 from public.youth_memberships m where m.youth_id=r.youth_id and m.user_id=auth.uid() and m.is_member and m.is_activist))))));
$$;
create function app_private.can_read_scope_content(p_parish uuid,p_youth uuid,p_visibility text) returns boolean
language sql stable security definer set search_path='' as $$
 select case when p_youth is null then app_private.can_read_content(p_parish,p_visibility) else
 exists(select 1 from public.youth_groups g where g.id=p_youth and not g.is_archived and g.parish_id=p_parish
 and ((p_visibility='public' and app_private.parish_public(p_parish)) or app_private.is_youth_member(p_youth))) end;
$$;
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(
 status='published' and published_at<=now() and app_private.can_read_scope_content(parish_id,youth_id,visibility)
 or app_private.has_scope_permission('posts.manage',parish_id,youth_id));
drop policy events_read on public.events;
create policy events_read on public.events for select to anon,authenticated using(
 status in ('published','cancelled') and app_private.can_read_scope_content(parish_id,youth_id,visibility)
 or app_private.has_scope_permission('events.manage',parish_id,youth_id) or app_private.has_scope_permission('events.edit',parish_id,youth_id));
-- Checked RPCs enforce event archive/delete permissions.
revoke insert,update,delete on public.posts,public.events from authenticated;
revoke insert(parish_id,author_id,title,body,visibility,status,published_at),update(title,body,visibility,status,published_at) on public.posts from authenticated;
revoke insert(parish_id,location_id,title,description,starts_at,ends_at,timezone,visibility,status,created_by),update(location_id,title,description,starts_at,ends_at,timezone,visibility,status) on public.events from authenticated;
drop policy posts_insert on public.posts; drop policy posts_update on public.posts;
create policy posts_insert on public.posts for insert to authenticated with check(author_id=auth.uid() and app_private.has_scope_permission('posts.manage',parish_id,youth_id));
create policy posts_update on public.posts for update to authenticated using(app_private.has_scope_permission('posts.manage',parish_id,youth_id)) with check(app_private.has_scope_permission('posts.manage',parish_id,youth_id));
drop policy events_insert on public.events; drop policy events_update on public.events;
create policy events_insert on public.events for insert to authenticated with check(created_by=auth.uid() and (app_private.has_scope_permission('events.create',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id)));
create policy events_update on public.events for update to authenticated using(app_private.has_scope_permission('events.edit',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id)) with check(app_private.has_scope_permission('events.edit',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id));

create or replace function public.send_message(p_room uuid,p_body text,p_nonce uuid) returns public.chat_messages
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms; m public.chat_messages;
begin
 if auth.uid() is null then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into r from public.chat_rooms where id=p_room for share;
 if not found or not app_private.can_read_room(p_room) or r.is_archived
 or not app_private.has_scope_permission(case when r.kind='channel' then 'channels.publish' else 'chat.send' end,r.parish_id,r.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_body is null or length(btrim(p_body)) not between 1 and 4000 or p_nonce is null then raise exception 'invalid_message' using errcode='22023'; end if;
 select * into m from public.chat_messages where author_id=auth.uid() and client_nonce=p_nonce;
 if found then
 if m.room_id<>p_room then raise exception 'nonce_conflict' using errcode='22023'; end if;
 return m;
 end if;
 if exists(select 1 from public.chat_messages where author_id=auth.uid() and created_at>clock_timestamp()-interval '1 second') then raise exception 'message_rate_limited' using errcode='P0001'; end if;
 insert into public.chat_messages(room_id,author_id,client_nonce,body) values(p_room,auth.uid(),p_nonce,btrim(p_body)) returning * into m;
 return m;
end $$;
create function public.chat_capabilities(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.chat_rooms;
begin
 select * into r from public.chat_rooms where id=p_room;
 if not found or not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 return jsonb_build_object('send',not r.is_archived and app_private.has_scope_permission(case when r.kind='channel' then 'channels.publish' else 'chat.send' end,r.parish_id,r.youth_id),
 'delete_own',app_private.has_scope_permission('messages.delete_own',r.parish_id,r.youth_id),
 'delete_any',app_private.has_scope_permission('messages.delete_any',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id),
 'pin',app_private.has_scope_permission('messages.pin',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id));
end $$;
create function public.delete_chat_message(p_message uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms; m public.chat_messages;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select r0.* into r from public.chat_rooms r0 join public.chat_messages m0 on m0.room_id=r0.id where m0.id=p_message for update of r0;
 if not found or not app_private.can_read_room(r.id) then raise exception 'forbidden' using errcode='42501'; end if;
 select * into m from public.chat_messages where id=p_message for update;
 if not(app_private.has_scope_permission('messages.delete_any',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id)
 or m.author_id=auth.uid() and app_private.has_scope_permission('messages.delete_own',r.parish_id,r.youth_id)) then raise exception 'forbidden' using errcode='42501'; end if;
 if m.deleted_at is not null then return; end if;
 delete from public.chat_pins where room_id=r.id and message_id=m.id;
 update public.chat_messages set body='Сообщение удалено',deleted_at=now() where id=m.id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'message.hide','chat_message',m.id,r.parish_id,jsonb_build_object('youth',r.youth_id,'own',m.author_id=auth.uid()));
end $$;
create or replace function public.hide_message(p_message uuid) returns void
language sql security definer set search_path='' as $$ select public.delete_chat_message(p_message,auth.uid()); $$;
create function public.set_chat_pin(p_room uuid,p_message uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select * into r from public.chat_rooms where id=p_room for update;
 if not found or not app_private.can_read_room(p_room) or not(app_private.has_scope_permission('messages.pin',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_message is null then delete from public.chat_pins where room_id=p_room;
 else
 perform 1 from public.chat_messages where id=p_message and room_id=p_room and deleted_at is null for share;
 if not found then raise exception 'message_unavailable' using errcode='22023'; end if;
 insert into public.chat_pins(room_id,message_id,pinned_by) values(p_room,p_message,auth.uid())
 on conflict(room_id) do update set message_id=excluded.message_id,pinned_by=excluded.pinned_by,pinned_at=now(),revision=chat_pins.revision+1;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),case when p_message is null then 'message.unpin' else 'message.pin' end,'chat_room',r.id,r.parish_id,jsonb_build_object('message',p_message,'youth',r.youth_id));
end $$;
create function public.chat_history(p_room uuid,p_before timestamptz default null,p_before_id uuid default null,p_anchor uuid default null)
returns table(id uuid,room_id uuid,author_id uuid,author_name text,body text,created_at timestamptz,deleted_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_anchor timestamptz;
begin
 if not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 if (p_before is null)<>(p_before_id is null) then raise exception 'invalid_cursor' using errcode='22023'; end if;
 if p_anchor is not null then
 select m.created_at into v_anchor from public.chat_messages m where m.id=p_anchor and m.room_id=p_room;
 if not found then raise exception 'message_unavailable' using errcode='22023'; end if;
 return query select m.id,m.room_id,m.author_id,p.display_name,m.body,m.created_at,m.deleted_at
 from public.chat_messages m join public.profiles p on p.id=m.author_id
 where m.room_id=p_room and (m.created_at,m.id)<=(v_anchor,p_anchor) order by m.created_at desc,m.id desc limit 50;
 else
 return query select m.id,m.room_id,m.author_id,p.display_name,m.body,m.created_at,m.deleted_at
 from public.chat_messages m join public.profiles p on p.id=m.author_id
 where m.room_id=p_room and (p_before is null or (m.created_at,m.id)<(p_before,p_before_id)) order by m.created_at desc,m.id desc limit 50;
 end if;
end $$;
create function public.current_chat_pin(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 return(select jsonb_build_object('message_id',m.id,'body',m.body,'author_name',p.display_name,'pinned_at',cp.pinned_at)
 from public.chat_pins cp join public.chat_messages m on m.id=cp.message_id join public.profiles p on p.id=m.author_id
 where cp.room_id=p_room and m.deleted_at is null);
end $$;
create function app_private.create_active_chat() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.chat_rooms(parish_id,youth_id,title,description,kind,access,icon_key,sort_order,created_by)
 values(new.parish_id,new.id,'Актив','Закрытый чат актива и руководителей','group','active','help',1000,new.created_by);
 return new;
end $$;
create trigger youth_active_chat after insert on public.youth_groups for each row execute function app_private.create_active_chat();

drop policy attendees_insert on public.event_attendees;
create policy attendees_insert on public.event_attendees for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.events e where e.id=event_id and e.status='published' and e.ends_at>now() and app_private.has_scope_permission('events.attend',e.parish_id,e.youth_id)));
drop policy attendees_read on public.event_attendees;
create policy attendees_read on public.event_attendees for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.events e where e.id=event_id and app_private.has_scope_permission('events.manage',e.parish_id,e.youth_id)));
create function public.scope_content(p_kind text,p_parish uuid,p_youth uuid default null,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_permission text; v_result jsonb;
begin
 v_permission=case p_kind when 'posts' then 'posts.manage' when 'events' then 'events.edit' when 'chats' then 'chats.manage' else null end;
 if v_permission is null or not(app_private.has_scope_permission(v_permission,p_parish,p_youth)
 or p_kind='events' and (app_private.has_scope_permission('events.manage',p_parish,p_youth) or app_private.has_scope_permission('events.create',p_parish,p_youth))
 or p_kind='chats' and app_private.has_scope_permission('chats.create',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='posts' then select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.posts where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) order by id limit 31)t;
 elsif p_kind='events' then select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.events where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) order by id limit 31)t;
 else select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.chat_rooms where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) and app_private.can_read_room(id) order by id limit 31)t; end if;
 return v_result;
end $$;
create function public.save_scope_content(p_kind text,p_id uuid,p_parish uuid,p_youth uuid,p_data jsonb,p_expected text,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_post public.posts; v_event public.events; v_room public.chat_rooms; v_found boolean; v_title text; v_body text; v_status text; v_visibility text;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or p_parish is null or p_data is null or jsonb_typeof(p_data)<>'object' or p_kind is null or p_kind not in ('posts','events','chats') then raise exception 'invalid_content' using errcode='22023'; end if;
 if p_youth is not null and not exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish) then raise exception 'invalid_scope' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,12));
 v_title=btrim(p_data->>'title'); v_body=coalesce(p_data->>'body',''); v_status=p_data->>'status'; v_visibility=p_data->>'visibility';
 if v_title is null or length(v_title) not between 1 and 200 then raise exception 'invalid_content' using errcode='22023'; end if;
 if p_kind='posts' then
 if not app_private.has_scope_permission('posts.manage',p_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(v_body)>30000 or v_status is null or v_status not in ('draft','published','archived') or v_visibility is null or v_visibility not in ('public','parish') then raise exception 'invalid_content' using errcode='22023'; end if;
 select * into v_post from public.posts where id=p_id for update; v_found=found;
 if v_found then
 if v_post.parish_id<>p_parish or v_post.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_post.author_id<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_post.title=v_title and v_post.body=v_body and v_post.status=v_status and v_post.visibility=v_visibility then return p_id; end if;
 if p_expected is null or v_post.updated_at is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.posts set title=v_title,body=v_body,status=v_status,visibility=v_visibility,published_at=case when v_status='published' then coalesce(published_at,now()) else published_at end where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.posts(id,parish_id,youth_id,author_id,title,body,status,visibility,published_at) values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,v_status,v_visibility,case when v_status='published' then now() else null end);
 end if;
 elsif p_kind='events' then
 select * into v_event from public.events where id=p_id for update; v_found=found;
 if not(app_private.has_scope_permission('events.manage',p_parish,p_youth) or app_private.has_scope_permission(case when v_found and p_expected is not null then 'events.edit' else 'events.create' end,p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(v_body)>10000 or v_status is null or v_status not in ('draft','published','cancelled','archived') or v_visibility is null or v_visibility not in ('public','parish')
 or p_data->>'starts_at' is null or p_data->>'ends_at' is null or (p_data->>'ends_at')::timestamptz<=(p_data->>'starts_at')::timestamptz
 or not isfinite((p_data->>'starts_at')::timestamptz) or not isfinite((p_data->>'ends_at')::timestamptz) or length(coalesce(p_data->>'location',''))>500 then raise exception 'invalid_content' using errcode='22023'; end if;
 if v_status='archived' and not(app_private.has_scope_permission('events.delete',p_parish,p_youth) or app_private.has_scope_permission('events.manage',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if v_found then
 if v_event.parish_id<>p_parish or v_event.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_event.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_event.title=v_title and v_event.description=v_body and v_event.status=v_status and v_event.visibility=v_visibility and v_event.starts_at=(p_data->>'starts_at')::timestamptz and v_event.ends_at=(p_data->>'ends_at')::timestamptz and v_event.location_label=coalesce(p_data->>'location','') then return p_id; end if;
 if p_expected is null or v_event.updated_at is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.events set title=v_title,description=v_body,status=v_status,visibility=v_visibility,starts_at=(p_data->>'starts_at')::timestamptz,ends_at=(p_data->>'ends_at')::timestamptz,location_label=coalesce(p_data->>'location','') where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.events(id,parish_id,youth_id,created_by,title,description,status,visibility,starts_at,ends_at,location_label)
 values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,v_status,v_visibility,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,coalesce(p_data->>'location',''));
 end if;
 else
 select * into v_room from public.chat_rooms where id=p_id for update; v_found=found;
 if not app_private.has_scope_permission(case when v_found and p_expected is not null then 'chats.manage' else 'chats.create' end,p_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(v_title)>100 or length(v_body)>300 or coalesce(p_data->>'kind','') not in ('group','channel') or coalesce(p_data->>'access','') not in ('parish','active')
 or p_data->>'access'='active' and p_youth is null or p_data->>'sort_order' is null or (p_data->>'sort_order')::integer not between 0 and 10000 or p_data->>'is_archived' is null then raise exception 'invalid_content' using errcode='22023'; end if;
 if v_found then
 if v_room.parish_id<>p_parish or v_room.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_room.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_room.title=v_title and v_room.description=v_body and v_room.kind=p_data->>'kind' and (v_room.access='restricted' or v_room.access=p_data->>'access') and v_room.sort_order=(p_data->>'sort_order')::integer and v_room.is_archived=(p_data->>'is_archived')::boolean then return p_id; end if;
 if p_expected is null or v_room.revision is distinct from p_expected::bigint then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.chat_rooms set title=v_title,description=v_body,kind=p_data->>'kind',access=case when access='restricted' then access else p_data->>'access' end,
 sort_order=(p_data->>'sort_order')::integer,is_archived=(p_data->>'is_archived')::boolean where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.chat_rooms(id,parish_id,youth_id,created_by,title,description,kind,access,sort_order,is_archived)
 values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,p_data->>'kind',p_data->>'access',(p_data->>'sort_order')::integer,(p_data->>'is_archived')::boolean);
 end if;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'content.save',p_kind,p_id,p_parish,jsonb_build_object('youth',p_youth));
 return p_id;
end $$;
create function public.delete_scope_content(p_kind text,p_id uuid,p_parish uuid,p_youth uuid,p_expected text,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_time timestamptz;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or p_kind is null or p_kind not in ('posts','events')
 or not(app_private.has_scope_permission(case when p_kind='posts' then 'posts.manage' else 'events.delete' end,p_parish,p_youth)
 or p_kind='events' and app_private.has_scope_permission('events.manage',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='posts' then
 select updated_at into v_time from public.posts where id=p_id and parish_id=p_parish and youth_id is not distinct from p_youth for update;
 else select updated_at into v_time from public.events where id=p_id and parish_id=p_parish and youth_id is not distinct from p_youth for update; end if;
 if not found then return; end if;
 if p_expected is null or v_time is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 if p_kind='posts' then delete from public.posts where id=p_id; else delete from public.events where id=p_id; end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata) values(auth.uid(),'content.delete',p_kind,p_id,p_parish,jsonb_build_object('youth',p_youth));
end $$;

create table public.app_configuration (
 id boolean primary key default true check(id), app_name text not null default 'Мой приход' check(length(btrim(app_name)) between 1 and 80),
 welcome_text text not null default 'Вера объединяет людей' check(length(welcome_text)<=500),
 support_email text not null default '' check(length(support_email)<=254), revision bigint not null default 1
);
insert into public.app_configuration(id) values(true);
alter table public.app_configuration enable row level security;
revoke all on public.app_configuration from public,anon,authenticated;
grant select on public.app_configuration to anon,authenticated;
create policy app_configuration_read on public.app_configuration for select to anon,authenticated using(true);
create trigger app_configuration_revision before update on public.app_configuration for each row execute function app_private.chat_revision();
create function public.save_app_configuration(p_name text,p_welcome text,p_email text,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare v public.app_configuration;
begin
 if not app_private.has_permission('settings.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 if length(btrim(coalesce(p_name,''))) not between 1 and 80 or p_welcome is null or length(p_welcome)>500 or p_email is null or length(p_email)>254
 or p_email<>'' and p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid_settings' using errcode='22023'; end if;
 select * into v from public.app_configuration for update;
 if v.revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.app_configuration set app_name=btrim(p_name),welcome_text=btrim(p_welcome),support_email=btrim(p_email);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'settings.save','app_configuration',null);
end $$;

-- Youth-only staff do not gain an administration entry for the whole parish.
create or replace function public.admin_parishes(p_after uuid default null,p_only uuid default null,p_limit integer default 31)
returns table(id uuid,city_name text,name text,description text,address text,join_mode text,is_published boolean,updated_at timestamptz,permissions text[])
language sql stable security definer set search_path='' as $$
 select p.id,c.name,p.name,p.description,p.address,p.join_mode,p.is_published,p.updated_at,
 array(select k from unnest(array['parish.manage','posts.manage','memberships.manage','chats.manage','chats.create','events.manage','events.create','events.edit','events.delete','roles.assign','youths.manage']) k where app_private.has_permission(k,p.id))
 from public.parishes p join public.cities c on c.id=p.city_id
 where auth.uid() is not null and (p_after is null or p.id>p_after) and (p_only is null or p.id=p_only)
 and (app_private.has_permission('parishes.manage') or exists(select 1 from unnest(array['parish.manage','posts.manage','memberships.manage','chats.manage','chats.create','events.manage','events.create','events.edit','roles.assign','youths.manage']) k where app_private.has_permission(k,p.id)))
 order by p.id limit greatest(1,least(coalesce(p_limit,31),101));
$$;
-- New RPCs and internal helpers do not inherit PostgreSQL's PUBLIC execute default.
do $privileges$
declare fn record;
begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname in ('app_private.can_read_scope_content','public.chat_capabilities','public.delete_chat_message','public.set_chat_pin','public.chat_history','public.current_chat_pin','app_private.create_active_chat','public.scope_content','public.save_scope_content','public.delete_scope_content','public.save_app_configuration') loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $privileges$;
grant execute on function app_private.can_read_scope_content(uuid,uuid,text) to anon,authenticated;
grant execute on function public.chat_capabilities(uuid),public.delete_chat_message(uuid,uuid),public.set_chat_pin(uuid,uuid,uuid),public.chat_history(uuid,timestamptz,uuid,uuid),public.current_chat_pin(uuid),
 public.scope_content(text,uuid,uuid,uuid),public.save_scope_content(text,uuid,uuid,uuid,jsonb,text,uuid),public.delete_scope_content(text,uuid,uuid,uuid,text,uuid),public.save_app_configuration(text,text,text,bigint) to authenticated;
create or replace function public.admin_save_chat(p_id uuid,p_parish uuid,p_create boolean,p_title text,p_description text,
 p_kind text,p_icon text,p_sort integer,p_archived boolean,p_expected_revision bigint,p_expected_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.chat_rooms; v_actor uuid:=auth.uid();
begin
 if v_actor is null or p_expected_user is distinct from v_actor or not app_private.has_permission('chats.manage',p_parish) or (p_create and not app_private.has_permission('chats.create',p_parish)) then
  raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or p_parish is null or p_create is null or p_archived is null
 or length(trim(coalesce(p_title,''))) not between 1 and 100 or length(coalesce(p_description,''))>300
 or p_kind is null or p_kind not in ('group','channel') or p_icon is null
 or p_icon not in ('auto','chat','announcements','news','book','games','location','rules','help','sport','craft','music','prayer','family')
 or p_sort is null or p_sort not between 0 and 10000 then raise exception 'invalid_chat' using errcode='22023'; end if;
 if not exists(select 1 from public.parishes where id=p_parish) then raise exception 'parish_unavailable' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into v_room from public.chat_rooms where id=p_id for update;
 if found then
  if v_room.parish_id<>p_parish then raise exception 'forbidden' using errcode='42501'; end if;
  if p_create and v_room.created_by is distinct from v_actor then raise exception 'edit_conflict' using errcode='40001'; end if;
  if (v_room.title,v_room.description,v_room.kind,v_room.icon_key,v_room.sort_order,v_room.is_archived)
    is not distinct from (trim(p_title),trim(coalesce(p_description,'')),p_kind,p_icon,p_sort,p_archived) then return to_jsonb(v_room); end if;
  if p_create or p_expected_revision is distinct from v_room.revision then raise exception 'edit_conflict' using errcode='40001'; end if;
  -- Keep parish, original author and restricted-room access immutable here.
  update public.chat_rooms set title=trim(p_title),description=trim(coalesce(p_description,'')),kind=p_kind,
    icon_key=p_icon,sort_order=p_sort,is_archived=p_archived where id=p_id returning * into v_room;
 else
  if not p_create then raise exception 'chat_unavailable' using errcode='22023'; end if;
  insert into public.chat_rooms(id,parish_id,title,description,kind,icon_key,sort_order,is_archived,access,created_by)
   values(p_id,p_parish,trim(p_title),trim(coalesce(p_description,'')),p_kind,p_icon,p_sort,p_archived,'parish',v_actor)
   returning * into v_room;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(v_actor,case when p_create then 'chat.create' else 'chat.update' end,'chat_room',p_id,p_parish,
 jsonb_build_object('revision',v_room.revision,'archived',p_archived));
 return to_jsonb(v_room);
end $$;
create or replace function app_private.youth_membership_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.is_member and not exists(select 1 from public.memberships m join public.youth_groups g on g.parish_id=m.parish_id where g.id=new.youth_id and m.user_id=new.user_id and m.status='active' and not g.is_archived) then raise exception 'active_membership_required' using errcode='23514'; end if;
 if tg_op='UPDATE' and old.is_member and not new.is_member then
 delete from app_private.role_assignments where user_id=new.user_id and youth_id=new.youth_id;
 delete from public.chat_members where user_id=new.user_id and room_id in(select id from public.chat_rooms where youth_id=new.youth_id);
 end if; return new;
end $$;

alter table app_private.profile_private add column phone text not null default '' check(length(phone)<=32);
alter table public.profiles add column avatar_path text;
-- Avatar references are changed only through the guarded RPC.
revoke update on public.profiles from authenticated;
grant update(display_name,directory_visibility) on public.profiles to authenticated;
create function public.my_profile_v2() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
 select to_jsonb(p) into v from public.my_profile() p;
 return v || (select jsonb_build_object('phone',d.phone,'avatar_path',p.avatar_path,'email',coalesce(to_jsonb(u)->>'email',''),
 'parish_name',(select pa.name from public.memberships m join public.parishes pa on pa.id=m.parish_id where m.user_id=p.id and m.status='active'),
 'youth_name',(select g.name from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id where m.user_id=p.id and m.is_member and not g.is_archived))
 from public.profiles p join app_private.profile_private d on d.user_id=p.id join auth.users u on u.id=p.id where p.id=auth.uid());
end $$;
create function public.save_my_profile_v2(p_display_name text,p_directory_visibility text,p_given_name text,p_family_name text,p_birth_date date,p_profile_revision bigint,p_private_revision bigint,p_expected_user_id uuid,p_phone text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_public public.profiles; v_private app_private.profile_private;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user_id then raise exception 'forbidden' using errcode='42501'; end if;
 if p_phone is null or length(btrim(p_phone))>32 or p_phone<>'' and p_phone !~ '^[+0-9 ()-]{5,32}$' then raise exception 'invalid_phone' using errcode='22023'; end if;
 select * into v_public from public.profiles where id=auth.uid() for update;
 select * into v_private from app_private.profile_private where user_id=auth.uid() for update;
 if v_private.phone is distinct from btrim(p_phone) and (v_public.revision is distinct from p_profile_revision or v_private.revision is distinct from p_private_revision) then raise exception 'profile_edit_conflict' using errcode='40001'; end if;
 perform public.save_my_profile(p_display_name,p_directory_visibility,p_given_name,p_family_name,p_birth_date,p_profile_revision,p_private_revision,p_expected_user_id);
 if v_private.phone is distinct from btrim(p_phone) then update app_private.profile_private set phone=btrim(p_phone) where user_id=auth.uid(); end if;
 return public.my_profile_v2();
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('profile-avatars','profile-avatars',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;
create policy profile_avatar_select on storage.objects for select to authenticated using(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text);
create policy profile_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text);
create policy profile_avatar_delete on storage.objects for delete to authenticated using(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text
 and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.avatar_path=name));
create function public.set_profile_avatar(p_path text,p_revision bigint,p_expected_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v public.profiles;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select * into v from public.profiles where id=auth.uid() for update;
 if p_path is not null and (split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='profile-avatars' and name=p_path)) then raise exception 'invalid_avatar' using errcode='22023'; end if;
 if v.avatar_path is not distinct from p_path then return public.my_profile_v2(); end if;
 if v.revision is distinct from p_revision then raise exception 'profile_edit_conflict' using errcode='40001'; end if;
 update public.profiles set avatar_path=p_path where id=auth.uid();
 return public.my_profile_v2();
end $$;
-- New RPCs and internal helpers do not inherit PostgreSQL's PUBLIC execute default.
do $privileges$
declare fn record;
begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname in ('public.set_profile_avatar') loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $privileges$;
grant execute on function public.my_profile_v2(),public.save_my_profile_v2(text,text,text,text,date,bigint,bigint,uuid,text),public.set_profile_avatar(text,bigint,uuid) to authenticated;

$migration_body$;
  insert into app_private.installed_features(feature,checksum) values('roles_profile_20260912','5be755d7848cf987b9618113169624a94b48111c0c92378cd75dbfa84b15efc2');
 end if;
end $install$;
commit;
