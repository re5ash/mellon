-- Mellon: проверка новых пользователей. Выполните файл целиком после club_live.sql.
begin;
select pg_advisory_xact_lock(120010);
do $install$
begin
 if exists(select 1 from app_private.installed_features where feature='guest_review_20260912') then
  if not exists(select 1 from app_private.installed_features where feature='guest_review_20260912' and checksum='b21db77b98f22bcbc85b7d3dd8bb2a9a9a92ba2ee326dd213033261002b0f812') then raise exception 'Different guest review update already installed'; end if;
 else
  if to_regprocedure('public.club_entry(uuid)') is null or to_regprocedure('public.mark_chat_read(uuid,timestamp with time zone,uuid,uuid)') is null then raise exception 'Сначала выполните mellon_club_live.sql'; end if;
  execute $body$select pg_advisory_xact_lock(120010);
-- Review is account state, not a new role. Existing accounts are untouched.
alter table app_private.account_access add column review_status text check(review_status in ('awaiting_email','pending','verified'));
alter table app_private.account_access add column review_guest boolean not null default false;
alter table app_private.account_access add column review_youth_id uuid references public.youth_groups;
alter table app_private.account_access add column review_request_id uuid references app_private.youth_join_requests;
create table app_private.registration_intake (
 singleton boolean primary key default true check(singleton), youth_id uuid references public.youth_groups
);
insert into app_private.registration_intake(singleton) values(true);
alter table app_private.registration_intake enable row level security;
revoke all on app_private.registration_intake from public,anon,authenticated;
alter table public.notifications add column youth_request_id uuid references app_private.youth_join_requests on delete cascade;
create unique index notification_youth_request_once on public.notifications(user_id,kind,youth_request_id) where youth_request_id is not null;

create or replace function app_private.is_restricted_guest(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from app_private.account_access where user_id=p_user and (guest_only or review_guest));
$$;
create or replace function public.my_account_access() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('restricted_guest',app_private.is_restricted_guest(auth.uid()),
 'super_admin',app_private.is_super_admin(),
 'can_manage_roles',app_private.is_super_admin() or exists(select 1 from public.youth_groups g where app_private.can_manage_club_roles(g.id)),
 'review_status',(select review_status from app_private.account_access where user_id=auth.uid()));
$$;
-- Guests may receive only their own review result, not old private club notifications.
alter policy guest_notifications_limit on public.notifications using(
 not app_private.is_restricted_guest(auth.uid()) or kind='youth_decision');
-- No public club enumeration, including direct table/legacy RPC requests.
create policy guest_club_directory_limit on public.youth_groups as restrictive for select to anon,authenticated
 using(auth.uid() is not null and not app_private.is_restricted_guest(auth.uid()));
create or replace function public.available_youth_clubs() returns table(id uuid,name text,parish_name text)
language sql stable security definer set search_path='' as $$
 select g.id,g.name,p.name from public.youth_groups g join public.parishes p on p.id=g.parish_id
 where auth.uid() is not null and not app_private.is_restricted_guest(auth.uid()) and not g.is_archived and p.is_published order by p.name,g.name,g.id;
$$;

create function app_private.default_intake_club() returns uuid
language sql stable security definer set search_path='' as $$
 select coalesce(
 (select g.id from app_private.registration_intake s join public.youth_groups g on g.id=s.youth_id join public.parishes p on p.id=g.parish_id where not g.is_archived and p.is_published),
 (select case when count(*)=1 then (array_agg(g.id))[1] end from public.youth_groups g join public.parishes p on p.id=g.parish_id where not g.is_archived and p.is_published));
