begin;
select pg_advisory_xact_lock(120010);
alter table public.youth_groups add column photo_path text, add column photo_revision bigint not null default 0;
alter table public.youth_memberships add column left_at timestamptz, add column joined_at timestamptz;
update public.youth_memberships set joined_at=updated_at;
create function app_private.club_membership_dates() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='INSERT' then new.joined_at:=now();
 elsif new.is_member and not old.is_member then new.joined_at:=now();
 else new.joined_at:=old.joined_at;end if;
 return new;
end $$;
create trigger club_membership_dates before insert or update on public.youth_memberships for each row execute function app_private.club_membership_dates();
alter table public.events add column club_section text not null default 'events' check(club_section in ('events','schedule'));

create function app_private.can_enter_club(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not app_private.is_restricted_guest(auth.uid())
 and exists(select 1 from public.youth_groups g where g.id=p_club and not g.is_archived
 and (app_private.is_super_admin() or app_private.is_youth_member(g.id)));
$$;
create function app_private.can_edit_club_photo(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select app_private.can_enter_club(p_club) and (app_private.is_super_admin() or app_private.is_club_admin(p_club));
$$;
create function app_private.can_manage_club_information(p_club uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select app_private.can_enter_club(p_club) and (app_private.is_super_admin() or exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 where a.user_id=auth.uid() and a.youth_id=p_club and r.key in ('youth_admin','youth_leader')
 and (a.expires_at is null or a.expires_at>now())));
$$;
-- Club privileges never derive from membership in a different club/parish.
-- Existing roles are retained; no catalog entry or assignment is added.
create or replace function app_private.has_scope_permission(p_key text,p_parish uuid,p_youth uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select not app_private.is_restricted_guest(auth.uid()) and case when p_youth is null then app_private.has_permission(p_key,p_parish) else
 exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish and not g.is_archived
 and app_private.can_enter_club(g.id) and (
 app_private.is_super_admin() or
 (p_key in ('events.create','events.edit','events.delete','events.manage','help.manage') and app_private.can_manage_club_information(g.id)) or
 (p_key not in ('events.create','events.edit','events.delete','events.manage','help.manage') and (
 p_key in ('parish.read','chat.read','chat.send','messages.delete_own','events.attend') or exists(
 select 1 from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 join app_private.role_permissions rp on rp.role_id=r.id where a.user_id=auth.uid() and a.youth_id=g.id
 and a.parish_id=g.parish_id and r.scope='youth' and rp.permission_key=p_key
 and (a.expires_at is null or a.expires_at>now())))))) end;
$$;
create or replace function app_private.can_read_scope_content(p_parish uuid,p_youth uuid,p_visibility text) returns boolean
language sql stable security definer set search_path='' as $$
 select case when p_youth is not null then app_private.can_enter_club(p_youth) and exists(select 1 from public.youth_groups where id=p_youth and parish_id=p_parish)
 else p_visibility='public' or app_private.has_permission('parish.read',p_parish) end;
$$;

create table public.club_chat_reads (
 user_id uuid not null references public.profiles on delete cascade,
 room_id uuid not null references public.chat_rooms on delete cascade,
 read_at timestamptz not null, read_message_id uuid not null,
 primary key(user_id,room_id)
);
alter table public.club_chat_reads enable row level security;
revoke all on public.club_chat_reads from public,anon,authenticated;
grant select on public.club_chat_reads to authenticated;
create policy own_club_chat_reads on public.club_chat_reads for select to authenticated using(user_id=auth.uid() and app_private.can_read_room(room_id));
create function public.my_chat_reads(p_expected_user uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 return coalesce((select jsonb_object_agg(room_id::text,read_at) from public.club_chat_reads where user_id=auth.uid() and app_private.can_read_room(room_id)),'{}');
end $$;
create function public.mark_chat_read(p_room uuid,p_at timestamptz,p_expected_user uuid,p_message uuid default null) returns void
language plpgsql security definer set search_path='' as $$
declare m public.chat_messages;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 if not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 select * into m from public.chat_messages where room_id=p_room and deleted_at is null and created_at<=least(p_at,now()) and (p_message is null or id=p_message) order by created_at desc,id desc limit 1;
 if not found then return; end if;
 insert into public.club_chat_reads(user_id,room_id,read_at,read_message_id)values(auth.uid(),p_room,m.created_at,m.id)
 on conflict(user_id,room_id)do update set read_at=excluded.read_at,read_message_id=excluded.read_message_id
 where (excluded.read_at,excluded.read_message_id)>(club_chat_reads.read_at,club_chat_reads.read_message_id);
end $$;

create function public.leave_youth_club(p_youth uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 perform 1 from public.profiles where id=auth.uid() for update;
 update public.youth_memberships set is_member=false,is_activist=false,left_at=now(),updated_at=now()
 where youth_id=p_youth and user_id=auth.uid() and is_member;
 if not found then return; end if;
 -- The membership trigger removes only this club's assignments/chat access.
 update app_private.youth_join_requests set status='rejected' where user_id=auth.uid() and youth_id=p_youth and status='pending';
 delete from public.club_chat_reads where user_id=auth.uid() and room_id in(select id from public.chat_rooms where youth_id=p_youth);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'youth.leave','youth_group',p_youth);
end $$;

create or replace function public.youth_club_directory() returns table(
 id uuid,parish_id uuid,name text,description text,city_name text,can_open boolean,request_status text)
language sql stable security definer set search_path='' as $$
 select g.id,g.parish_id,g.name,g.description,c.name,app_private.can_enter_club(g.id),
 (select r.status from app_private.youth_join_requests r where r.user_id=auth.uid() and r.youth_id=g.id
 and r.created_at>coalesce((select m.left_at from public.youth_memberships m where m.youth_id=g.id and m.user_id=auth.uid()),'-infinity')
 order by r.created_at desc,r.id desc limit 1)
 from public.youth_groups g join public.parishes p on p.id=g.parish_id join public.cities c on c.id=p.city_id
 where auth.uid() is not null and not app_private.is_restricted_guest(auth.uid()) and not g.is_archived
 and (p.is_published or app_private.can_enter_club(g.id)) order by g.name,g.id;
$$;
create function public.club_entry(p_youth uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 select to_jsonb(d)||jsonb_build_object('address',p.address,'city',d.city_name,'temple_name',p.name,'temple_description',p.description,
 'photo_path',g.photo_path,'photo_revision',g.photo_revision,'is_member',app_private.is_youth_member(g.id),
 'can_edit_photo',app_private.can_edit_club_photo(g.id)) into result
 from public.youth_club_directory() d join public.youth_groups g on g.id=d.id join public.parishes p on p.id=g.parish_id where d.id=p_youth;
 if result is null then raise exception 'forbidden' using errcode='42501'; end if;
 return result;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('club-photos','club-photos',false,8388608,array['image/png']);
create function app_private.club_photo_club(p_path text) returns uuid
language plpgsql immutable set search_path='' as $$
begin
 if p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.png$' then return null; end if;
 return split_part(p_path,'/',1)::uuid;
exception when invalid_text_representation then return null;
end $$;
create function app_private.can_read_club_photo(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.youth_club_directory() d join public.youth_groups g on g.id=d.id
 where g.photo_path=p_path) or (app_private.can_edit_club_photo(app_private.club_photo_club(p_path)) and split_part(p_path,'/',2)=auth.uid()::text);
$$;
create policy club_photo_read on storage.objects for select to authenticated using(bucket_id='club-photos' and app_private.can_read_club_photo(name));
create policy club_photo_insert on storage.objects for insert to authenticated with check(bucket_id='club-photos'
 and app_private.can_edit_club_photo(app_private.club_photo_club(name)) and split_part(name,'/',2)=auth.uid()::text);
-- Immutable object names avoid stale caches and concurrent overwrite races.
create function app_private.is_current_club_photo(p_path text) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.youth_groups where photo_path=p_path); $$;
create policy club_photo_remove on storage.objects for delete to authenticated using(bucket_id='club-photos'
 and app_private.can_edit_club_photo(app_private.club_photo_club(name))
 and not app_private.is_current_club_photo(name));
create function public.set_club_photo(p_youth uuid,p_path text,p_revision bigint,p_expected_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 select * into g from public.youth_groups where id=p_youth for update;
 if not found or not app_private.can_edit_club_photo(p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_path is null or app_private.club_photo_club(p_path) is distinct from p_youth or split_part(p_path,'/',2)<>auth.uid()::text
 then raise exception 'invalid_photo' using errcode='22023'; end if;
 perform 1 from storage.objects where bucket_id='club-photos' and name=p_path for update;
 if not found then raise exception 'invalid_photo' using errcode='22023'; end if;
 if g.photo_path=p_path then return public.club_entry(p_youth); end if;
 if g.photo_revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.youth_groups set photo_path=p_path,photo_revision=photo_revision+1 where id=p_youth;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'club.photo','youth_group',p_youth);
 return public.club_entry(p_youth);
end $$;

create or replace function public.club_dashboard(p_youth uuid,p_reads jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.youth_groups; v_rooms jsonb; v_events jsonb; v_help jsonb;
begin
 if not app_private.can_enter_club(p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 select * into strict g from public.youth_groups where id=p_youth;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.sort_order,t.title,t.id),'[]') into v_rooms from(
 select r.*,lm.created_at last_message_at,lm.body last_message,coalesce(pr.display_name,'Участник') last_author,
 (select count(*)::int from public.chat_messages m where m.room_id=r.id and m.deleted_at is null and m.author_id<>auth.uid()
 and (m.created_at,m.id)>(coalesce(rd.read_at,ym.joined_at,g.created_at),coalesce(rd.read_message_id,'00000000-0000-0000-0000-000000000000'::uuid))) unread_count
 from public.chat_rooms r left join public.club_chat_reads rd on rd.room_id=r.id and rd.user_id=auth.uid()
 left join public.youth_memberships ym on ym.youth_id=g.id and ym.user_id=auth.uid() and ym.is_member
 left join lateral(select m.* from public.chat_messages m where m.room_id=r.id and m.deleted_at is null order by m.created_at desc,m.id desc limit 1)lm on true
 left join public.profiles pr on pr.id=lm.author_id
 where r.youth_id=g.id and not r.is_archived and r.deleted_at is null and app_private.can_read_room(r.id))t;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.starts_at,t.id),'[]') into v_events from(
 select e.id,e.title,e.description,e.starts_at,e.ends_at,e.location_label,e.status,e.updated_at,e.club_section
 from public.events e where e.youth_id=g.id and e.status in ('published','cancelled') and e.ends_at>=now() order by e.starts_at,e.id limit 200)t;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc,t.id),'[]') into v_help from(
 select h.id,h.title,h.description,h.created_at,h.status,h.updated_at from public.help_requests h
 where h.youth_id=g.id and h.status in ('published','fulfilled') order by h.created_at desc,h.id limit 100)t;
 return jsonb_build_object('club',public.club_entry(g.id)||jsonb_build_object('leaders',coalesce((
 select string_agg(distinct p.display_name,', ') from app_private.role_assignments a join app_private.roles r on r.id=a.role_id
 join public.profiles p on p.id=a.user_id where a.youth_id=g.id and r.key in ('youth_admin','youth_leader')
 and (a.expires_at is null or a.expires_at>now()) and not app_private.is_restricted_guest(a.user_id)),'')),
 'chats',v_rooms,'events',v_events,'help',v_help,'can_manage_information',app_private.can_manage_club_information(g.id),
 'can_create_chats',app_private.has_scope_permission('chats.create',g.parish_id,g.id),
 'can_manage_chats',app_private.has_scope_permission('chats.manage',g.parish_id,g.id));
