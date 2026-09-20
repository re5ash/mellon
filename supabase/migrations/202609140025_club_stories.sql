begin;
create table if not exists public.club_stories (
 id uuid primary key,
 youth_id uuid not null references public.youth_groups(id) on delete cascade,
 author_id uuid not null references auth.users(id) on delete cascade,
 media_path text not null unique,
 mime_type text not null check(mime_type in ('image/png','video/mp4','video/webm','video/quicktime')),
 byte_size bigint not null check(byte_size between 1 and 52428800),
 duration_ms integer,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '24 hours',
 check((mime_type='image/png' and duration_ms is null) or (mime_type<>'image/png' and duration_ms between 1 and 60000))
);
create index if not exists club_stories_active on public.club_stories(youth_id,expires_at,created_at,id);
alter table public.club_stories enable row level security;
revoke all on public.club_stories from anon,authenticated;
grant select on public.club_stories to authenticated;
drop policy if exists club_stories_read on public.club_stories;
create policy club_stories_read on public.club_stories for select to authenticated
 using(expires_at>now() and app_private.can_enter_club(youth_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('club-stories','club-stories',false,52428800,array['image/png','video/mp4','video/webm','video/quicktime'])
 on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create or replace function app_private.club_story_club(p_path text) returns uuid
language plpgsql immutable set search_path='' as $$
begin
 if p_path !~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(png|mp4|webm|mov)$' then return null; end if;
 return split_part(p_path,'/',1)::uuid;
exception when invalid_text_representation then return null;
end $$;
create or replace function app_private.can_read_club_story(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select app_private.can_edit_club_photo(app_private.club_story_club(p_path)) or exists(
 select 1 from public.club_stories s where s.media_path=p_path and s.expires_at>now()
 and app_private.can_enter_club(s.youth_id));
$$;
grant execute on function app_private.club_story_club(text),app_private.can_read_club_story(text) to authenticated;
drop policy if exists club_story_read on storage.objects;
create policy club_story_read on storage.objects for select to authenticated
 using(bucket_id='club-stories' and app_private.can_read_club_story(name));
drop policy if exists club_story_insert on storage.objects;
create policy club_story_insert on storage.objects for insert to authenticated
 with check(bucket_id='club-stories' and app_private.can_edit_club_photo(app_private.club_story_club(name))
 and split_part(name,'/',2)=auth.uid()::text);
drop policy if exists club_story_remove on storage.objects;
create policy club_story_remove on storage.objects for delete to authenticated
 using(bucket_id='club-stories' and app_private.can_edit_club_photo(app_private.club_story_club(name)));

create or replace function public.publish_club_story(p_id uuid,p_youth uuid,p_path text,p_mime text,p_bytes bigint,p_duration integer,p_expected_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result public.club_stories; ext text;
begin
 perform pg_advisory_xact_lock(120010);
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or not app_private.can_edit_club_photo(p_youth)
 then raise exception 'forbidden' using errcode='42501'; end if;
 ext:=case p_mime when 'image/png' then 'png' when 'video/mp4' then 'mp4' when 'video/webm' then 'webm' when 'video/quicktime' then 'mov' end;
 if p_id is null or ext is null or p_path is distinct from p_youth::text||'/'||auth.uid()::text||'/'||p_id::text||'.'||ext
 or p_bytes is null or p_bytes<1 or p_bytes>52428800
 or (p_mime='image/png' and p_duration is not null)
 or (p_mime<>'image/png' and (p_duration is null or p_duration<1 or p_duration>60000))
 then raise exception 'invalid_story' using errcode='22023'; end if;
 select * into result from public.club_stories where id=p_id;
 if found then
  if result.author_id=auth.uid() and result.youth_id=p_youth and result.media_path=p_path and result.mime_type=p_mime and result.byte_size=p_bytes and result.duration_ms is not distinct from p_duration then return to_jsonb(result); end if;
  raise exception 'story_conflict' using errcode='40001';
 end if;
 perform 1 from storage.objects where bucket_id='club-stories' and name=p_path for update;
 if not found then raise exception 'missing_story_upload' using errcode='22023'; end if;
 insert into public.club_stories(id,youth_id,author_id,media_path,mime_type,byte_size,duration_ms)
 values(p_id,p_youth,auth.uid(),p_path,p_mime,p_bytes,p_duration) returning * into result;
 return to_jsonb(result);
end $$;
create or replace function public.expired_club_stories(p_youth uuid) returns table(id uuid,media_path text)
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.can_edit_club_photo(p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 return query select s.id,s.media_path from public.club_stories s where s.youth_id=p_youth and s.expires_at<=now() order by s.expires_at limit 100;
end $$;
create or replace function public.remove_club_story(p_id uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare s public.club_stories;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select * into s from public.club_stories where id=p_id;
 if not found then return; end if;
 if not app_private.can_edit_club_photo(s.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 -- Delete bytes through Storage API first; never delete storage.objects in SQL.
 if exists(select 1 from storage.objects where bucket_id='club-stories' and name=s.media_path)
 then raise exception 'remove_media_first' using errcode='22023'; end if;
 delete from public.club_stories where id=p_id;
end $$;
revoke all on function public.publish_club_story(uuid,uuid,text,text,bigint,integer,uuid),public.expired_club_stories(uuid),public.remove_club_story(uuid,uuid) from public;
grant execute on function public.publish_club_story(uuid,uuid,text,text,bigint,integer,uuid),public.expired_club_stories(uuid),public.remove_club_story(uuid,uuid) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='club_stories') then
 alter publication supabase_realtime add table public.club_stories;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
