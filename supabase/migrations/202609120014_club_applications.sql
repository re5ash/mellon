begin;

-- Requests are private. Neither signup metadata nor a receipt grants membership.
create table if not exists app_private.youth_join_requests (
 id uuid primary key default gen_random_uuid(),
 receipt_key uuid not null unique,
 user_id uuid not null references public.profiles on delete cascade,
 youth_id uuid not null references public.youth_groups,
 parish_id uuid not null references public.parishes,
 status text not null default 'pending' check(status in ('pending','accepted','rejected')),
 created_at timestamptz not null default now(), reviewed_at timestamptz,
 reviewed_by uuid references public.profiles,
 foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id)
);
create unique index if not exists youth_one_pending_request on app_private.youth_join_requests(user_id) where status='pending';
alter table app_private.youth_join_requests enable row level security;
revoke all on app_private.youth_join_requests from public,anon,authenticated;
update app_private.permissions set description='Рассматривать заявки в молодёжный клуб' where key='youth.requests.review';

create or replace function public.available_youth_clubs() returns table(id uuid,name text,parish_name text)
language sql stable security definer set search_path='' as $$
 select g.id,g.name,p.name from public.youth_groups g join public.parishes p on p.id=g.parish_id
 where not g.is_archived and p.is_published order by p.name,g.name,g.id;
$$;

-- Explicit actor parameter is internal only; never set JWT claims inside a definer.
create or replace function app_private.can_review_youth_request(p_user uuid,p_parish uuid,p_youth uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select p_user is not null and exists(
 select 1 from app_private.role_assignments a
 join app_private.roles r on r.id=a.role_id
 join app_private.role_permissions rp on rp.role_id=r.id and rp.permission_key='youth.requests.review'
 where a.user_id=p_user and (a.expires_at is null or a.expires_at>now())
 and ((r.scope='global' and a.parish_id is null and a.youth_id is null)
 or (r.scope='parish' and a.parish_id=p_parish and a.youth_id is null and exists(select 1 from public.memberships m where m.user_id=p_user and m.parish_id=p_parish and m.status='active'))
 or (r.scope='youth' and a.parish_id=p_parish and a.youth_id=p_youth and exists(
 select 1 from public.youth_memberships m join public.memberships pm on pm.user_id=m.user_id
 join public.youth_groups g on g.id=m.youth_id and not g.is_archived
 where m.user_id=p_user and m.youth_id=p_youth and m.is_member and pm.parish_id=p_parish and pm.status='active'))));
$$;

create or replace function app_private.club_application_on_signup() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_data jsonb; v_youth uuid; v_receipt uuid; v_parish uuid; v_request uuid;
begin
 v_data := new.raw_user_meta_data->'club_registration';
 if v_data is null or not (v_data ? 'youth_id' or v_data ? 'receipt_key') then return new; end if;
 begin
  v_youth := (v_data->>'youth_id')::uuid;
  v_receipt := (v_data->>'receipt_key')::uuid;
 exception when invalid_text_representation then raise exception 'invalid_club_request' using errcode='22023'; end;
 if v_youth is null or v_receipt is null then raise exception 'invalid_club_request' using errcode='22023'; end if;
 select g.parish_id into v_parish from public.youth_groups g join public.parishes p on p.id=g.parish_id
 where g.id=v_youth and not g.is_archived and p.is_published for share of g,p;
 if v_parish is null then raise exception 'club_unavailable' using errcode='22023'; end if;
 -- Admission to the parish remains a separate decision by its administrator.
 insert into public.memberships(user_id,parish_id,status) values(new.id,v_parish,'pending');
 insert into app_private.youth_join_requests(receipt_key,user_id,youth_id,parish_id)
 values(v_receipt,new.id,v_youth,v_parish) returning id into v_request;
 insert into public.notifications(user_id,kind,title,body,target_path)
 select distinct a.user_id,'youth_request','Новая заявка в молодёжный клуб',
 'Участник ожидает рассмотрения заявки.','/youth-requests/'||v_youth::text
 from app_private.role_assignments a
 where app_private.can_review_youth_request(a.user_id,v_parish,v_youth);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id)
 values(new.id,'youth.request','youth_request',v_request,v_parish);
 return new;
end $$;
-- Auth triggers run alphabetically: on_signup has already created the profile.
drop trigger if exists zz_club_application on auth.users;
create trigger zz_club_application after insert on auth.users for each row execute function app_private.club_application_on_signup();

-- Possession of a random receipt permits only this acknowledgement, no personal data.
-- A duplicate/obfuscated Auth signup response has no receipt and cannot show success.
create or replace function public.club_application_receipt(p_receipt uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('status',r.status) from app_private.youth_join_requests r where r.receipt_key=p_receipt;
$$;
create or replace function public.my_club_applications() returns table(id uuid,youth_name text,status text,created_at timestamptz)
language sql stable security definer set search_path='' as $$
 select r.id,g.name,r.status,r.created_at from app_private.youth_join_requests r join public.youth_groups g on g.id=r.youth_id
 where r.user_id=auth.uid() order by r.created_at desc limit 20;
$$;
create or replace function public.youth_join_requests(p_youth uuid) returns table(
 id uuid,display_name text,status text,created_at timestamptz,email_confirmed boolean,parish_active boolean)
language plpgsql stable security definer set search_path='' as $$
declare v_parish uuid;
begin
 select g.parish_id into v_parish from public.youth_groups g where g.id=p_youth;
 if not app_private.can_review_youth_request(auth.uid(),v_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 return query select r.id,p.display_name,r.status,r.created_at,
 (to_jsonb(u)->>'email_confirmed_at') is not null,
 exists(select 1 from public.memberships m where m.user_id=r.user_id and m.parish_id=r.parish_id and m.status='active')
 from app_private.youth_join_requests r join public.profiles p on p.id=r.user_id join auth.users u on u.id=r.user_id
 where r.youth_id=p_youth and r.status='pending' order by r.created_at,r.id;
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
  if not exists(select 1 from public.memberships m where m.user_id=v.user_id and m.parish_id=v.parish_id and m.status='active') then
   raise exception 'active_membership_required' using errcode='23514'; end if;
  insert into public.youth_memberships(youth_id,user_id,is_member,is_activist) values(v.youth_id,v.user_id,true,false)
  on conflict(youth_id,user_id) do update set is_member=true,updated_at=now();
 end if;
 update app_private.youth_join_requests set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid() where id=v.id;
 insert into public.notifications(user_id,kind,title,body,target_path) values(v.user_id,'youth_decision',
 case when p_decision='accepted' then 'Заявка одобрена' else 'Заявка рассмотрена' end,
 case when p_decision='accepted' then 'Вы приняты в молодёжный клуб.' else 'Руководитель отклонил заявку. Вы можете связаться с приходом для уточнения.' end,'/my-youth');
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'youth.request.review','youth_request',v.id,v.parish_id,jsonb_build_object('decision',p_decision));
end $$;

revoke all on function app_private.can_review_youth_request(uuid,uuid,uuid),app_private.club_application_on_signup() from public,anon,authenticated;
revoke all on function public.available_youth_clubs(),public.club_application_receipt(uuid),public.my_club_applications(),public.youth_join_requests(uuid),public.review_youth_join_request(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.available_youth_clubs(),public.club_application_receipt(uuid) to anon,authenticated;
grant execute on function public.my_club_applications(),public.youth_join_requests(uuid),public.review_youth_join_request(uuid,text,uuid) to authenticated;
commit;
