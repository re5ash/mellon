begin;
grant usage on schema public to anon,authenticated;
grant select on public.cities,public.parishes,public.parish_locations,public.posts,public.events,public.help_requests to anon,authenticated;
grant select on public.profiles,public.memberships,public.event_attendees,public.help_responses,
 public.chat_rooms,public.chat_members,public.chat_messages,public.notifications to authenticated;
create policy cities_read on public.cities for select to anon,authenticated using(app_private.has_permission('public.read'));
create policy parishes_read on public.parishes for select to anon,authenticated using(
 (is_published and app_private.has_permission('public.read')) or app_private.is_member(id)
 or app_private.has_permission('parish.manage',id) or app_private.has_permission('parishes.manage'));
grant insert(city_id,slug,name,description,address,latitude,longitude,join_mode,is_published) on public.parishes to authenticated;
grant update(name,description,address,latitude,longitude,join_mode) on public.parishes to authenticated;
create policy parishes_insert on public.parishes for insert to authenticated with check(app_private.has_permission('parishes.manage'));
create policy parishes_update on public.parishes for update to authenticated
 using(app_private.has_permission('parish.manage',id)) with check(app_private.has_permission('parish.manage',id));
create policy locations_read on public.parish_locations for select to anon,authenticated using(
 app_private.can_read_content(parish_id,'public') or app_private.is_member(parish_id) or app_private.has_permission('parish.manage',parish_id));
grant insert(parish_id,name,address,latitude,longitude),update(name,address,latitude,longitude) on public.parish_locations to authenticated;
create policy locations_insert on public.parish_locations for insert to authenticated with check(app_private.has_permission('parish.manage',parish_id));
create policy locations_update on public.parish_locations for update to authenticated
 using(app_private.has_permission('parish.manage',parish_id)) with check(app_private.has_permission('parish.manage',parish_id));
create policy profiles_read on public.profiles for select to authenticated using(app_private.can_see_profile(id,directory_visibility));
grant update(display_name,directory_visibility) on public.profiles to authenticated;
create policy profiles_update on public.profiles for update to authenticated
 using(id=auth.uid() and app_private.has_permission('profile.self')) with check(id=auth.uid() and app_private.has_permission('profile.self'));
create policy memberships_read on public.memberships for select to authenticated using(
 user_id=auth.uid() or app_private.has_permission('memberships.read',parish_id));
-- Memberships and messages: no client INSERT/UPDATE/DELETE, only checked RPCs.
create policy posts_read on public.posts for select to anon,authenticated using(
 (status='published' and published_at<=now() and app_private.can_read_content(parish_id,visibility))
 or app_private.has_permission('posts.manage',parish_id));
grant insert(parish_id,author_id,title,body,visibility,status,published_at),update(title,body,visibility,status,published_at) on public.posts to authenticated;
create policy posts_insert on public.posts for insert to authenticated
 with check(author_id=auth.uid() and app_private.has_permission('posts.manage',parish_id));
create policy posts_update on public.posts for update to authenticated
 using(app_private.has_permission('posts.manage',parish_id)) with check(app_private.has_permission('posts.manage',parish_id));
create policy events_read on public.events for select to anon,authenticated using(
 (status in ('published','cancelled') and app_private.can_read_content(parish_id,visibility)) or app_private.has_permission('events.manage',parish_id));
grant insert(parish_id,location_id,title,description,starts_at,ends_at,timezone,visibility,status,created_by),
 update(location_id,title,description,starts_at,ends_at,timezone,visibility,status) on public.events to authenticated;
create policy events_insert on public.events for insert to authenticated with check(created_by=auth.uid() and app_private.has_permission('events.manage',parish_id));
create policy events_update on public.events for update to authenticated using(app_private.has_permission('events.manage',parish_id)) with check(app_private.has_permission('events.manage',parish_id));
create policy attendees_read on public.event_attendees for select to authenticated using(user_id=auth.uid() or exists(
 select 1 from public.events e where e.id=event_id and app_private.has_permission('events.manage',e.parish_id)));
grant insert(event_id,user_id),delete on public.event_attendees to authenticated;
create policy attendees_insert on public.event_attendees for insert to authenticated with check(user_id=auth.uid() and exists(
 select 1 from public.events e where e.id=event_id and e.status='published' and e.ends_at>now()
 and app_private.is_member(e.parish_id) and app_private.has_permission('events.attend',e.parish_id)));
create policy attendees_delete on public.event_attendees for delete to authenticated using(user_id=auth.uid());
create policy help_read on public.help_requests for select to anon,authenticated using(
 (status in ('published','fulfilled') and app_private.can_read_content(parish_id,visibility)) or app_private.has_permission('help.manage',parish_id));
grant insert(parish_id,author_id,title,description,visibility,status),update(title,description,visibility,status) on public.help_requests to authenticated;
create policy help_insert on public.help_requests for insert to authenticated with check(author_id=auth.uid() and app_private.has_permission('help.manage',parish_id));
create policy help_update on public.help_requests for update to authenticated using(app_private.has_permission('help.manage',parish_id)) with check(app_private.has_permission('help.manage',parish_id));
create policy responses_read on public.help_responses for select to authenticated using(user_id=auth.uid() or exists(
 select 1 from public.help_requests h where h.id=request_id and app_private.has_permission('help.manage',h.parish_id)));
grant insert(request_id,user_id,message),delete on public.help_responses to authenticated;
create policy responses_insert on public.help_responses for insert to authenticated with check(user_id=auth.uid() and exists(
 select 1 from public.help_requests h where h.id=request_id and h.status='published'
 and app_private.is_member(h.parish_id) and app_private.has_permission('help.respond',h.parish_id)));
create policy responses_delete on public.help_responses for delete to authenticated using(user_id=auth.uid());
create policy rooms_read on public.chat_rooms for select to authenticated using(app_private.can_read_room(id));
grant insert(parish_id,title,kind,access,created_by),update(title,is_archived) on public.chat_rooms to authenticated;
create policy rooms_insert on public.chat_rooms for insert to authenticated with check(created_by=auth.uid() and app_private.has_permission('chats.manage',parish_id));
create policy rooms_update on public.chat_rooms for update to authenticated using(app_private.has_permission('chats.manage',parish_id)) with check(app_private.has_permission('chats.manage',parish_id));
create policy chat_members_read on public.chat_members for select to authenticated using(app_private.can_read_room(room_id));
create policy messages_read on public.chat_messages for select to authenticated using(app_private.can_read_room(room_id));
create policy notifications_read on public.notifications for select to authenticated using(user_id=auth.uid());
commit;
