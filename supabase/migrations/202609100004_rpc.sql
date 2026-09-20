begin;
create function public.my_permissions(p_parish uuid default null) returns table(permission_key text)
language sql stable security definer set search_path='' as $$
 select key from app_private.permissions where app_private.has_permission(key,p_parish);
$$;
create function public.my_private_profile() returns table(given_name text,family_name text,birth_date date)
language sql stable security definer set search_path='' as $$
 select given_name,family_name,birth_date from app_private.profile_private
 where user_id=auth.uid() and app_private.has_permission('profile.self');
$$;
create function public.update_private_profile(p_given_name text,p_family_name text,p_birth_date date default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.has_permission('profile.self') then raise exception 'forbidden' using errcode='42501'; end if;
 if p_birth_date>current_date or p_birth_date<date '1900-01-01' then raise exception 'invalid_birth_date' using errcode='22023'; end if;
 update app_private.profile_private set given_name=trim(p_given_name),family_name=trim(p_family_name),birth_date=p_birth_date,updated_at=now() where user_id=auth.uid();
end $$;
create function public.request_membership(p_parish uuid) returns public.memberships
language plpgsql security definer set search_path='' as $$
declare v_mode text; v_row public.memberships;
begin
 if auth.uid() is null or not app_private.has_permission('membership.request') then raise exception 'forbidden' using errcode='42501'; end if;
 -- Serialize all membership mutations for one person, including admin decisions.
 perform 1 from public.profiles where id=auth.uid() for update;
 select join_mode into v_mode from public.parishes where id=p_parish and is_published;
 if not found then raise exception 'parish_unavailable' using errcode='22023'; end if;
 if exists(select 1 from public.memberships where user_id=auth.uid() and parish_id=p_parish and status='banned') then
  raise exception 'membership_banned' using errcode='42501'; end if;
 select * into v_row from public.memberships where user_id=auth.uid() and status in ('pending','active');
 if found then
  if v_row.parish_id=p_parish then return v_row; end if;
  raise exception 'membership_already_exists' using errcode='23505';
 end if;
 insert into public.memberships(user_id,parish_id,status) values(auth.uid(),p_parish,case when v_mode='open' then 'active' else 'pending' end) returning * into v_row;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'membership.request','membership',v_row.id,p_parish);
 return v_row;
end $$;
create function public.leave_parish() returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.memberships;
begin
 if auth.uid() is null or not app_private.has_permission('membership.request') then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 update public.memberships set status='left',ended_at=now() where user_id=auth.uid() and status in ('pending','active') returning * into v_row;
 if found then insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'membership.leave','membership',v_row.id,v_row.parish_id); end if;
end $$;
create function public.review_membership(p_membership uuid,p_decision text) returns void
language plpgsql security definer set search_path='' as $$
declare v_row public.memberships;
begin
 select * into v_row from public.memberships where id=p_membership;
 if not found or not app_private.has_permission('memberships.manage',v_row.parish_id) then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=v_row.user_id for update;
 select * into strict v_row from public.memberships where id=p_membership for update;
 if not app_private.has_permission('memberships.manage',v_row.parish_id) then raise exception 'forbidden' using errcode='42501'; end if;
 if not ((v_row.status='pending' and p_decision in ('active','rejected','banned')) or (v_row.status='active' and p_decision in ('left','banned')) or (v_row.status='banned' and p_decision='rejected')) then
  raise exception 'invalid_membership_transition' using errcode='22023'; end if;
 update public.memberships set status=p_decision,reviewed_at=now(),reviewed_by=auth.uid(),
 ended_at=case when p_decision='active' then null else now() end where id=p_membership;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'membership.review','membership',p_membership,v_row.parish_id,jsonb_build_object('decision',p_decision));
