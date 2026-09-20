begin;
select pg_advisory_xact_lock(120010);
-- Link the notice to a person. Private fields are read through a checked RPC,
-- never copied into notifications or push payloads.
alter table public.notifications add column subject_user_id uuid references public.profiles(id) on delete cascade;
create unique index notification_review_person_once on public.notifications(user_id,kind,subject_user_id)
 where kind='review_routing' and subject_user_id is not null;
update public.notifications n set subject_user_id=r.user_id
 from app_private.youth_join_requests r where n.youth_request_id=r.id and n.kind='youth_request';

create or replace function app_private.notify_youth_request(p_request uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.youth_join_requests; v_name text; v_club text;
begin
 select * into v from app_private.youth_join_requests where id=p_request and status='pending';
 if not found or not exists(select 1 from auth.users where id=v.user_id and email_confirmed_at is not null) then return; end if;
 select display_name into v_name from public.profiles where id=v.user_id;
 select name into v_club from public.youth_groups where id=v.youth_id;
 insert into public.notifications(user_id,kind,title,body,target_path,youth_request_id,subject_user_id)
 select distinct a.user_id,'youth_request','Новая заявка',v_name||' · '||v_club,
 '/youth-requests/'||v.youth_id::text||'?request='||v.id::text,v.id,v.user_id
 from app_private.role_assignments a where app_private.can_review_youth_request(a.user_id,v.parish_id,v.youth_id)
 on conflict(user_id,kind,youth_request_id) where youth_request_id is not null do nothing;
update public.notifications set kind='review_legacy',read_at=coalesce(read_at,now())
 where kind='review_routing' and subject_user_id=v.user_id;
end $$;
create or replace function app_private.route_review(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.account_access; v_club uuid; v_parish uuid; v_request uuid;
begin
 select * into v from app_private.account_access where user_id=p_user for update;
 if not found or v.review_status is distinct from 'pending' then return; end if;
 if v.review_request_id is not null then perform app_private.notify_youth_request(v.review_request_id); return; end if;
 v_club:=coalesce(v.review_youth_id,app_private.default_intake_club());
 select g.parish_id into v_parish from public.youth_groups g join public.parishes p on p.id=g.parish_id where g.id=v_club and not g.is_archived and p.is_published;
 if v_parish is null then
  -- Keep a distinct, attributable notification for every confirmed person.
  insert into public.notifications(user_id,kind,title,body,target_path,subject_user_id)
  select distinct a.user_id,'review_routing','Новый пользователь',
  coalesce((select display_name from public.profiles where id=p_user),'Новый пользователь')||' · Ожидание проверки',
  '/admin/youth-clubs',p_user
  from app_private.role_assignments a join app_private.roles r on r.id=a.role_id and r.key='super_admin'
  where a.parish_id is null and a.youth_id is null and (a.expires_at is null or a.expires_at>now())
  and not app_private.is_restricted_guest(a.user_id)
  on conflict(user_id,kind,subject_user_id) where kind='review_routing' and subject_user_id is not null do nothing;
  return;
 end if;
 insert into app_private.youth_join_requests(receipt_key,user_id,youth_id,parish_id)
 values(gen_random_uuid(),p_user,v_club,v_parish) returning id into v_request;
 update app_private.account_access set review_youth_id=v_club,review_request_id=v_request,updated_at=now() where user_id=p_user;
end $$;

-- Club managers can open the existing role editor for their confirmed applicants.
-- Membership/role writes and the pending-review guard remain unchanged.
create or replace function app_private.can_manage_person(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (app_private.is_super_admin() or exists(
 select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id) and (
 exists(select 1 from public.youth_memberships m where m.user_id=p_user and m.youth_id=g.id and m.is_member)
 or exists(select 1 from public.memberships m where m.user_id=p_user and m.parish_id=g.parish_id and m.status='active')
 or exists(select 1 from app_private.youth_join_requests r join auth.users u on u.id=r.user_id
 where r.user_id=p_user and r.youth_id=g.id and r.status='pending' and u.email_confirmed_at is not null))));
$$;

create function public.notification_applicant(p_notification uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare n public.notifications; r app_private.youth_join_requests; v_user uuid; v jsonb;
begin
 if auth.uid() is null then raise exception 'forbidden' using errcode='42501'; end if;
 select * into n from public.notifications where id=p_notification and user_id=auth.uid()
 and kind in ('youth_request','review_routing');
 if not found or app_private.is_restricted_guest(auth.uid()) then return null; end if;
 if n.youth_request_id is not null then
  select * into r from app_private.youth_join_requests where id=n.youth_request_id;
  if not found then return null; end if;
  v_user:=r.user_id;
  if n.subject_user_id is not null and n.subject_user_id<>v_user then return null; end if;
  if not app_private.can_review_youth_request(auth.uid(),r.parish_id,r.youth_id) then return null; end if;
 else
  if n.kind<>'review_routing' or not app_private.is_super_admin() then return null; end if;
  v_user:=n.subject_user_id;
 end if;
 if v_user is null then return null; end if;
 select jsonb_build_object('notification_id',n.id,'user_id',p.id,'display_name',p.display_name,
 'given_name',coalesce(d.given_name,''),'family_name',coalesce(d.family_name,''),
 'birth_date',d.birth_date,'phone',coalesce(d.phone,''),'email',coalesce(u.email,''),
 'registered_at',coalesce(to_jsonb(u)->>'created_at',to_jsonb(p)->>'created_at'),
 'review_status',a.review_status,'youth_id',r.youth_id,
 'youth_name',(select g.name from public.youth_groups g where g.id=r.youth_id),
 'request_id',r.id,'request_status',r.status,
 'can_manage_roles',app_private.can_manage_person(p.id)) into v
 from public.profiles p join auth.users u on u.id=p.id
 left join app_private.profile_private d on d.user_id=p.id
 left join app_private.account_access a on a.user_id=p.id
 where p.id=v_user and u.email_confirmed_at is not null;
 return v;
end $$;
revoke all on function public.notification_applicant(uuid) from public,anon,authenticated;
grant execute on function public.notification_applicant(uuid) to authenticated;

-- Old generic notices cannot be mapped to a person reliably. Keep the history,
-- retire those placeholders and regenerate exact notices from existing requests.
update public.notifications set kind='review_legacy',read_at=coalesce(read_at,now())
 where kind in ('youth_request','review_routing') and subject_user_id is null and youth_request_id is null;
do $backfill$
declare x record;
begin
 for x in select id from app_private.youth_join_requests where status='pending' order by created_at,id loop
  perform app_private.notify_youth_request(x.id);
 end loop;
 for x in select a.user_id from app_private.account_access a join auth.users u on u.id=a.user_id
 where a.review_status='pending' and a.review_request_id is null and u.email_confirmed_at is not null order by a.user_id loop
  perform app_private.route_review(x.user_id);
 end loop;
end $backfill$;
create or replace function public.save_person_roles_v2(p_user uuid,p_global_role text,p_clubs jsonb,p_revision text,p_request uuid,p_expected_actor uuid) returns jsonb
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
 if exists(select 1 from app_private.account_access where user_id=p_user and review_status in ('pending','awaiting_email'))
 and (jsonb_array_length(p_clubs)>0 or (p_global_role is not null and p_global_role<>'guest')) then
 raise exception 'review_required' using errcode='22023'; end if;
 v_global:=app_private.is_super_admin();
 if p_global_role is not null and not v_global then raise exception 'forbidden' using errcode='42501'; end if;
 if p_global_role is not null and exists(select 1 from app_private.account_access where user_id=p_user and review_status in ('pending','awaiting_email')) and not exists(select 1 from app_private.roles where key=p_global_role and baseline='guest') then raise exception 'review_required' using errcode='22023'; end if;
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
 on conflict(user_id) do update set guest_only=excluded.guest_only,changed_by=excluded.changed_by,updated_at=now(),review_guest=case when app_private.account_access.review_status='verified' and not excluded.guest_only then false else app_private.account_access.review_guest end;
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
create or replace function public.save_person_roles(p_user uuid,p_global_role text,p_clubs jsonb,p_revision text,p_request uuid,p_expected_actor uuid) returns jsonb
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
 if exists(select 1 from app_private.account_access where user_id=p_user and review_status in ('pending','awaiting_email'))
 and (jsonb_array_length(p_clubs)>0 or (p_global_role is not null and p_global_role<>'guest')) then
 raise exception 'review_required' using errcode='22023'; end if;
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
notify pgrst,'reload schema';
commit;
