-- Mellon blocks 5–6. Run this entire file once in Supabase SQL Editor.
-- Repeatable; no copies of events and no changes to existing map/chat RPCs.
begin;
alter table public.events add column if not exists publish_to_feed boolean not null default false;
alter table public.events add column if not exists feed_published_at timestamptz;
alter table public.events add column if not exists photo_path text;
alter table public.events add column if not exists icon_id text;
alter table public.events add column if not exists icon_manual boolean not null default false;
create index if not exists events_general_feed on public.events(feed_published_at desc,id desc)
 where publish_to_feed and status='published';

-- Public access is explicit; archived clubs and hidden parishes stay hidden.
create or replace function app_private.event_in_general_feed(p_event uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.events e join public.youth_groups g on g.id=e.youth_id
 where e.id=p_event and e.publish_to_feed and e.status='published'
 and e.feed_published_at<=now() and not g.is_archived and app_private.parish_public(e.parish_id));
$$;
revoke all on function app_private.event_in_general_feed(uuid) from public;
grant execute on function app_private.event_in_general_feed(uuid) to anon,authenticated;
drop policy if exists events_general_feed_read on public.events;
create policy events_general_feed_read on public.events for select to anon,authenticated
 using(app_private.event_in_general_feed(id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('event-photos','event-photos',false,8388608,array['image/png'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=array['image/png'];

create or replace function app_private.event_photo_access(p_name text,p_write boolean) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare v_club uuid;v_event uuid;
begin
 if p_name !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.png$' then return false; end if;
 begin
 v_club:=split_part(p_name,'/',1)::uuid;v_event:=split_part(p_name,'/',2)::uuid;
 exception when invalid_text_representation then return false;end;
 if p_write then
 return auth.uid() is not null and app_private.can_manage_club_information(v_club)
 and not exists(select 1 from public.events e where e.id=v_event and e.youth_id<>v_club);
 end if;
 return (auth.uid() is not null and app_private.can_manage_club_information(v_club)) or
 exists(select 1 from public.events e where e.id=v_event and e.youth_id=v_club and e.photo_path=p_name
 and e.status in ('published','cancelled') and
 (app_private.event_in_general_feed(e.id) or app_private.can_enter_club(v_club)));
end $$;
revoke all on function app_private.event_photo_access(text,boolean) from public;
grant execute on function app_private.event_photo_access(text,boolean) to anon,authenticated;
drop policy if exists event_photos_read on storage.objects;
create policy event_photos_read on storage.objects for select to anon,authenticated
 using(bucket_id='event-photos' and app_private.event_photo_access(name,false));
drop policy if exists event_photos_insert on storage.objects;
create policy event_photos_insert on storage.objects for insert to authenticated
 with check(bucket_id='event-photos' and app_private.event_photo_access(name,true));
-- Uploaded paths are immutable. No client UPDATE or DELETE policy is granted.

create or replace function public.save_club_publication(p_youth uuid,p_id uuid,p_kind text,
 p_data jsonb,p_expected timestamptz,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_old public.events;v_exists boolean;v_publish boolean;v_photo text;v_icon text;v_manual boolean;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user
 or not app_private.can_manage_club_information(p_youth) then
 raise exception 'forbidden' using errcode='42501';end if;
 if p_kind is null or p_kind not in ('events','schedule') or p_id is null
 or jsonb_typeof(p_data) is distinct from 'object' then
 raise exception 'invalid_content' using errcode='22023';end if;
 perform pg_advisory_xact_lock(120010);
 select * into v_old from public.events where id=p_id for update;v_exists:=found;
 if v_exists and (v_old.youth_id is distinct from p_youth or v_old.club_section<>p_kind) then
 raise exception 'forbidden' using errcode='42501';end if;
 -- Same UUID on a retried create is an idempotent no-op, including metadata.
 if v_exists and p_expected is null then
 if v_old.created_by is distinct from auth.uid() then raise exception 'edit_conflict' using errcode='40001';end if;
 return p_id;end if;
 if (v_exists and v_old.updated_at is distinct from p_expected) or (not v_exists and p_expected is not null) then
 raise exception 'edit_conflict' using errcode='40001';end if;
 if jsonb_typeof(p_data->'publish_to_feed') is distinct from 'boolean'
 or jsonb_typeof(p_data->'icon_manual') is distinct from 'boolean'
 or (p_data ? 'photo_path' and jsonb_typeof(p_data->'photo_path') not in ('string','null')) then
 raise exception 'invalid_publication' using errcode='22023';end if;
 v_publish:=(p_data->>'publish_to_feed')::boolean;v_manual:=(p_data->>'icon_manual')::boolean;
 v_photo:=nullif(p_data->>'photo_path','');v_icon:=p_data->>'icon_id';
 if v_icon is null or v_icon not in ('help_hands','help_heart','help_gift','faith_church','faith_candle','faith_bell',
 'people_group','people_chat','people_meeting','sport_ball','sport_run','sport_bike','trip_bus','trip_route','trip_boat',
 'learn_book','learn_school','learn_lecture','event_calendar','event_date') then
 raise exception 'invalid_icon' using errcode='22023';end if;
 if v_photo is not null then
 if split_part(v_photo,'/',1)<>p_youth::text or split_part(v_photo,'/',2)<>p_id::text
 or not app_private.event_photo_access(v_photo,true) then raise exception 'invalid_photo' using errcode='22023';end if;
 perform 1 from storage.objects where bucket_id='event-photos' and name=v_photo for share;
 if not found then raise exception 'invalid_photo' using errcode='22023';end if;
 end if;
 -- Existing authorization, date validation, optimistic locking and map logic.
 perform public.save_club_information(p_youth,p_id,p_kind,p_data,p_expected,p_expected_user);
 update public.events set publish_to_feed=v_publish,photo_path=v_photo,icon_id=v_icon,icon_manual=v_manual,
 feed_published_at=case when v_publish and not coalesce(v_old.publish_to_feed,false) then now()
                       else v_old.feed_published_at end where id=p_id;
 return p_id;
end $$;
revoke all on function public.save_club_publication(uuid,uuid,text,jsonb,timestamptz,uuid) from public,anon;
grant execute on function public.save_club_publication(uuid,uuid,text,jsonb,timestamptz,uuid) to authenticated;

-- Enrich the existing dashboard without replacing its chat/read/map logic.
create or replace function public.club_publication_dashboard(p_youth uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_dashboard jsonb;v_events jsonb;
begin
 v_dashboard:=public.club_dashboard(p_youth);
 -- The current club RPC already checks membership/admin access.
 select coalesce(jsonb_agg(to_jsonb(e) order by e.starts_at,e.id),'[]'::jsonb) into v_events
 from (select e.id,e.title,e.description,e.starts_at,e.ends_at,e.location_label,e.status,e.updated_at,e.club_section,
 e.photo_path,e.icon_id,e.icon_manual,e.publish_to_feed,e.feed_published_at,
 (to_jsonb(e)->'show_on_map') show_on_map,(to_jsonb(e)->'map_latitude') map_latitude,(to_jsonb(e)->'map_longitude') map_longitude
 from public.events e where e.youth_id=p_youth and e.status in ('published','cancelled')
 order by e.starts_at desc,e.id desc limit 200) e;
 return jsonb_set(v_dashboard,'{events}',v_events);
end $$;
revoke all on function public.club_publication_dashboard(uuid) from public,anon;
grant execute on function public.club_publication_dashboard(uuid) to authenticated;

-- One read-only projection; no INSERT into posts or duplicate event rows.
create or replace view public.mellon_general_feed with(security_invoker=true) as
 select 'post:'||p.id::text as id,p.id as source_id,'post'::text as source_kind,p.parish_id,
 p.title,p.body,p.published_at,null::timestamptz as starts_at,null::text as location_label,
 null::text as photo_path,null::text as icon_id
 from public.posts p where p.status='published' and p.visibility='public' and p.published_at<=now()
 union all
 select 'event:'||e.id::text,e.id,e.club_section,e.parish_id,e.title,e.description,e.feed_published_at,
 e.starts_at,e.location_label,e.photo_path,e.icon_id from public.events e
 where e.publish_to_feed and e.status='published' and e.feed_published_at<=now()
 and app_private.event_in_general_feed(e.id);
revoke all on public.mellon_general_feed from public,anon,authenticated;
grant select on public.mellon_general_feed to anon,authenticated;

-- A public revision signal carries no event data. Unpublishing still refreshes
-- other clients even when RLS correctly stops sending them the event itself.
create table if not exists public.feed_publication_changes (
 singleton boolean primary key default true check(singleton), revision bigint not null default 0
);
alter table public.feed_publication_changes enable row level security;
revoke all on public.feed_publication_changes from anon,authenticated;
grant select on public.feed_publication_changes to anon,authenticated;
drop policy if exists feed_revision_read on public.feed_publication_changes;
create policy feed_revision_read on public.feed_publication_changes for select to anon,authenticated using(true);
insert into public.feed_publication_changes(singleton) values(true) on conflict do nothing;
create or replace function app_private.signal_feed_publication() returns trigger
language plpgsql security definer set search_path='' as $$
declare o jsonb:='{}';n jsonb:='{}';relevant boolean;
begin
 if TG_OP<>'INSERT' then o:=to_jsonb(old);end if;
 if TG_OP<>'DELETE' then n:=to_jsonb(new);end if;
 if TG_TABLE_NAME='events' then
 relevant:=coalesce((o->>'publish_to_feed')::boolean,false) or coalesce((n->>'publish_to_feed')::boolean,false);
 else
 relevant:=(o->>'visibility'='public' and o->>'status'='published') or
           (n->>'visibility'='public' and n->>'status'='published');
 end if;
 if relevant then update public.feed_publication_changes set revision=revision+1 where singleton;end if;
 return null;
end $$;
revoke all on function app_private.signal_feed_publication() from public,anon,authenticated;
drop trigger if exists event_feed_revision on public.events;
create trigger event_feed_revision after insert or update or delete on public.events
 for each row execute function app_private.signal_feed_publication();
drop trigger if exists post_feed_revision on public.posts;
create trigger post_feed_revision after insert or update or delete on public.posts
 for each row execute function app_private.signal_feed_publication();

do $$ declare t text;begin
 foreach t in array array['events','posts','feed_publication_changes'] loop
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
 select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
 execute format('alter publication supabase_realtime add table public.%I',t);end if;
 end loop;
end $$;
notify pgrst,'reload schema';
commit;