$$;
create function app_private.notify_youth_request(p_request uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.youth_join_requests; v_name text; v_club text;
begin
 select * into v from app_private.youth_join_requests where id=p_request and status='pending';
 if not found or not exists(select 1 from auth.users where id=v.user_id and email_confirmed_at is not null) then return; end if;
 select display_name into v_name from public.profiles where id=v.user_id;
 select name into v_club from public.youth_groups where id=v.youth_id;
 insert into public.notifications(user_id,kind,title,body,target_path,youth_request_id)
 select distinct a.user_id,'youth_request','Новая заявка',v_name||' · '||v_club,
 '/youth-requests/'||v.youth_id::text||'?request='||v.id::text,v.id
 from app_private.role_assignments a where app_private.can_review_youth_request(a.user_id,v.parish_id,v.youth_id)
 on conflict(user_id,kind,youth_request_id) where youth_request_id is not null do nothing;
end $$;
create function app_private.notify_youth_request_insert() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform app_private.notify_youth_request(new.id); return new; end $$;
create trigger notify_new_youth_request after insert on app_private.youth_join_requests for each row execute function app_private.notify_youth_request_insert();

-- Called only by trusted triggers/RPCs; metadata can request a club but cannot grant access.
create function app_private.route_review(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.account_access; v_club uuid; v_parish uuid; v_request uuid;
begin
 select * into v from app_private.account_access where user_id=p_user for update;
 if not found or v.review_status is distinct from 'pending' then return; end if;
 if v.review_request_id is not null then perform app_private.notify_youth_request(v.review_request_id); return; end if;
 v_club:=coalesce(v.review_youth_id,app_private.default_intake_club());
 select g.parish_id into v_parish from public.youth_groups g join public.parishes p on p.id=g.parish_id where g.id=v_club and not g.is_archived and p.is_published;
 if v_parish is null then
  -- Do not guess a destination when there are several clubs. Tell superadmins how to resolve it.
  insert into public.notifications(user_id,kind,title,body,target_path)
  select distinct a.user_id,'review_routing','Выберите клуб для новых заявок','Новый пользователь ожидает проверки. Настройте клуб приёма заявок в управлении.','/admin/youth-clubs'
  from app_private.role_assignments a join app_private.roles r on r.id=a.role_id and r.key='super_admin'
  where a.parish_id is null and a.youth_id is null and (a.expires_at is null or a.expires_at>now()) and not app_private.is_restricted_guest(a.user_id)
  and not exists(select 1 from public.notifications n where n.user_id=a.user_id and n.kind='review_routing' and n.read_at is null);
  return;
 end if;
 insert into app_private.youth_join_requests(receipt_key,user_id,youth_id,parish_id)
 values(gen_random_uuid(),p_user,v_club,v_parish) returning id into v_request;
 update app_private.account_access set review_youth_id=v_club,review_request_id=v_request,updated_at=now() where user_id=p_user;
end $$;

create or replace function app_private.club_application_on_signup() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_data jsonb:=new.raw_user_meta_data->'club_registration'; v_youth uuid; v_receipt uuid; v_parish uuid; v_request uuid;
begin
 if v_data ? 'youth_id' or v_data ? 'receipt_key' then
  begin v_youth:=(v_data->>'youth_id')::uuid; v_receipt:=(v_data->>'receipt_key')::uuid;
  exception when invalid_text_representation then raise exception 'invalid_club_request' using errcode='22023'; end;
  if v_youth is null or v_receipt is null then raise exception 'invalid_club_request' using errcode='22023'; end if;
  select g.parish_id into v_parish from public.youth_groups g join public.parishes p on p.id=g.parish_id where g.id=v_youth and not g.is_archived and p.is_published;
  if v_parish is null then raise exception 'club_unavailable' using errcode='22023'; end if;
  insert into app_private.youth_join_requests(receipt_key,user_id,youth_id,parish_id) values(v_receipt,new.id,v_youth,v_parish) returning id into v_request;
 end if;
 insert into app_private.account_access(user_id,review_guest,review_status,review_youth_id,review_request_id)
 values(new.id,true,case when new.email_confirmed_at is null then 'awaiting_email' else 'pending' end,v_youth,v_request);
 if new.email_confirmed_at is not null then perform app_private.route_review(new.id); end if;
 return new;
end $$;
create function app_private.review_on_email_confirmed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 update app_private.account_access set review_status='pending',updated_at=now() where user_id=new.id and review_status='awaiting_email';
 if found then perform app_private.route_review(new.id); end if;
 return new;
end $$;
create trigger review_email_confirmed after update of email_confirmed_at on auth.users for each row
 when (old.email_confirmed_at is null and new.email_confirmed_at is not null) execute function app_private.review_on_email_confirmed();

-- Unconfirmed registrations without existing entitlements also enter review after confirmation.
-- Confirmed accounts and anyone already holding a role/membership are preserved.
insert into app_private.account_access(user_id,review_guest,review_status,review_youth_id,review_request_id)
select u.id,true,'awaiting_email',r.youth_id,r.id from auth.users u
left join lateral (select id,youth_id from app_private.youth_join_requests where user_id=u.id and status='pending' order by created_at,id limit 1) r on true
where u.email_confirmed_at is null
and not exists(select 1 from app_private.role_assignments where user_id=u.id)
and not exists(select 1 from public.youth_memberships where user_id=u.id and is_member)
and not exists(select 1 from public.memberships where user_id=u.id and status='active')
on conflict(user_id) do update set review_guest=true,review_status='awaiting_email',review_youth_id=excluded.review_youth_id,review_request_id=excluded.review_request_id
where app_private.account_access.review_status is null;

create function public.registration_intake_settings() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 return jsonb_build_object('youth_id',app_private.default_intake_club(),
 'waiting_count',(select count(*) from app_private.account_access where review_status='pending' and review_request_id is null));
end $$;
create function public.set_registration_intake(p_youth uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v record;
begin
 perform pg_advisory_xact_lock(120010);
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 if not exists(select 1 from public.youth_groups g join public.parishes p on p.id=g.parish_id where g.id=p_youth and not g.is_archived and p.is_published) then raise exception 'club_unavailable' using errcode='22023'; end if;
 update app_private.registration_intake set youth_id=p_youth;
 for v in select user_id from app_private.account_access where review_status='pending' and review_request_id is null order by user_id loop
  perform app_private.route_review(v.user_id);
 end loop;
 update public.notifications set read_at=coalesce(read_at,now()) where kind='review_routing';
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'registration.intake','youth_group',p_youth);
end $$;

create or replace function public.request_youth_club(p_youth uuid,p_receipt uuid,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_parish uuid; v app_private.youth_join_requests; v_id uuid;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or app_private.is_restricted_guest(auth.uid()) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_youth is null or p_receipt is null then raise exception 'invalid_club_request' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(120010);
 perform 1 from public.profiles where id=auth.uid() for update;
 if app_private.is_restricted_guest(auth.uid()) then raise exception 'forbidden' using errcode='42501'; end if;
 select g.parish_id into v_parish from public.youth_groups g join public.parishes p on p.id=g.parish_id
 where g.id=p_youth and not g.is_archived and p.is_published for share of g,p;
 if v_parish is null then raise exception 'club_unavailable' using errcode='22023'; end if;
 if app_private.is_youth_member(p_youth) then return null; end if;
 select * into v from app_private.youth_join_requests where receipt_key=p_receipt;
 if found then
  if v.user_id is distinct from auth.uid() or v.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
  return v.id;
 end if;
 select r.id into v_id from app_private.youth_join_requests r where r.user_id=auth.uid() and r.youth_id=p_youth and r.status='pending';
 if found then return v_id; end if;
 if not exists(select 1 from auth.users u where u.id=auth.uid() and (to_jsonb(u)->>'email_confirmed_at') is not null) then
  raise exception 'email_confirmation_required' using errcode='22023'; end if;
 if not exists(select 1 from app_private.profile_private p where p.user_id=auth.uid() and nullif(btrim(p.given_name),'') is not null
 and nullif(btrim(p.family_name),'') is not null and p.birth_date is not null) then
  raise exception 'club_profile_required' using errcode='22023'; end if;
 insert into app_private.youth_join_requests(receipt_key,user_id,youth_id,parish_id)
 values(p_receipt,auth.uid(),p_youth,v_parish) returning id into v_id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id)
 values(auth.uid(),'youth.request','youth_request',v_id,v_parish);
 return v_id;
end $$;
create or replace function public.review_youth_join_request(p_request uuid,p_decision text,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v app_private.youth_join_requests;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 if p_decision is null or p_decision not in ('accepted','rejected') then raise exception 'invalid_decision' using errcode='22023'; end if;
 select * into v from app_private.youth_join_requests where id=p_request;
 if not found or not app_private.can_review_youth_request(auth.uid(),v.parish_id,v.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 -- Same ordering as membership and role mutations, including repeated decisions.
 perform pg_advisory_xact_lock(120010);
 perform 1 from public.profiles where id=v.user_id for update;
 select * into strict v from app_private.youth_join_requests where id=p_request for update;
 if not app_private.can_review_youth_request(auth.uid(),v.parish_id,v.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 if v.status=p_decision then return; end if;
 if v.status<>'pending' then raise exception 'request_already_reviewed' using errcode='40001'; end if;
 if not exists(select 1 from auth.users where id=v.user_id and email_confirmed_at is not null) then raise exception 'email_confirmation_required' using errcode='22023'; end if;
 if p_decision='accepted' then
  if not exists(select 1 from auth.users u where u.id=v.user_id and (to_jsonb(u)->>'email_confirmed_at') is not null) then
   raise exception 'email_confirmation_required' using errcode='22023'; end if;
  if not exists(select 1 from public.youth_groups g where g.id=v.youth_id and not g.is_archived) then
   raise exception 'club_unavailable' using errcode='22023'; end if;
  insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(v.youth_id,v.user_id,true,false)
  on conflict(youth_id,user_id) do update set is_member=true,updated_at=now();
 end if;
 -- Lift only the automatic review restriction. Explicit global Guest and all other role assignments remain unchanged.
 update app_private.account_access set review_status='verified',review_guest=(p_decision='rejected'),updated_at=now()
 where user_id=v.user_id and review_request_id=v.id;
 update public.notifications set read_at=coalesce(read_at,now()) where youth_request_id=v.id and kind='youth_request';
 update app_private.youth_join_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where id=v.id;
 insert into public.notifications(user_id,kind,title,body,target_path) values(v.user_id,'youth_decision',
 case when p_decision='accepted' then 'Заявка одобрена' else 'Заявка рассмотрена' end,
 case when p_decision='accepted' then 'Вы приняты в молодёжный клуб.' else 'Проверен. Доступ к молодёжному клубу пока не открыт.' end,case when p_decision='accepted' then '/my-youth' else '/feed' end);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'youth.request.review','youth_request',v.id,v.parish_id,jsonb_build_object('decision',p_decision));
end $$;
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

-- Every new helper is private; only the two superadmin-checked settings RPCs are exposed.
revoke all on function app_private.default_intake_club(),app_private.notify_youth_request(uuid),app_private.notify_youth_request_insert(),app_private.route_review(uuid),app_private.review_on_email_confirmed() from public,anon,authenticated;
revoke all on function public.registration_intake_settings(),public.set_registration_intake(uuid,uuid) from public,anon,authenticated;
grant execute on function public.registration_intake_settings(),public.set_registration_intake(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
$body$;
  insert into app_private.installed_features(feature,checksum) values('guest_review_20260912','b21db77b98f22bcbc85b7d3dd8bb2a9a9a92ba2ee326dd213033261002b0f812');
 end if;
end $install$;
commit;
