begin;
-- Read the existing catalog. This update creates no roles and changes no role titles.
create or replace function app_private.person_global_role(p_user uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when app_private.is_restricted_guest(p_user)
 then (select key from app_private.roles where baseline='guest')
 else coalesce((select r.key from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and r.scope='global' and a.parish_id is null and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now()) order by (r.key='super_admin') desc,a.created_at desc,a.id limit 1),
 (select key from app_private.roles where baseline='authenticated')) end;
$$;
create or replace function app_private.person_club_role(p_user uuid,p_club uuid) returns text
language sql stable security definer set search_path='' as $$
 select case when not exists(select 1 from public.youth_memberships m where m.user_id=p_user and m.youth_id=p_club and m.is_member) then null
 else coalesce((select r.key from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and a.youth_id=p_club and r.scope='youth' and (a.expires_at is null or a.expires_at>now())
 order by (r.key='youth_leader') desc,a.created_at desc,a.id limit 1),
 (select key from app_private.roles where baseline='authenticated')) end;
$$;
create function app_private.role_catalog_revision() returns text
language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object(
 'roles',(select jsonb_agg(to_jsonb(r) order by r.id) from app_private.roles r),
 'permissions',(select jsonb_agg(to_jsonb(p) order by p.role_id,p.permission_key) from app_private.role_permissions p),
 'clubs',(select jsonb_agg(jsonb_build_array(g.id,g.revision) order by g.id) from public.youth_groups g)
 )::text);
$$;
create function app_private.person_roles_revision_v2(p_user uuid) returns text
language sql stable security definer set search_path='' as $$
 select md5(app_private.person_roles_revision(p_user)||app_private.role_catalog_revision());
$$;
create function app_private.can_replace_club_role(p_user uuid,p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select app_private.can_manage_person(p_user) and exists(select 1 from public.youth_groups g
 where g.id=p_club and not g.is_archived and app_private.can_manage_club_roles(g.id)
 and not exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and a.youth_id=g.id and not app_private.can_assign_role(r.id,g.parish_id,g.id)));
$$;
create function app_private.role_manager_options(p_user uuid,p_club uuid default null) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('key',r.key,'title',r.title,'baseline',r.baseline,
 'assignable',case when p_club is null then app_private.is_super_admin()
 else app_private.can_replace_club_role(p_user,p_club) and (r.baseline='authenticated'
 or app_private.can_assign_role(r.id,(select parish_id from public.youth_groups where id=p_club),p_club)) end)
 order by (r.key='super_admin') desc,(r.baseline is not null),r.title,r.key),'[]'::jsonb)
 from app_private.roles r where (p_club is null and r.scope='global')
 -- Membership is the existing authenticated baseline, not a new role or a global grant.
 or (p_club is not null and (r.scope='youth' or r.baseline='authenticated'));
$$;
create function public.role_manager_person_v2(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
 v:=public.role_manager_person(p_user);
 if v is null then raise exception 'profile_unavailable' using errcode='22023'; end if;
 return v||jsonb_build_object('revision',app_private.person_roles_revision_v2(p_user),
 'global_roles',app_private.role_manager_options(p_user),
 'global_multiple_roles',(select count(*)>1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=p_user and r.scope='global' and a.parish_id is null and a.youth_id is null and (a.expires_at is null or a.expires_at>now())),
 'clubs',(select coalesce(jsonb_agg(c||jsonb_build_object(
 'roles',app_private.role_manager_options(p_user,(c->>'id')::uuid),
 'can_edit',app_private.can_replace_club_role(p_user,(c->>'id')::uuid),
 'multiple_roles',(c->>'can_edit')::boolean and (select count(*)>1 from app_private.role_assignments a
 where a.user_id=p_user and a.youth_id=(c->>'id')::uuid and (a.expires_at is null or a.expires_at>now()))
 ) order by c->>'name',c->>'id'),'[]'::jsonb) from jsonb_array_elements(v->'clubs') c));
end $$;
create or replace function public.role_manager_people(p_search text default '',p_after uuid default null) returns table(
 user_id uuid,display_name text,avatar_path text,summary text)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not (app_private.is_super_admin() or exists(select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id))) then
 raise exception 'forbidden' using errcode='42501'; end if;
 return query select p.id,p.display_name,p.avatar_path,
 concat_ws(' · ',(select r.title from app_private.roles r where r.key=app_private.person_global_role(p.id)),
 (select string_agg(r.title||' — '||g.name,'; ' order by g.name,g.id)
 from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id
 join app_private.roles r on r.key=app_private.person_club_role(p.id,g.id)
 where m.user_id=p.id and m.is_member and (app_private.is_super_admin() or app_private.can_manage_club_roles(g.id))))
 from public.profiles p join auth.users u on u.id=p.id where app_private.can_manage_person(p.id) and (p_after is null or p.id>p_after)
 and position(lower(btrim(coalesce(p_search,''))) in lower(p.display_name))>0
 order by p.id limit 31;
