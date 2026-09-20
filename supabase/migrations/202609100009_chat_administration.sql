begin;

alter table public.chat_rooms
 add column description text not null default '' check(length(description)<=300),
 add column icon_key text not null default 'auto' check(icon_key in ('auto','chat','announcements','news','book','games','location','rules','help','sport','craft','music','prayer','family')),
 add column sort_order integer not null default 100 check(sort_order between 0 and 10000),
 add column revision bigint not null default 1 check(revision>0);
create index chat_rooms_order on public.chat_rooms(parish_id,sort_order,title,id);
create function app_private.chat_revision() returns trigger
language plpgsql set search_path='' as $$
begin new.revision=old.revision+1; return new; end $$;
revoke all on function app_private.chat_revision() from public,anon,authenticated;
create trigger chat_rooms_revision before update on public.chat_rooms
 for each row execute function app_private.chat_revision();
-- All writes now pass through the validated, revision-aware RPC.
revoke insert(parish_id,title,kind,access,created_by),update(title,is_archived) on public.chat_rooms from authenticated;

create or replace function public.admin_parishes(p_after uuid default null,p_only uuid default null,p_limit integer default 31)
returns table(id uuid,city_name text,name text,description text,address text,join_mode text,is_published boolean,updated_at timestamptz,permissions text[])
language sql stable security definer set search_path='' as $$
 select p.id,c.name,p.name,p.description,p.address,p.join_mode,p.is_published,p.updated_at,
 array(select k from unnest(array['parish.manage','posts.manage','memberships.manage','chats.manage']) k where app_private.has_permission(k,p.id))
 from public.parishes p join public.cities c on c.id=p.city_id
 where auth.uid() is not null and (p_after is null or p.id>p_after) and (p_only is null or p.id=p_only)
 and (app_private.has_permission('parishes.manage') or app_private.has_permission('parish.manage',p.id)
 or app_private.has_permission('posts.manage',p.id) or app_private.has_permission('memberships.manage',p.id)
 or app_private.has_permission('chats.manage',p.id))
 order by p.id limit greatest(1,least(coalesce(p_limit,31),101));
$$;

create function public.admin_chat_rooms(p_parish uuid,p_after uuid default null,p_only uuid default null,p_limit integer default 21)
returns setof public.chat_rooms language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.has_permission('chats.manage',p_parish) then raise exception 'forbidden' using errcode='42501'; end if;
 return query select r.* from public.chat_rooms r where r.parish_id=p_parish
 and (p_after is null or r.id>p_after) and (p_only is null or r.id=p_only)
 order by r.id limit greatest(1,least(coalesce(p_limit,21),101));
end $$;

create function public.admin_save_chat(p_id uuid,p_parish uuid,p_create boolean,p_title text,p_description text,
 p_kind text,p_icon text,p_sort integer,p_archived boolean,p_expected_revision bigint,p_expected_user uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_room public.chat_rooms; v_actor uuid:=auth.uid();
begin
 if v_actor is null or p_expected_user is distinct from v_actor or not app_private.has_permission('chats.manage',p_parish) then
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
revoke all on function public.admin_chat_rooms(uuid,uuid,uuid,integer),
 public.admin_save_chat(uuid,uuid,boolean,text,text,text,text,integer,boolean,bigint,uuid) from public,anon,authenticated;
grant execute on function public.admin_chat_rooms(uuid,uuid,uuid,integer),
 public.admin_save_chat(uuid,uuid,boolean,text,text,text,text,integer,boolean,bigint,uuid) to authenticated;
commit;
