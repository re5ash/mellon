-- Mellon: выбор клуба, единый вход и отдельное управление. Выполните весь файл.
begin;
select pg_advisory_xact_lock(120010);
create table if not exists app_private.installed_features(feature text primary key,checksum text not null,installed_at timestamptz not null default now());
revoke all on app_private.installed_features from public,anon,authenticated;
do $install$
begin
 if exists(select 1 from app_private.installed_features where feature='club_navigation_20260912') then
  if not exists(select 1 from app_private.installed_features where feature='club_navigation_20260912' and checksum='614557584594d27b52a92e8e24bf18eb37353b45ea7ae21d4db83b565e2dc705') then raise exception 'A different club navigation update is already installed'; end if;
  raise notice 'Обновление молодёжных клубов уже установлено';
 else
  if to_regprocedure('app_private.is_club_admin(uuid)') is null then raise exception 'Сначала выполните mellon_club_administrator.sql (обновление 017)'; end if;
  execute $club_navigation_migration$
-- Public club selection is separate from administrative club settings.
-- Existing role catalog, assignments, club IDs and memberships are preserved.
drop index if exists app_private.youth_one_pending_request;
create unique index if not exists youth_one_pending_request_per_club
 on app_private.youth_join_requests(user_id,youth_id) where status='pending';

create or replace function public.youth_club_directory() returns table(
 id uuid,parish_id uuid,name text,description text,city_name text,can_open boolean,request_status text)
language sql stable security definer set search_path='' as $$
 select g.id,g.parish_id,g.name,g.description,c.name,
 app_private.has_scope_permission('parish.read',g.parish_id,g.id),
 (select r.status from app_private.youth_join_requests r where r.user_id=auth.uid() and r.youth_id=g.id order by r.created_at desc,r.id desc limit 1)
 from public.youth_groups g join public.parishes p on p.id=g.parish_id join public.cities c on c.id=p.city_id
 where auth.uid() is not null and not app_private.is_restricted_guest(auth.uid()) and not g.is_archived
 and (p.is_published or app_private.has_scope_permission('parish.read',g.parish_id,g.id))
 order by g.name,g.id;
$$;

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
 insert into public.notifications(user_id,kind,title,body,target_path)
 select distinct a.user_id,'youth_request','Новая заявка в молодёжный клуб','Участник ожидает рассмотрения заявки.','/youth-requests/'||p_youth::text
 from app_private.role_assignments a where app_private.can_review_youth_request(a.user_id,v_parish,p_youth);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id)
 values(auth.uid(),'youth.request','youth_request',v_id,v_parish);
 return v_id;
end $$;

create or replace function public.managed_youth_groups(p_parish uuid default null) returns setof public.youth_groups
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 return query select g.* from public.youth_groups g where p_parish is null or g.parish_id=p_parish order by g.name,g.id;
end $$;

create or replace function public.my_club_workspaces() returns setof public.youth_groups
language sql stable security definer set search_path='' as $$
 select g.* from public.youth_groups g where auth.uid() is not null and not app_private.is_restricted_guest(auth.uid()) and not g.is_archived
 and exists(select 1 from unnest(array['youth.members.manage','youth.roles.manage','youth.requests.review','chats.create','chats.manage','messages.pin','messages.delete_any','posts.manage','events.create','events.edit']) as permission(key)
 where app_private.has_scope_permission(permission.key,g.parish_id,g.id)) order by g.name,g.id;
$$;