end $$;
create function public.save_person_roles_v2(p_user uuid,p_global_role text,p_clubs jsonb,p_revision text,p_request uuid,p_expected_actor uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_actor uuid:=auth.uid(); v_global boolean; v_hash text; v_receipt app_private.role_change_receipts;
 v_item jsonb; v_club uuid; v_group public.youth_groups; v_role text; v_role_id uuid; v_catalog app_private.roles;
begin
 if v_actor is null or v_actor is distinct from p_expected_actor then raise exception 'forbidden' using errcode='42501'; end if;
 if p_user is null or p_request is null or p_revision is null or p_clubs is null or jsonb_typeof(p_clubs)<>'array'
 or jsonb_array_length(p_clubs)>100 then
 raise exception 'invalid_role' using errcode='22023'; end if;
 v_hash:=md5(jsonb_build_object('api',2,'user',p_user,'global',p_global_role,'clubs',p_clubs,'revision',p_revision)::text);
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
 if app_private.person_roles_revision_v2(p_user) is distinct from p_revision then raise exception 'role_edit_conflict' using errcode='40001'; end if;
 v_global:=app_private.is_super_admin();
 if p_global_role is not null and not v_global then raise exception 'forbidden' using errcode='42501'; end if;
 if p_global_role is not null then
 select * into v_catalog from app_private.roles where key=p_global_role and scope='global';
 if not found then raise exception 'invalid_role' using errcode='22023'; end if;
 end if;
 if p_global_role is not null and p_global_role<>'super_admin' and exists(select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id where a.user_id=p_user and r.key='super_admin' and a.parish_id is null and a.youth_id is null) and not exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id<>p_user and r.key='super_admin' and a.parish_id is null and a.youth_id is null
 and (a.expires_at is null or a.expires_at>now()) and not app_private.is_restricted_guest(a.user_id)) then
 raise exception 'last_super_admin' using errcode='23514'; end if;
 if exists(select 1 from jsonb_array_elements(p_clubs) x group by x->>'id' having count(*)>1) then raise exception 'invalid_role' using errcode='22023'; end if;
 -- Validate the entire patch using the actor's existing permissions first.
 for v_item in select * from jsonb_array_elements(p_clubs) loop
 begin v_club:=(v_item->>'id')::uuid; exception when invalid_text_representation then raise exception 'invalid_role' using errcode='22023'; end;
 v_role:=v_item->>'role';
 select * into v_catalog from app_private.roles where key=v_role and (scope='youth' or baseline='authenticated');
 if v_club is null or not found then raise exception 'invalid_role' using errcode='22023'; end if;
 select * into v_group from public.youth_groups where id=v_club for share;
 if not found or v_group.is_archived then raise exception 'club_unavailable' using errcode='22023'; end if;
 if not app_private.can_replace_club_role(p_user,v_club) or (v_catalog.baseline is distinct from 'authenticated'
 and not app_private.can_assign_role(v_catalog.id,v_group.parish_id,v_club)) then raise exception 'forbidden' using errcode='42501'; end if;
 end loop;
 for v_item in select * from jsonb_array_elements(p_clubs) loop
 v_club:=(v_item->>'id')::uuid;v_role:=v_item->>'role';
 select * into strict v_group from public.youth_groups where id=v_club;
 insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(v_club,p_user,true,false)
 on conflict(youth_id,user_id) do update set is_member=true,updated_at=now();
 -- Only this selected club changes. Active status and other clubs survive.
 delete from app_private.role_assignments where user_id=p_user and youth_id=v_club;
 if not exists(select 1 from app_private.roles where key=v_role and baseline='authenticated') then
 select id into strict v_role_id from app_private.roles where key=v_role;
 insert into app_private.role_assignments(user_id,role_id,parish_id,youth_id,granted_by)
 values(p_user,v_role_id,v_group.parish_id,v_club,v_actor);
 end if;
 end loop;
 if p_global_role is not null then
 delete from app_private.role_assignments where user_id=p_user and parish_id is null and youth_id is null;
 insert into app_private.account_access(user_id,guest_only,changed_by) values(p_user,exists(select 1 from app_private.roles where key=p_global_role and baseline='guest'),v_actor)
 on conflict(user_id) do update set guest_only=excluded.guest_only,changed_by=excluded.changed_by,updated_at=now();
 if exists(select 1 from app_private.roles where key=p_global_role and baseline is null) then
 select id into strict v_role_id from app_private.roles where key=p_global_role;
 insert into app_private.role_assignments(user_id,role_id,granted_by) values(p_user,v_role_id,v_actor);
 end if;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,metadata)
 values(v_actor,'roles.save','profile',p_user,jsonb_build_object('global',p_global_role,'clubs',p_clubs));
 insert into app_private.role_change_receipts(actor_id,request_id,user_id,payload_hash) values(v_actor,p_request,p_user,v_hash);
 return jsonb_build_object('saved',true);
end $$;

revoke all on function app_private.role_catalog_revision(),app_private.person_roles_revision_v2(uuid),
 app_private.can_replace_club_role(uuid,uuid),app_private.role_manager_options(uuid,uuid),
 public.role_manager_person_v2(uuid),public.save_person_roles_v2(uuid,text,jsonb,text,uuid,uuid) from public,anon,authenticated;
grant execute on function public.role_manager_person_v2(uuid),public.save_person_roles_v2(uuid,text,jsonb,text,uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
commit;
