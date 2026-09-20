begin;
-- Club administrator: a youth-scoped role, never a global or parish grant.
-- Existing assignments are not migrated or removed.
do $catalog$
begin
 if exists(select 1 from app_private.roles where key='youth_admin') then
  raise exception 'Role key youth_admin already exists; review its scope and permissions before installing this update' using errcode='23505';
 end if;
end $catalog$;
insert into app_private.roles(key,title,scope) values('youth_admin','Администратор','youth');
-- The club administrator has the club leader's operational rights. The
-- assignment hierarchy below additionally permits appointing/removing leaders.
insert into app_private.role_permissions(role_id,permission_key)
 select r.id,p.key from app_private.roles r cross join app_private.permissions p
 where r.key='youth_admin' and p.key in (
 'parish.read','chat.read','chat.send','messages.delete_own','messages.delete_any',
 'messages.pin','chats.moderate','chats.manage','chats.create','channels.publish',
 'events.create','events.edit','events.delete','events.manage','posts.manage',
 'youth.members.manage','youth.roles.manage','youth.active.manage','youth.requests.review');

create function app_private.is_club_admin(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select app_private.is_youth_member(p_club) and exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 join public.youth_groups g on g.id=a.youth_id and g.parish_id=a.parish_id
 where a.user_id=auth.uid() and g.id=p_club and r.key='youth_admin' and r.scope='youth'
 and (a.expires_at is null or a.expires_at>now()));
$$;

create or replace function app_private.can_assign_role(p_role uuid,p_parish uuid,p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.roles r where r.id=p_role and r.baseline is null
 and ((r.scope='global' and p_parish is null and p_youth is null)
 or (r.scope='parish' and p_parish is not null and p_youth is null)
 or (r.scope='youth' and p_youth is not null and exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish)))
 and (app_private.has_permission('roles.manage') or (
 r.scope<>'global' and (app_private.has_permission('roles.assign',p_parish)
 or r.scope='youth' and r.key<>'youth_admin'
 and (r.key<>'youth_leader' or app_private.is_club_admin(p_youth)) and app_private.has_scope_permission('youth.roles.manage',p_parish,p_youth))
 and not exists(select 1 from app_private.role_permissions rp where rp.role_id=r.id
 and not app_private.has_scope_permission(rp.permission_key,p_parish,p_youth)))));
$$;

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
 if v.baseline is not null or v.key in ('super_admin','parish_admin','youth_leader','youth_moderator','youth_admin') or v.scope<>p_scope then raise exception 'protected_role' using errcode='42501'; end if;
 v_id=v.id; update app_private.roles set title=btrim(p_title) where id=v_id;
 delete from app_private.role_permissions where role_id=v_id;
 else insert into app_private.roles(key,title,scope) values(p_key,btrim(p_title),p_scope) returning id into v_id; end if;
 insert into app_private.role_permissions select distinct v_id,x from unnest(p_permissions) x;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'role.define','role',v_id,jsonb_build_object('key',p_key));
 return v_id;
end $$;

create or replace function public.set_youth_member(p_youth uuid,p_user uuid,p_member boolean,p_activist boolean,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare v_parish uuid; v public.youth_memberships;
begin
 perform pg_advisory_xact_lock(120010);
 select parish_id into v_parish from public.youth_groups where id=p_youth and not is_archived;
 if v_parish is null or not app_private.has_scope_permission('youth.members.manage',v_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_member is null or p_activist is null or not p_member and p_activist then raise exception 'invalid_membership' using errcode='22023'; end if;
 -- Removing a member also revokes club assignments. Enforce the same hierarchy
 -- as role editing so a leader cannot remove an administrator through this RPC.
 if not p_member and exists(select 1 from app_private.role_assignments a
 where a.user_id=p_user and a.youth_id=p_youth
 and not app_private.can_assign_role(a.role_id,v_parish,p_youth)) then
 raise exception 'forbidden' using errcode='42501'; end if;
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

revoke all on function app_private.is_club_admin(uuid) from public,anon,authenticated;
-- CREATE OR REPLACE retains the existing RPC grants; only the internal helper
-- is new. Clients continue to use the existing dynamic role catalog endpoints.
notify pgrst, 'reload schema';
commit;
