begin;
alter table public.chat_rooms add column youth_id uuid, add constraint room_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
alter table public.chat_rooms drop constraint chat_rooms_access_check;
alter table public.chat_rooms add constraint chat_rooms_access_check check(access in ('parish','restricted','active')),
 add constraint active_chat_has_youth check(access<>'active' or youth_id is not null);
alter table public.posts add column youth_id uuid,add constraint post_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
alter table public.events add column youth_id uuid,add column location_label text not null default '' check(length(location_label)<=500),
 add constraint event_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
create index rooms_youth on public.chat_rooms(youth_id,sort_order,id);
create index posts_youth on public.posts(youth_id,published_at desc,id desc);
create index events_youth on public.events(youth_id,starts_at,id);
alter table public.chat_messages add constraint message_room_identity unique(room_id,id);
create table public.chat_pins (
 room_id uuid primary key references public.chat_rooms on delete cascade,
 message_id uuid not null, pinned_by uuid not null references public.profiles,
 pinned_at timestamptz not null default now(), revision bigint not null default 1,
 foreign key(room_id,message_id) references public.chat_messages(room_id,id)
);
alter table public.chat_pins enable row level security;
revoke all on public.chat_pins from public,anon,authenticated;
grant select on public.chat_pins to authenticated;
create policy pins_read on public.chat_pins for select to authenticated using(app_private.can_read_room(room_id));
alter publication supabase_realtime add table public.chat_pins;

create or replace function app_private.can_read_room(p_room uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_rooms r where r.id=p_room and (
 app_private.has_scope_permission('chats.manage',r.parish_id,r.youth_id) or
 (app_private.has_scope_permission('chat.read',r.parish_id,r.youth_id) and
 (r.youth_id is null or app_private.is_youth_member(r.youth_id)) and
 (r.access='parish' or r.access='restricted' and exists(select 1 from public.chat_members m where m.room_id=r.id and m.user_id=auth.uid())
 or r.access='active' and (app_private.has_scope_permission('youth.active.manage',r.parish_id,r.youth_id)
 or exists(select 1 from public.youth_memberships m where m.youth_id=r.youth_id and m.user_id=auth.uid() and m.is_member and m.is_activist))))));
$$;
create function app_private.can_read_scope_content(p_parish uuid,p_youth uuid,p_visibility text) returns boolean
language sql stable security definer set search_path='' as $$
 select case when p_youth is null then app_private.can_read_content(p_parish,p_visibility) else
 exists(select 1 from public.youth_groups g where g.id=p_youth and not g.is_archived and g.parish_id=p_parish
 and ((p_visibility='public' and app_private.parish_public(p_parish)) or app_private.is_youth_member(p_youth))) end;
$$;
drop policy posts_read on public.posts;
create policy posts_read on public.posts for select to anon,authenticated using(
 status='published' and published_at<=now() and app_private.can_read_scope_content(parish_id,youth_id,visibility)
 or app_private.has_scope_permission('posts.manage',parish_id,youth_id));
drop policy events_read on public.events;
create policy events_read on public.events for select to anon,authenticated using(
 status in ('published','cancelled') and app_private.can_read_scope_content(parish_id,youth_id,visibility)
 or app_private.has_scope_permission('events.manage',parish_id,youth_id) or app_private.has_scope_permission('events.edit',parish_id,youth_id));
