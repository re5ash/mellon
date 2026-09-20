begin;
insert into app_private.permissions(key,description,scope) values
 ('public.read','Чтение публичных материалов','both'),
 ('profile.self','Свой профиль','global'),
 ('membership.request','Вступить или выйти','global'),
 ('parish.read','Материалы своего прихода','parish'),
 ('chat.read','Чтение доступных чатов','parish'),
 ('chat.send','Сообщения в групповых чатах','parish'),
 ('help.respond','Отклик на помощь','parish'),
 ('events.attend','Участие в событиях','parish'),
 ('parishes.manage','Создание и публикация приходов','global'),
 ('parish.manage','Редактирование своего прихода','parish'),
 ('memberships.read','Список членства','parish'),
 ('memberships.manage','Одобрение и исключение участников','parish'),
 ('posts.manage','Управление публикациями','parish'),
 ('events.manage','Управление событиями','parish'),
 ('help.manage','Модерация помощи','parish'),
 ('chats.manage','Создание и настройка чатов','parish'),
 ('chats.moderate','Модерация сообщений','parish'),
 ('channels.publish','Публикация в каналах','parish'),
 ('roles.manage','Роли, права и назначения','global'),
 ('audit.read','Журнал управления','both');
insert into app_private.roles(key,title,scope,baseline) values
 ('guest','Гость','global','guest'), ('user','Пользователь','global','authenticated'),
 ('parish_admin','Администратор прихода','parish',null),('super_admin','Суперадминистратор','global',null);
insert into app_private.role_permissions
 select r.id,p.key from app_private.roles r cross join app_private.permissions p
 where (r.key='guest' and p.key='public.read')
 or (r.key='user' and p.key in ('public.read','profile.self','membership.request','parish.read','chat.read','chat.send','help.respond','events.attend'))
 or (r.key='parish_admin' and p.scope in ('parish','both'))
 or r.key='super_admin';

create function app_private.is_member(p_parish uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.memberships m
 where m.user_id=auth.uid() and m.parish_id=p_parish and m.status='active');
$$;
create function app_private.has_permission(p_key text,p_parish uuid default null) returns boolean
language sql stable security definer set search_path='' as $$
 select exists (
  select 1 from app_private.permissions p
  join app_private.role_permissions rp on rp.permission_key=p.key
  join app_private.roles r on r.id=rp.role_id
  where p.key=p_key
    and (p.scope='both' or (p.scope='global' and p_parish is null) or (p.scope='parish' and p_parish is not null))
    and (
     (r.baseline=case when auth.uid() is null then 'guest' else 'authenticated' end
       and (p.scope<>'parish' or app_private.is_member(p_parish)))
     or exists(select 1 from app_private.role_assignments a
       where a.role_id=r.id and a.user_id=auth.uid() and (a.expires_at is null or a.expires_at>now())
       and ((r.scope='global' and a.parish_id is null)
         or (r.scope='parish' and a.parish_id=p_parish and app_private.is_member(p_parish))))
    )
 );
$$;
create function app_private.parish_public(p_parish uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.parishes where id=p_parish and is_published);
$$;
create function app_private.can_read_content(p_parish uuid,p_visibility text) returns boolean
language sql stable security definer set search_path='' as $$
 select (p_visibility='public' and app_private.parish_public(p_parish) and app_private.has_permission('public.read',p_parish))
 or (app_private.is_member(p_parish) and app_private.has_permission('parish.read',p_parish));
$$;
create function app_private.can_read_room(p_room uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_rooms r where r.id=p_room and
  (app_private.has_permission('chats.manage',r.parish_id) or
   (app_private.is_member(r.parish_id) and app_private.has_permission('chat.read',r.parish_id)
     and (r.access='parish' or exists(select 1 from public.chat_members m where m.room_id=r.id and m.user_id=auth.uid())))));
$$;
create function app_private.can_see_profile(p_user uuid,p_visibility text) returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid()=p_user or (p_visibility='parish' and exists(
  select 1 from public.memberships m where m.user_id=p_user and m.status='active' and app_private.is_member(m.parish_id)));
$$;
create function app_private.validate_role_assignment() returns trigger
language plpgsql security definer set search_path='' as $$
declare r app_private.roles;
begin
 select * into strict r from app_private.roles where id=new.role_id;
 if r.baseline is not null or (r.scope='global')<>(new.parish_id is null) then
  raise exception 'invalid_role_scope' using errcode='23514';
 end if;
 if new.parish_id is not null and not exists(select 1 from public.memberships
  where user_id=new.user_id and parish_id=new.parish_id and status='active') then
  raise exception 'active_membership_required' using errcode='23514';
 end if;
 return new;
end $$;
create trigger validate_role_assignment before insert or update on app_private.role_assignments
 for each row execute function app_private.validate_role_assignment();
create function app_private.on_membership_end() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if old.status='active' and new.status<>'active' then
  delete from app_private.role_assignments where user_id=new.user_id and parish_id=new.parish_id;
  delete from public.chat_members where user_id=new.user_id and room_id in
   (select id from public.chat_rooms where parish_id=new.parish_id);
 end if;
 return new;
end $$;
create trigger membership_end after update on public.memberships for each row execute function app_private.on_membership_end();
create function app_private.set_updated_at() returns trigger
language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
do $$ declare t text; begin
 foreach t in array array['parishes','profiles','posts','events','help_requests'] loop
  execute format('create trigger set_updated_at before update on public.%I for each row execute function app_private.set_updated_at()',t);
 end loop;
end $$;
create function app_private.on_signup() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 -- Never accept roles, permissions, parish or membership from user metadata.
 insert into public.profiles(id) values(new.id);
 insert into app_private.profile_private(user_id) values(new.id);
 return new;
end $$;
create trigger on_signup after insert on auth.users for each row execute function app_private.on_signup();

-- Explicit policy helper privileges; no blanket EXECUTE on internal functions.
grant usage on schema app_private to anon,authenticated;
grant execute on function app_private.is_member(uuid),app_private.has_permission(text,uuid),
 app_private.parish_public(uuid),app_private.can_read_content(uuid,text),
 app_private.can_read_room(uuid),app_private.can_see_profile(uuid,text) to anon,authenticated;
commit;
