begin;

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
commit;