-- Checked RPCs enforce event archive/delete permissions.
revoke insert,update,delete on public.posts,public.events from authenticated;
revoke insert(parish_id,author_id,title,body,visibility,status,published_at),update(title,body,visibility,status,published_at) on public.posts from authenticated;
revoke insert(parish_id,location_id,title,description,starts_at,ends_at,timezone,visibility,status,created_by),update(location_id,title,description,starts_at,ends_at,timezone,visibility,status) on public.events from authenticated;
drop policy posts_insert on public.posts; drop policy posts_update on public.posts;
create policy posts_insert on public.posts for insert to authenticated with check(author_id=auth.uid() and app_private.has_scope_permission('posts.manage',parish_id,youth_id));
create policy posts_update on public.posts for update to authenticated using(app_private.has_scope_permission('posts.manage',parish_id,youth_id)) with check(app_private.has_scope_permission('posts.manage',parish_id,youth_id));
drop policy events_insert on public.events; drop policy events_update on public.events;
create policy events_insert on public.events for insert to authenticated with check(created_by=auth.uid() and (app_private.has_scope_permission('events.create',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id)));
create policy events_update on public.events for update to authenticated using(app_private.has_scope_permission('events.edit',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id)) with check(app_private.has_scope_permission('events.edit',parish_id,youth_id) or app_private.has_scope_permission('events.manage',parish_id,youth_id));

create or replace function public.send_message(p_room uuid,p_body text,p_nonce uuid) returns public.chat_messages
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms; m public.chat_messages;
begin
 if auth.uid() is null then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into r from public.chat_rooms where id=p_room for share;
 if not found or not app_private.can_read_room(p_room) or r.is_archived
 or not app_private.has_scope_permission(case when r.kind='channel' then 'channels.publish' else 'chat.send' end,r.parish_id,r.youth_id) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_body is null or length(btrim(p_body)) not between 1 and 4000 or p_nonce is null then raise exception 'invalid_message' using errcode='22023'; end if;
 select * into m from public.chat_messages where author_id=auth.uid() and client_nonce=p_nonce;
 if found then
 if m.room_id<>p_room then raise exception 'nonce_conflict' using errcode='22023'; end if;
 return m;
 end if;
 if exists(select 1 from public.chat_messages where author_id=auth.uid() and created_at>clock_timestamp()-interval '1 second') then raise exception 'message_rate_limited' using errcode='P0001'; end if;
 insert into public.chat_messages(room_id,author_id,client_nonce,body) values(p_room,auth.uid(),p_nonce,btrim(p_body)) returning * into m;
 return m;