end $$;
create function public.grant_role(p_user uuid,p_role text,p_parish uuid default null,p_expires_at timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_role uuid;
begin
 if auth.uid() is null or not app_private.has_permission('roles.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_user for update;
 select id into strict v_role from app_private.roles where key=p_role and baseline is null;
 insert into app_private.role_assignments(user_id,role_id,parish_id,granted_by,expires_at)
 values(p_user,v_role,p_parish,auth.uid(),p_expires_at) returning id into v_id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'role.grant','role_assignment',v_id,p_parish,jsonb_build_object('role',p_role,'user',p_user));
 return v_id;
end $$;
create function public.revoke_role(p_assignment uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.has_permission('roles.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 delete from app_private.role_assignments where id=p_assignment;
 if found then insert into app_private.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'role.revoke','role_assignment',p_assignment); end if;
end $$;
create function public.set_parish_published(p_parish uuid,p_published boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not app_private.has_permission('parishes.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 update public.parishes set is_published=p_published where id=p_parish;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'parish.publish','parish',p_parish,p_parish,jsonb_build_object('published',p_published));
end $$;
create function public.set_chat_member(p_room uuid,p_user uuid,p_add boolean) returns void
language plpgsql security definer set search_path='' as $$
declare v_parish uuid;
begin
 select parish_id into v_parish from public.chat_rooms where id=p_room;
 if not found or not app_private.has_permission('chats.manage',v_parish) then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=p_user for update;
 if p_add then
  if not exists(select 1 from public.memberships where user_id=p_user and parish_id=v_parish and status='active') then raise exception 'active_membership_required' using errcode='23514'; end if;
  insert into public.chat_members(room_id,user_id) values(p_room,p_user) on conflict do nothing;
 else delete from public.chat_members where room_id=p_room and user_id=p_user; end if;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'chat.member','chat_room',p_room,v_parish,jsonb_build_object('user',p_user,'added',p_add));
end $$;
create function public.send_message(p_room uuid,p_body text,p_nonce uuid) returns public.chat_messages
language plpgsql security definer set search_path='' as $$
declare v_room public.chat_rooms; v_message public.chat_messages;
begin
 if auth.uid() is null then raise exception 'forbidden' using errcode='42501'; end if;
 perform 1 from public.profiles where id=auth.uid() for update;
 select * into v_room from public.chat_rooms where id=p_room for share;
 if not found or not app_private.can_read_room(p_room) or v_room.is_archived
 or not app_private.has_permission(case when v_room.kind='channel' then 'channels.publish' else 'chat.send' end,v_room.parish_id) then
  raise exception 'forbidden' using errcode='42501'; end if;
 if p_body is null or length(trim(p_body)) not between 1 and 4000 or p_nonce is null then raise exception 'invalid_message' using errcode='22023'; end if;
 select * into v_message from public.chat_messages where author_id=auth.uid() and client_nonce=p_nonce;
 if found then
  if v_message.room_id<>p_room then raise exception 'nonce_conflict' using errcode='22023'; end if;
  return v_message;
 end if;
 -- Basic per-account pacing. Gateway rate limits are still required at production scale.
 if exists(select 1 from public.chat_messages where author_id=auth.uid() and created_at>clock_timestamp()-interval '1 second') then
  raise exception 'message_rate_limited' using errcode='P0001'; end if;
 insert into public.chat_messages(room_id,author_id,client_nonce,body) values(p_room,auth.uid(),p_nonce,trim(p_body)) returning * into v_message;
 return v_message;
end $$;
create index chat_message_author_recent on public.chat_messages(author_id,created_at desc);
create function public.hide_message(p_message uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_parish uuid;
begin
 select r.parish_id into v_parish from public.chat_messages m join public.chat_rooms r on r.id=m.room_id where m.id=p_message;
 if not found or not app_private.has_permission('chats.moderate',v_parish) then raise exception 'forbidden' using errcode='42501'; end if;
 update public.chat_messages set body='Сообщение удалено',deleted_at=now() where id=p_message;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id) values(auth.uid(),'message.hide','chat_message',p_message,v_parish);
end $$;
create function public.mark_notification_read(p_notification uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'forbidden' using errcode='42501'; end if;
 update public.notifications set read_at=coalesce(read_at,now()) where id=p_notification and user_id=auth.uid();
end $$;

-- Definer RPCs have an explicit allow list; anonymous calls only for the UI permission snapshot.
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.my_permissions(uuid) to anon,authenticated;
grant execute on function public.my_private_profile(), public.update_private_profile(text,text,date),
 public.request_membership(uuid),public.leave_parish(),public.review_membership(uuid,text),
 public.grant_role(uuid,text,uuid,timestamptz),public.revoke_role(uuid),public.set_parish_published(uuid,boolean),
 public.set_chat_member(uuid,uuid,boolean),public.send_message(uuid,text,uuid),public.hide_message(uuid),
 public.mark_notification_read(uuid) to authenticated;
commit;
