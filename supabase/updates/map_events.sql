-- Mellon: event map pins. Run once in Supabase SQL Editor (safe to repeat).
-- Existing event permissions, optimistic locking and visibility remain in force.
begin;
alter table public.events add column if not exists show_on_map boolean not null default false;
alter table public.events add column if not exists map_latitude double precision;
alter table public.events add column if not exists map_longitude double precision;
alter table public.events drop constraint if exists events_map_coordinates;
alter table public.events add constraint events_map_coordinates check (
 (map_latitude is null)=(map_longitude is null)
 and (map_latitude is null or map_latitude between -90 and 90)
 and (map_longitude is null or map_longitude between -180 and 180)
 and (not show_on_map or map_latitude is not null));
create index if not exists events_map_today on public.events(starts_at,id) where show_on_map and status='published';

create or replace function app_private.validated_event_map(p_data jsonb,p_current jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare v_show boolean; v_lat double precision; v_lon double precision;
begin
 if (p_data ? 'show_on_map' and jsonb_typeof(p_data->'show_on_map') is distinct from 'boolean')
 or (p_data ? 'map_latitude' and jsonb_typeof(p_data->'map_latitude') not in ('number','null'))
 or (p_data ? 'map_longitude' and jsonb_typeof(p_data->'map_longitude') not in ('number','null')) then
 raise exception 'invalid_map_point' using errcode='22023'; end if;
 v_show:=case when p_data ? 'show_on_map' then (p_data->>'show_on_map')::boolean else coalesce((p_current->>'show_on_map')::boolean,false) end;
 v_lat:=(case when p_data ? 'map_latitude' then p_data->>'map_latitude' else p_current->>'map_latitude' end)::double precision;
 v_lon:=(case when p_data ? 'map_longitude' then p_data->>'map_longitude' else p_current->>'map_longitude' end)::double precision;
 if (v_lat is null)<>(v_lon is null) or v_show and v_lat is null
 or v_lat not between -90 and 90 or v_lon not between -180 and 180 then
 raise exception 'invalid_map_point' using errcode='22023'; end if;
 return jsonb_build_object('show_on_map',v_show,'map_latitude',v_lat,'map_longitude',v_lon);
end $$;
revoke all on function app_private.validated_event_map(jsonb,jsonb) from public,anon,authenticated;

create or replace function public.save_scope_content(p_kind text,p_id uuid,p_parish uuid,p_youth uuid,p_data jsonb,p_expected text,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_post public.posts; v_event public.events; v_room public.chat_rooms; v_found boolean; v_title text; v_body text; v_status text; v_visibility text; v_map jsonb;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or p_parish is null or p_data is null or jsonb_typeof(p_data)<>'object' or p_kind is null or p_kind not in ('posts','events','chats') then raise exception 'invalid_content' using errcode='22023'; end if;
 if p_youth is not null and not exists(select 1 from public.youth_groups g where g.id=p_youth and g.parish_id=p_parish) then raise exception 'invalid_scope' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,12));
 v_title=btrim(p_data->>'title'); v_body=coalesce(p_data->>'body',''); v_status=p_data->>'status'; v_visibility=p_data->>'visibility';
 if v_title is null or length(v_title) not between 1 and 200 then raise exception 'invalid_content' using errcode='22023'; end if;
 if p_kind='posts' then
 if not app_private.has_scope_permission('posts.manage',p_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(v_body)>30000 or v_status is null or v_status not in ('draft','published','archived') or v_visibility is null or v_visibility not in ('public','parish') then raise exception 'invalid_content' using errcode='22023'; end if;
 select * into v_post from public.posts where id=p_id for update; v_found=found;
 if v_found then
 if v_post.parish_id<>p_parish or v_post.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_post.author_id<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_post.title=v_title and v_post.body=v_body and v_post.status=v_status and v_post.visibility=v_visibility then return p_id; end if;
 if p_expected is null or v_post.updated_at is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.posts set title=v_title,body=v_body,status=v_status,visibility=v_visibility,published_at=case when v_status='published' then coalesce(published_at,now()) else published_at end where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.posts(id,parish_id,youth_id,author_id,title,body,status,visibility,published_at) values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,v_status,v_visibility,case when v_status='published' then now() else null end);
 end if;
 elsif p_kind='events' then
 select * into v_event from public.events where id=p_id for update; v_found=found;
 if not(app_private.has_scope_permission('events.manage',p_parish,p_youth) or app_private.has_scope_permission(case when v_found and p_expected is not null then 'events.edit' else 'events.create' end,p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 v_map:=app_private.validated_event_map(p_data,case when v_found then to_jsonb(v_event) else '{}'::jsonb end);
 if length(v_body)>10000 or v_status is null or v_status not in ('draft','published','cancelled','archived') or v_visibility is null or v_visibility not in ('public','parish')
 or p_data->>'starts_at' is null or p_data->>'ends_at' is null or (p_data->>'ends_at')::timestamptz<=(p_data->>'starts_at')::timestamptz
 or not isfinite((p_data->>'starts_at')::timestamptz) or not isfinite((p_data->>'ends_at')::timestamptz) or length(coalesce(p_data->>'location',''))>500 then raise exception 'invalid_content' using errcode='22023'; end if;
 if v_status='archived' and not(app_private.has_scope_permission('events.delete',p_parish,p_youth) or app_private.has_scope_permission('events.manage',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if v_found then
 if v_event.parish_id<>p_parish or v_event.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_event.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_event.title=v_title and v_event.description=v_body and v_event.status=v_status and v_event.visibility=v_visibility and v_event.starts_at=(p_data->>'starts_at')::timestamptz and v_event.ends_at=(p_data->>'ends_at')::timestamptz and v_event.location_label=coalesce(p_data->>'location','') and (v_event.show_on_map,v_event.map_latitude,v_event.map_longitude) is not distinct from ((v_map->>'show_on_map')::boolean,(v_map->>'map_latitude')::double precision,(v_map->>'map_longitude')::double precision) then return p_id; end if;
 if p_expected is null or v_event.updated_at is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.events set title=v_title,description=v_body,status=v_status,visibility=v_visibility,starts_at=(p_data->>'starts_at')::timestamptz,ends_at=(p_data->>'ends_at')::timestamptz,location_label=coalesce(p_data->>'location',''),show_on_map=(v_map->>'show_on_map')::boolean,map_latitude=(v_map->>'map_latitude')::double precision,map_longitude=(v_map->>'map_longitude')::double precision where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.events(id,parish_id,youth_id,created_by,title,description,status,visibility,starts_at,ends_at,location_label,show_on_map,map_latitude,map_longitude)
 values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,v_status,v_visibility,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,coalesce(p_data->>'location',''),(v_map->>'show_on_map')::boolean,(v_map->>'map_latitude')::double precision,(v_map->>'map_longitude')::double precision);
 end if;
 else
 select * into v_room from public.chat_rooms where id=p_id for update; v_found=found;
 if not app_private.has_scope_permission(case when v_found and p_expected is not null then 'chats.manage' else 'chats.create' end,p_parish,p_youth) then raise exception 'forbidden' using errcode='42501'; end if;
 if length(v_title)>100 or length(v_body)>300 or coalesce(p_data->>'kind','') not in ('group','channel') or coalesce(p_data->>'access','') not in ('parish','active')
 or p_data->>'access'='active' and p_youth is null or p_data->>'sort_order' is null or (p_data->>'sort_order')::integer not between 0 and 10000 or p_data->>'is_archived' is null then raise exception 'invalid_content' using errcode='22023'; end if;
 if v_found then
 if v_room.parish_id<>p_parish or v_room.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_room.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_room.title=v_title and v_room.description=v_body and v_room.kind=p_data->>'kind' and (v_room.access='restricted' or v_room.access=p_data->>'access') and v_room.sort_order=(p_data->>'sort_order')::integer and v_room.is_archived=(p_data->>'is_archived')::boolean then return p_id; end if;
 if p_expected is null or v_room.revision is distinct from p_expected::bigint then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.chat_rooms set title=v_title,description=v_body,kind=p_data->>'kind',access=case when access='restricted' then access else p_data->>'access' end,
 sort_order=(p_data->>'sort_order')::integer,is_archived=(p_data->>'is_archived')::boolean where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.chat_rooms(id,parish_id,youth_id,created_by,title,description,kind,access,sort_order,is_archived)
 values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,p_data->>'kind',p_data->>'access',(p_data->>'sort_order')::integer,(p_data->>'is_archived')::boolean);
 end if;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'content.save',p_kind,p_id,p_parish,jsonb_build_object('youth',p_youth));
 return p_id;
end $$;

create or replace function public.save_club_information(p_youth uuid,p_id uuid,p_kind text,p_data jsonb,p_expected timestamptz,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups; old_time timestamptz; v_found boolean; v_title text; v_body text; v_creator uuid; v_map jsonb;
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
 select to_jsonb(e) into v_map from public.events e where e.id=p_id;
 v_map:=app_private.validated_event_map(p_data,coalesce(v_map,'{}'::jsonb));
 insert into public.events(id,parish_id,youth_id,created_by,title,description,status,starts_at,ends_at,location_label,club_section,show_on_map,map_latitude,map_longitude)
 values(p_id,g.parish_id,p_youth,auth.uid(),v_title,v_body,'published',(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,coalesce(p_data->>'location',''),p_kind,(v_map->>'show_on_map')::boolean,(v_map->>'map_latitude')::double precision,(v_map->>'map_longitude')::double precision)
 on conflict(id)do update set title=excluded.title,description=excluded.description,starts_at=excluded.starts_at,ends_at=excluded.ends_at,location_label=excluded.location_label,show_on_map=excluded.show_on_map,map_latitude=excluded.map_latitude,map_longitude=excluded.map_longitude;
 end if;
 return p_id;
end $$;

-- This RPC deliberately uses the caller's RLS, including guest and club restrictions.
create or replace function public.map_events_today()
returns table(id uuid,title text,location_label text,starts_at timestamptz,map_latitude double precision,map_longitude double precision,time_label text)
language sql stable security invoker set search_path='' as $$
 select e.id,e.title,e.location_label,e.starts_at,e.map_latitude,e.map_longitude,
 to_char(e.starts_at at time zone 'Europe/Kaliningrad','HH24:MI')
 from public.events e
 where e.show_on_map and e.status='published' and e.map_latitude is not null and e.map_longitude is not null
 and e.starts_at >= (date_trunc('day',now() at time zone 'Europe/Kaliningrad') at time zone 'Europe/Kaliningrad')
 and e.starts_at < ((date_trunc('day',now() at time zone 'Europe/Kaliningrad') + interval '1 day') at time zone 'Europe/Kaliningrad')
 order by e.starts_at,e.id limit 100;
$$;
revoke all on function public.map_events_today() from public;
grant execute on function public.map_events_today() to anon,authenticated;
-- CREATE OR REPLACE retains the original save RPC grants and SECURITY DEFINER guards.
notify pgrst, 'reload schema';
commit;