end $$;
create function public.chat_capabilities(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r public.chat_rooms;
begin
 select * into r from public.chat_rooms where id=p_room;
 if not found or not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 return jsonb_build_object('send',not r.is_archived and app_private.has_scope_permission(case when r.kind='channel' then 'channels.publish' else 'chat.send' end,r.parish_id,r.youth_id),
 'delete_own',app_private.has_scope_permission('messages.delete_own',r.parish_id,r.youth_id),
 'delete_any',app_private.has_scope_permission('messages.delete_any',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id),
 'pin',app_private.has_scope_permission('messages.pin',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id));
end $$;
create function public.delete_chat_message(p_message uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms; m public.chat_messages;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select r0.* into r from public.chat_rooms r0 join public.chat_messages m0 on m0.room_id=r0.id where m0.id=p_message for update of r0;
 if not found or not app_private.can_read_room(r.id) then raise exception 'forbidden' using errcode='42501'; end if;
 select * into m from public.chat_messages where id=p_message for update;
 if not(app_private.has_scope_permission('messages.delete_any',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id)
 or m.author_id=auth.uid() and app_private.has_scope_permission('messages.delete_own',r.parish_id,r.youth_id)) then raise exception 'forbidden' using errcode='42501'; end if;
 if m.deleted_at is not null then return; end if;
 delete from public.chat_pins where room_id=r.id and message_id=m.id;
 update public.chat_messages set body='Сообщение удалено',deleted_at=now() where id=m.id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'message.hide','chat_message',m.id,r.parish_id,jsonb_build_object('youth',r.youth_id,'own',m.author_id=auth.uid()));
end $$;
create or replace function public.hide_message(p_message uuid) returns void
language sql security definer set search_path='' as $$ select public.delete_chat_message(p_message,auth.uid()); $$;
create function public.set_chat_pin(p_room uuid,p_message uuid,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare r public.chat_rooms;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select * into r from public.chat_rooms where id=p_room for update;
 if not found or not app_private.can_read_room(p_room) or not(app_private.has_scope_permission('messages.pin',r.parish_id,r.youth_id) or app_private.has_scope_permission('chats.moderate',r.parish_id,r.youth_id)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_message is null then delete from public.chat_pins where room_id=p_room;
 else
 perform 1 from public.chat_messages where id=p_message and room_id=p_room and deleted_at is null for share;
 if not found then raise exception 'message_unavailable' using errcode='22023'; end if;
 insert into public.chat_pins(room_id,message_id,pinned_by) values(p_room,p_message,auth.uid())
 on conflict(room_id) do update set message_id=excluded.message_id,pinned_by=excluded.pinned_by,pinned_at=now(),revision=chat_pins.revision+1;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),case when p_message is null then 'message.unpin' else 'message.pin' end,'chat_room',r.id,r.parish_id,jsonb_build_object('message',p_message,'youth',r.youth_id));
end $$;
create function public.chat_history(p_room uuid,p_before timestamptz default null,p_before_id uuid default null,p_anchor uuid default null)
returns table(id uuid,room_id uuid,author_id uuid,author_name text,body text,created_at timestamptz,deleted_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
declare v_anchor timestamptz;
begin
 if not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 if (p_before is null)<>(p_before_id is null) then raise exception 'invalid_cursor' using errcode='22023'; end if;
 if p_anchor is not null then
 select m.created_at into v_anchor from public.chat_messages m where m.id=p_anchor and m.room_id=p_room;
 if not found then raise exception 'message_unavailable' using errcode='22023'; end if;
 return query select m.id,m.room_id,m.author_id,p.display_name,m.body,m.created_at,m.deleted_at
 from public.chat_messages m join public.profiles p on p.id=m.author_id
 where m.room_id=p_room and (m.created_at,m.id)<=(v_anchor,p_anchor) order by m.created_at desc,m.id desc limit 50;
 else
 return query select m.id,m.room_id,m.author_id,p.display_name,m.body,m.created_at,m.deleted_at
 from public.chat_messages m join public.profiles p on p.id=m.author_id
 where m.room_id=p_room and (p_before is null or (m.created_at,m.id)<(p_before,p_before_id)) order by m.created_at desc,m.id desc limit 50;
 end if;
end $$;
create function public.current_chat_pin(p_room uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not app_private.can_read_room(p_room) then raise exception 'forbidden' using errcode='42501'; end if;
 return(select jsonb_build_object('message_id',m.id,'body',m.body,'author_name',p.display_name,'pinned_at',cp.pinned_at)
 from public.chat_pins cp join public.chat_messages m on m.id=cp.message_id join public.profiles p on p.id=m.author_id
 where cp.room_id=p_room and m.deleted_at is null);
end $$;
create function app_private.create_active_chat() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.chat_rooms(parish_id,youth_id,title,description,kind,access,icon_key,sort_order,created_by)
 values(new.parish_id,new.id,'Актив','Закрытый чат актива и руководителей','group','active','help',1000,new.created_by);
 return new;
end $$;
create trigger youth_active_chat after insert on public.youth_groups for each row execute function app_private.create_active_chat();

drop policy attendees_insert on public.event_attendees;
create policy attendees_insert on public.event_attendees for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.events e where e.id=event_id and e.status='published' and e.ends_at>now() and app_private.has_scope_permission('events.attend',e.parish_id,e.youth_id)));
drop policy attendees_read on public.event_attendees;
create policy attendees_read on public.event_attendees for select to authenticated using(user_id=auth.uid() or exists(select 1 from public.events e where e.id=event_id and app_private.has_scope_permission('events.manage',e.parish_id,e.youth_id)));
create function public.scope_content(p_kind text,p_parish uuid,p_youth uuid default null,p_after uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_permission text; v_result jsonb;
begin
 v_permission=case p_kind when 'posts' then 'posts.manage' when 'events' then 'events.edit' when 'chats' then 'chats.manage' else null end;
 if v_permission is null or not(app_private.has_scope_permission(v_permission,p_parish,p_youth)
 or p_kind='events' and (app_private.has_scope_permission('events.manage',p_parish,p_youth) or app_private.has_scope_permission('events.create',p_parish,p_youth))
 or p_kind='chats' and app_private.has_scope_permission('chats.create',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='posts' then select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.posts where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) order by id limit 31)t;
 elsif p_kind='events' then select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.events where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) order by id limit 31)t;
 else select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into v_result from(select * from public.chat_rooms where parish_id=p_parish and youth_id is not distinct from p_youth and (p_after is null or id>p_after) and app_private.can_read_room(id) order by id limit 31)t; end if;
 return v_result;