create or replace function public.club_management_cities() returns table(id uuid,name text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 return query select c.id,c.name from public.cities c order by c.name,c.id;
end $$;
create or replace function public.save_youth_group(p_id uuid,p_parish uuid,p_name text,p_description text,p_archived boolean,p_revision bigint) returns uuid
language plpgsql security definer set search_path='' as $$
declare v public.youth_groups;
begin
 perform pg_advisory_xact_lock(120010);
 if not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or length(btrim(coalesce(p_name,''))) not between 1 and 160 or p_description is null or length(p_description)>5000 or p_archived is null then raise exception 'invalid_youth' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,10));
 select * into v from public.youth_groups where id=p_id for update;
 if found then
 if v.parish_id<>p_parish then raise exception 'forbidden' using errcode='42501'; end if;
 if (v.name,v.description,v.is_archived) is not distinct from (btrim(p_name),btrim(p_description),p_archived) then return v.id; end if;
 if v.revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.youth_groups set name=btrim(p_name),description=btrim(p_description),is_archived=p_archived where id=p_id;
 else
 if p_revision is distinct from 0::bigint then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.youth_groups(id,parish_id,name,description,is_archived,created_by) values(p_id,p_parish,btrim(p_name),btrim(p_description),p_archived,auth.uid());
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'youth.save','youth_group',p_id,p_parish);
 return p_id;
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
 if p_decision='accepted' then
  if not exists(select 1 from auth.users u where u.id=v.user_id and (to_jsonb(u)->>'email_confirmed_at') is not null) then
   raise exception 'email_confirmation_required' using errcode='22023'; end if;
  if not exists(select 1 from public.youth_groups g where g.id=v.youth_id and not g.is_archived) then
   raise exception 'club_unavailable' using errcode='22023'; end if;
  insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(v.youth_id,v.user_id,true,false)
  on conflict(youth_id,user_id) do update set is_member=true,updated_at=now();
 end if;
 update app_private.youth_join_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where id=v.id;
 insert into public.notifications(user_id,kind,title,body,target_path) values(v.user_id,'youth_decision',
 case when p_decision='accepted' then 'Заявка одобрена' else 'Заявка рассмотрена' end,
 case when p_decision='accepted' then 'Вы приняты в молодёжный клуб.' else 'Руководитель отклонил заявку. Вы можете связаться с руководителем клуба для уточнения.' end,'/my-youth');
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'youth.request.review','youth_request',v.id,v.parish_id,jsonb_build_object('decision',p_decision));
end $$;

-- parish_id is retained as an internal storage scope for existing content/RLS.
-- New clubs receive a private-to-management technical parent; no parish admission is required.
create or replace function public.save_youth_club(p_id uuid,p_city uuid,p_name text,p_description text,p_archived boolean,p_revision bigint,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_parish uuid;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 if not app_private.is_super_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or length(btrim(coalesce(p_name,''))) not between 1 and 160 or p_description is null or length(p_description)>5000 or p_archived is null then raise exception 'invalid_youth' using errcode='22023'; end if;
 select g.parish_id into v_parish from public.youth_groups g where g.id=p_id;
 if v_parish is null then
  if p_revision is distinct from 0::bigint then raise exception 'edit_conflict' using errcode='40001'; end if;
  if not exists(select 1 from public.cities where id=p_city) then raise exception 'invalid_city' using errcode='22023'; end if;
  v_parish:=p_id;
  insert into public.parishes(id,city_id,slug,name,is_published) values(v_parish,p_city,'club-'||p_id::text,btrim(p_name),true);
 end if;
 return public.save_youth_group(p_id,v_parish,p_name,p_description,p_archived,p_revision);
end $$;

revoke all on function public.youth_club_directory(),public.request_youth_club(uuid,uuid,uuid),
 public.managed_youth_groups(uuid),public.my_club_workspaces(),public.club_management_cities(),
 public.save_youth_group(uuid,uuid,text,text,boolean,bigint),public.save_youth_club(uuid,uuid,text,text,boolean,bigint,uuid),
 public.review_youth_join_request(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.youth_club_directory(),public.request_youth_club(uuid,uuid,uuid),
 public.managed_youth_groups(uuid),public.my_club_workspaces(),public.club_management_cities(),
 public.save_youth_group(uuid,uuid,text,text,boolean,bigint),public.save_youth_club(uuid,uuid,text,text,boolean,bigint,uuid),
 public.review_youth_join_request(uuid,text,uuid) to authenticated;
notify pgrst,'reload schema';

$club_navigation_migration$;
  insert into app_private.installed_features(feature,checksum)values('club_navigation_20260912','614557584594d27b52a92e8e24bf18eb37353b45ea7ae21d4db83b565e2dc705');
 end if;
end $install$;
commit;