end $$;

create function public.save_club_information(p_youth uuid,p_id uuid,p_kind text,p_data jsonb,p_expected timestamptz,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups; old_time timestamptz; v_found boolean; v_title text; v_body text; v_creator uuid;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 select * into g from public.youth_groups where id=p_youth;
 if not found or not app_private.can_manage_club_information(p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or p_kind is null or p_kind not in ('schedule','events','help') or jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_content' using errcode='22023'; end if;
 v_title:=btrim(p_data->>'title');v_body:=coalesce(p_data->>'description','');
 if v_title is null or length(v_title) not between 1 and 200 or length(v_body)>10000 then raise exception 'invalid_content' using errcode='22023'; end if;
 if p_kind='help' then
 select updated_at,author_id into old_time,v_creator from public.help_requests where id=p_id and youth_id=p_youth for update;v_found:=found;
 if not v_found and exists(select 1 from public.help_requests where id=p_id) then raise exception 'forbidden' using errcode='42501'; end if;
 else
 select updated_at,created_by into old_time,v_creator from public.events where id=p_id and youth_id=p_youth and club_section=p_kind for update;v_found:=found;
 if not v_found and exists(select 1 from public.events where id=p_id) then raise exception 'forbidden' using errcode='42501'; end if;
 end if;
 if v_found and p_expected is null then
 if v_creator is distinct from auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 return p_id; end if;
 if old_time is distinct from p_expected then raise exception 'edit_conflict' using errcode='40001'; end if;
 if p_kind='help' then
 insert into public.help_requests(id,parish_id,youth_id,author_id,title,description,status)
 values(p_id,g.parish_id,p_youth,auth.uid(),v_title,v_body,'published') on conflict(id)do update set title=excluded.title,description=excluded.description;
 else
 if (p_data->>'ends_at')::timestamptz<=(p_data->>'starts_at')::timestamptz or p_data->>'starts_at' is null or p_data->>'ends_at' is null then raise exception 'invalid_content' using errcode='22023'; end if;
 insert into public.events(id,parish_id,youth_id,created_by,title,description,status,starts_at,ends_at,location_label,club_section)
 values(p_id,g.parish_id,p_youth,auth.uid(),v_title,v_body,'published',(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,coalesce(p_data->>'location',''),p_kind)
 on conflict(id)do update set title=excluded.title,description=excluded.description,starts_at=excluded.starts_at,ends_at=excluded.ends_at,location_label=excluded.location_label;
 end if;
 return p_id;
end $$;
create function public.remove_club_information(p_youth uuid,p_id uuid,p_kind text,p_expected timestamptz,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_time timestamptz;v_status text;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 if not app_private.can_manage_club_information(p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='help' then select updated_at,status into v_time,v_status from public.help_requests where id=p_id and youth_id=p_youth for update;
 elsif p_kind in ('schedule','events') then select updated_at,status into v_time,v_status from public.events where id=p_id and youth_id=p_youth and club_section=p_kind for update;
 else raise exception 'invalid_content' using errcode='22023'; end if;
 if not found then raise exception 'forbidden' using errcode='42501'; end if;
 if v_status='archived' then return; end if;
 if v_time is distinct from p_expected then raise exception 'edit_conflict' using errcode='40001'; end if;
 if p_kind='help' then update public.help_requests set status='archived' where id=p_id;
 else update public.events set status='archived' where id=p_id;end if;
end $$;

do $grants$ declare f record;begin
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='app_private' and p.proname in
 ('can_enter_club','can_edit_club_photo','can_manage_club_information','club_photo_club','can_read_club_photo','is_current_club_photo') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
 for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in
 ('my_chat_reads','mark_chat_read','leave_youth_club','club_entry','set_club_photo','save_club_information','remove_club_information') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);
 execute format('grant execute on function %s to authenticated',f.sig);
 end loop;
end $grants$;
do $realtime$ declare t text;begin
 foreach t in array array['club_chat_reads','youth_memberships','youth_groups','chat_rooms'] loop
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t);end if;
 end loop;
end $realtime$;
notify pgrst,'reload schema';
commit;