end $$;
create function public.save_scope_content(p_kind text,p_id uuid,p_parish uuid,p_youth uuid,p_data jsonb,p_expected text,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_post public.posts; v_event public.events; v_room public.chat_rooms; v_found boolean; v_title text; v_body text; v_status text; v_visibility text;
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
 if length(v_body)>10000 or v_status is null or v_status not in ('draft','published','cancelled','archived') or v_visibility is null or v_visibility not in ('public','parish')
 or p_data->>'starts_at' is null or p_data->>'ends_at' is null or (p_data->>'ends_at')::timestamptz<=(p_data->>'starts_at')::timestamptz
 or not isfinite((p_data->>'starts_at')::timestamptz) or not isfinite((p_data->>'ends_at')::timestamptz) or length(coalesce(p_data->>'location',''))>500 then raise exception 'invalid_content' using errcode='22023'; end if;
 if v_status='archived' and not(app_private.has_scope_permission('events.delete',p_parish,p_youth) or app_private.has_scope_permission('events.manage',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if v_found then
 if v_event.parish_id<>p_parish or v_event.youth_id is distinct from p_youth then raise exception 'forbidden' using errcode='42501'; end if;
 if p_expected is null and v_event.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_event.title=v_title and v_event.description=v_body and v_event.status=v_status and v_event.visibility=v_visibility and v_event.starts_at=(p_data->>'starts_at')::timestamptz and v_event.ends_at=(p_data->>'ends_at')::timestamptz and v_event.location_label=coalesce(p_data->>'location','') then return p_id; end if;
 if p_expected is null or v_event.updated_at is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.events set title=v_title,description=v_body,status=v_status,visibility=v_visibility,starts_at=(p_data->>'starts_at')::timestamptz,ends_at=(p_data->>'ends_at')::timestamptz,location_label=coalesce(p_data->>'location','') where id=p_id;
 else
 if p_expected is not null then raise exception 'edit_conflict' using errcode='40001'; end if;
 insert into public.events(id,parish_id,youth_id,created_by,title,description,status,visibility,starts_at,ends_at,location_label)
 values(p_id,p_parish,p_youth,auth.uid(),v_title,v_body,v_status,v_visibility,(p_data->>'starts_at')::timestamptz,(p_data->>'ends_at')::timestamptz,coalesce(p_data->>'location',''));
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
create function public.delete_scope_content(p_kind text,p_id uuid,p_parish uuid,p_youth uuid,p_expected text,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_time timestamptz;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user or p_kind is null or p_kind not in ('posts','events')
 or not(app_private.has_scope_permission(case when p_kind='posts' then 'posts.manage' else 'events.delete' end,p_parish,p_youth)
 or p_kind='events' and app_private.has_scope_permission('events.manage',p_parish,p_youth)) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_kind='posts' then
 select updated_at into v_time from public.posts where id=p_id and parish_id=p_parish and youth_id is not distinct from p_youth for update;
 else select updated_at into v_time from public.events where id=p_id and parish_id=p_parish and youth_id is not distinct from p_youth for update; end if;
 if not found then return; end if;
 if p_expected is null or v_time is distinct from p_expected::timestamptz then raise exception 'edit_conflict' using errcode='40001'; end if;
 if p_kind='posts' then delete from public.posts where id=p_id; else delete from public.events where id=p_id; end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata) values(auth.uid(),'content.delete',p_kind,p_id,p_parish,jsonb_build_object('youth',p_youth));
end $$;

create table public.app_configuration (
 id boolean primary key default true check(id), app_name text not null default 'Мой приход' check(length(btrim(app_name)) between 1 and 80),
 welcome_text text not null default 'Вера объединяет людей' check(length(welcome_text)<=500),
 support_email text not null default '' check(length(support_email)<=254), revision bigint not null default 1
);
insert into public.app_configuration(id) values(true);
alter table public.app_configuration enable row level security;
revoke all on public.app_configuration from public,anon,authenticated;
grant select on public.app_configuration to anon,authenticated;
create policy app_configuration_read on public.app_configuration for select to anon,authenticated using(true);
create trigger app_configuration_revision before update on public.app_configuration for each row execute function app_private.chat_revision();
create function public.save_app_configuration(p_name text,p_welcome text,p_email text,p_revision bigint) returns void
language plpgsql security definer set search_path='' as $$
declare v public.app_configuration;
begin
 if not app_private.has_permission('settings.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 if length(btrim(coalesce(p_name,''))) not between 1 and 80 or p_welcome is null or length(p_welcome)>500 or p_email is null or length(p_email)>254
 or p_email<>'' and p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'invalid_settings' using errcode='22023'; end if;
 select * into v from public.app_configuration for update;
 if v.revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 update public.app_configuration set app_name=btrim(p_name),welcome_text=btrim(p_welcome),support_email=btrim(p_email);
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'settings.save','app_configuration',null);
end $$;

-- Youth-only staff do not gain an administration entry for the whole parish.
create or replace function public.admin_parishes(p_after uuid default null,p_only uuid default null,p_limit integer default 31)
returns table(id uuid,city_name text,name text,description text,address text,join_mode text,is_published boolean,updated_at timestamptz,permissions text[])
language sql stable security definer set search_path='' as $$
 select p.id,c.name,p.name,p.description,p.address,p.join_mode,p.is_published,p.updated_at,
 array(select k from unnest(array['parish.manage','posts.manage','memberships.manage','chats.manage','chats.create','events.manage','events.create','events.edit','events.delete','roles.assign','youths.manage']) k where app_private.has_permission(k,p.id))
 from public.parishes p join public.cities c on c.id=p.city_id
 where auth.uid() is not null and (p_after is null or p.id>p_after) and (p_only is null or p.id=p_only)
 and (app_private.has_permission('parishes.manage') or exists(select 1 from unnest(array['parish.manage','posts.manage','memberships.manage','chats.manage','chats.create','events.manage','events.create','events.edit','roles.assign','youths.manage']) k where app_private.has_permission(k,p.id)))
 order by p.id limit greatest(1,least(coalesce(p_limit,31),101));
$$;
-- New RPCs and internal helpers do not inherit PostgreSQL's PUBLIC execute default.
do $privileges$
declare fn record;
begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname in ('app_private.can_read_scope_content','public.chat_capabilities','public.delete_chat_message','public.set_chat_pin','public.chat_history','public.current_chat_pin','app_private.create_active_chat','public.scope_content','public.save_scope_content','public.delete_scope_content','public.save_app_configuration') loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $privileges$;
grant execute on function app_private.can_read_scope_content(uuid,uuid,text) to anon,authenticated;
grant execute on function public.chat_capabilities(uuid),public.delete_chat_message(uuid,uuid),public.set_chat_pin(uuid,uuid,uuid),public.chat_history(uuid,timestamptz,uuid,uuid),public.current_chat_pin(uuid),
 public.scope_content(text,uuid,uuid,uuid),public.save_scope_content(text,uuid,uuid,uuid,jsonb,text,uuid),public.delete_scope_content(text,uuid,uuid,uuid,text,uuid),public.save_app_configuration(text,text,text,bigint) to authenticated;
create or replace function public.admin_save_chat(p_id uuid,p_parish uuid,p_create boolean,p_title text,p_description text,
 p_kind text,p_icon text,p_sort integer,p_archived boolean,p_expected_revision bigint,p_expected_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.chat_rooms; v_actor uuid:=auth.uid();
begin
 if v_actor is null or p_expected_user is distinct from v_actor or not app_private.has_permission('chats.manage',p_parish) or (p_create and not app_private.has_permission('chats.create',p_parish)) then
  raise exception 'forbidden' using errcode='42501'; end if;
 if p_id is null or p_parish is null or p_create is null or p_archived is null
 or length(trim(coalesce(p_title,''))) not between 1 and 100 or length(coalesce(p_description,''))>300
 or p_kind is null or p_kind not in ('group','channel') or p_icon is null
 or p_icon not in ('auto','chat','announcements','news','book','games','location','rules','help','sport','craft','music','prayer','family')
 or p_sort is null or p_sort not between 0 and 10000 then raise exception 'invalid_chat' using errcode='22023'; end if;
 if not exists(select 1 from public.parishes where id=p_parish) then raise exception 'parish_unavailable' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
 select * into v_room from public.chat_rooms where id=p_id for update;
 if found then
  if v_room.parish_id<>p_parish then raise exception 'forbidden' using errcode='42501'; end if;
  if p_create and v_room.created_by is distinct from v_actor then raise exception 'edit_conflict' using errcode='40001'; end if;
  if (v_room.title,v_room.description,v_room.kind,v_room.icon_key,v_room.sort_order,v_room.is_archived)
    is not distinct from (trim(p_title),trim(coalesce(p_description,'')),p_kind,p_icon,p_sort,p_archived) then return to_jsonb(v_room); end if;
  if p_create or p_expected_revision is distinct from v_room.revision then raise exception 'edit_conflict' using errcode='40001'; end if;
  -- Keep parish, original author and restricted-room access immutable here.
  update public.chat_rooms set title=trim(p_title),description=trim(coalesce(p_description,'')),kind=p_kind,
    icon_key=p_icon,sort_order=p_sort,is_archived=p_archived where id=p_id returning * into v_room;
 else
  if not p_create then raise exception 'chat_unavailable' using errcode='22023'; end if;
  insert into public.chat_rooms(id,parish_id,title,description,kind,icon_key,sort_order,is_archived,access,created_by)
   values(p_id,p_parish,trim(p_title),trim(coalesce(p_description,'')),p_kind,p_icon,p_sort,p_archived,'parish',v_actor)
   returning * into v_room;
 end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(v_actor,case when p_create then 'chat.create' else 'chat.update' end,'chat_room',p_id,p_parish,
 jsonb_build_object('revision',v_room.revision,'archived',p_archived));
 return to_jsonb(v_room);
end $$;
create or replace function app_private.youth_membership_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.is_member and not exists(select 1 from public.memberships m join public.youth_groups g on g.parish_id=m.parish_id where g.id=new.youth_id and m.user_id=new.user_id and m.status='active' and not g.is_archived) then raise exception 'active_membership_required' using errcode='23514'; end if;
 if tg_op='UPDATE' and old.is_member and not new.is_member then
 delete from app_private.role_assignments where user_id=new.user_id and youth_id=new.youth_id;
 delete from public.chat_members where user_id=new.user_id and room_id in(select id from public.chat_rooms where youth_id=new.youth_id);
 end if; return new;
end $$;
commit;
