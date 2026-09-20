begin;
select pg_advisory_xact_lock(120010);
-- Reuses youth_groups, chat_rooms, chat_messages, events and help_requests.
-- No new roles, communities, or membership entities.
alter table public.chat_rooms add column if not exists deleted_at timestamptz;
alter table public.help_requests add column if not exists youth_id uuid;
do $fk$ begin
 if not exists(select 1 from pg_constraint where conname='help_youth_parish_fk') then
  alter table public.help_requests add constraint help_youth_parish_fk foreign key(youth_id,parish_id) references public.youth_groups(id,parish_id);
 end if;
end $fk$;
create index if not exists help_youth_feed on public.help_requests(youth_id,created_at desc,id);
drop policy if exists help_read on public.help_requests;
create policy help_read on public.help_requests for select to anon,authenticated using(
 (status in ('published','fulfilled') and app_private.can_read_scope_content(parish_id,youth_id,visibility))
 or app_private.has_scope_permission('help.manage',parish_id,youth_id));
-- Existing managers can associate existing help records with a club. RLS and
-- the composite FK prevent access outside the assigned club.
grant insert(youth_id),update(youth_id) on public.help_requests to authenticated;
drop policy if exists help_insert on public.help_requests;
drop policy if exists help_update on public.help_requests;
create policy help_insert on public.help_requests for insert to authenticated with check(author_id=auth.uid() and app_private.has_scope_permission('help.manage',parish_id,youth_id));
create policy help_update on public.help_requests for update to authenticated using(app_private.has_scope_permission('help.manage',parish_id,youth_id)) with check(app_private.has_scope_permission('help.manage',parish_id,youth_id));
create or replace function app_private.can_read_room(p_room uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.chat_rooms r where r.id=p_room and r.deleted_at is null and (
 app_private.has_scope_permission('chats.manage',r.parish_id,r.youth_id) or
 (app_private.has_scope_permission('chat.read',r.parish_id,r.youth_id) and
 (r.youth_id is null or app_private.is_youth_member(r.youth_id)) and
 (r.access='parish' or r.access='restricted' and exists(select 1 from public.chat_members m where m.room_id=r.id and m.user_id=auth.uid())
 or r.access='active' and (app_private.has_scope_permission('youth.active.manage',r.parish_id,r.youth_id)
 or exists(select 1 from public.youth_memberships m where m.youth_id=r.youth_id and m.user_id=auth.uid() and m.is_member and m.is_activist))))));
$$;

create or replace function app_private.protect_deleted_chat() returns trigger
language plpgsql set search_path='' as $$
begin
 if old.deleted_at is not null and new is distinct from old then raise exception 'chat_unavailable' using errcode='22023'; end if;
 return new;
end $$;
drop trigger if exists aa_protect_deleted_chat on public.chat_rooms;
create trigger aa_protect_deleted_chat before update on public.chat_rooms for each row execute function app_private.protect_deleted_chat();

create or replace function public.club_dashboard(p_youth uuid,p_reads jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare g public.youth_groups; v_club jsonb; v_rooms jsonb; v_events jsonb; v_help jsonb; v_joined timestamptz;
begin
 select * into g from public.youth_groups where id=p_youth and not is_archived;
 if not found or auth.uid() is null or not app_private.has_scope_permission('parish.read',g.parish_id,g.id) then raise exception 'forbidden' using errcode='42501'; end if;
 if p_reads is null or jsonb_typeof(p_reads)<>'object' then raise exception 'invalid_cursor' using errcode='22023'; end if;
 select m.updated_at into v_joined from public.youth_memberships m where m.youth_id=g.id and m.user_id=auth.uid() and m.is_member;
 v_joined:=coalesce(v_joined,g.created_at);
 select jsonb_build_object('id',g.id,'parish_id',g.parish_id,'name',g.name,'description',g.description,'address',p.address,'city',c.name,
  'leaders',coalesce((select string_agg(distinct pr.display_name,', ' order by pr.display_name)
   from app_private.role_assignments a join app_private.roles r on r.id=a.role_id join public.profiles pr on pr.id=a.user_id
   join public.youth_memberships m on m.user_id=a.user_id and m.youth_id=g.id and m.is_member
   where a.youth_id=g.id and r.key in ('youth_leader','youth_admin') and (a.expires_at is null or a.expires_at>now())
   and not app_private.is_restricted_guest(a.user_id)),'')) into v_club
 from public.parishes p join public.cities c on c.id=p.city_id where p.id=g.parish_id;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.sort_order,t.title,t.id),'[]') into v_rooms from(
  select r.*, (select max(m.created_at) from public.chat_messages m where m.room_id=r.id and m.deleted_at is null) last_message_at,
   (select count(*)::int from public.chat_messages m where m.room_id=r.id and m.deleted_at is null and m.author_id<>auth.uid()
    and m.created_at>case when p_reads->>r.id::text is not null then least((p_reads->>r.id::text)::timestamptz,now()) else v_joined end) unread_count
  from public.chat_rooms r where r.youth_id=g.id and not r.is_archived and r.deleted_at is null and app_private.can_read_room(r.id)
 )t;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.starts_at,t.id),'[]') into v_events from(
  select e.id,e.title,e.description,e.starts_at,e.ends_at,e.location_label,e.status
  from public.events e where e.youth_id=g.id and e.status in ('published','cancelled') and e.ends_at>=now()
  and (app_private.can_read_scope_content(e.parish_id,e.youth_id,e.visibility) or app_private.has_scope_permission('events.manage',g.parish_id,g.id))
  order by e.starts_at,e.id limit 100
 )t;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc,t.id),'[]') into v_help from(
  select h.id,h.title,h.description,h.created_at,h.status from public.help_requests h
  where h.youth_id=g.id and h.status in ('published','fulfilled')
  and (app_private.can_read_scope_content(h.parish_id,h.youth_id,h.visibility) or app_private.has_scope_permission('help.manage',g.parish_id,g.id))
  order by h.created_at desc,h.id limit 100
 )t;
 return jsonb_build_object('club',v_club,'chats',v_rooms,'events',v_events,'help',v_help,
  'can_create_chats',app_private.has_scope_permission('chats.create',g.parish_id,g.id),
  'can_manage_chats',app_private.has_scope_permission('chats.manage',g.parish_id,g.id));
end $$;

create or replace function public.save_club_chat(p_youth uuid,p_id uuid,p_title text,p_description text,p_icon text,p_kind text,p_access text,p_sort integer,p_revision bigint,p_expected_user uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups; v public.chat_rooms; v_found boolean;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 select * into g from public.youth_groups where id=p_youth and not is_archived;
 if not found then raise exception 'club_unavailable' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,12));
 select * into v from public.chat_rooms where id=p_id for update;v_found:=found;
 if not app_private.has_scope_permission(case when v_found and p_revision is not null then 'chats.manage' else 'chats.create' end,g.parish_id,g.id) then raise exception 'forbidden' using errcode='42501'; end if;
 if v_found and (v.youth_id is distinct from g.id or v.deleted_at is not null) then raise exception 'chat_unavailable' using errcode='22023'; end if;
 if p_icon is null or p_icon not in ('auto','chat','announcements','news','book','games','location','rules','help','sport','craft','music','prayer','family') then raise exception 'invalid_chat' using errcode='22023'; end if;
 -- Validate icon edits against the same revision as all other room fields.
 if v_found and p_revision is null and v.created_by<>auth.uid() then raise exception 'edit_conflict' using errcode='40001'; end if;
 if v_found and v.icon_key is distinct from p_icon and (p_revision is null or v.revision is distinct from p_revision) then raise exception 'edit_conflict' using errcode='40001'; end if;
 perform public.save_scope_content('chats',p_id,g.parish_id,g.id,jsonb_build_object(
 'title',p_title,'body',p_description,'kind',p_kind,'access',p_access,'sort_order',p_sort,'is_archived',false),p_revision::text,p_expected_user);
 if not v_found or v.icon_key is distinct from p_icon then update public.chat_rooms set icon_key=p_icon where id=p_id; end if;
 return p_id;
end $$;

create or replace function public.delete_club_chat(p_youth uuid,p_room uuid,p_revision bigint,p_expected_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups; r public.chat_rooms;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(120010);
 select * into g from public.youth_groups where id=p_youth and not is_archived;
 if not found or not app_private.has_scope_permission('chats.manage',g.parish_id,g.id) then raise exception 'forbidden' using errcode='42501'; end if;
 select * into r from public.chat_rooms where id=p_room and youth_id=g.id for update;
 if not found then raise exception 'chat_unavailable' using errcode='22023'; end if;
 if r.deleted_at is not null then return; end if;
 if p_revision is null or r.revision is distinct from p_revision then raise exception 'edit_conflict' using errcode='40001'; end if;
 delete from public.chat_pins where room_id=r.id;
 update public.chat_rooms set deleted_at=now(),is_archived=true where id=r.id;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id,metadata)
 values(auth.uid(),'chat.delete','chat_room',r.id,r.parish_id,jsonb_build_object('youth',g.id));
end $$;

-- One-time initial chat set. Stable IDs preserve renamed/deleted rooms when
-- installing again. Existing matching chats, their messages and access stay intact.
create or replace function app_private.seed_club_chat_layout(p_youth uuid) returns void
language plpgsql security definer set search_path='' as $$
declare g public.youth_groups; v record;
begin
 select * into strict g from public.youth_groups where id=p_youth;
 for v in select * from(values
('chat','Болталка','Свободное общение участников','group',1),
('announcements','Объявления','Важные объявления клуба','channel',2),
('news','Важные новости','Главные новости и обновления','channel',3),
('book','Полезные материалы','Статьи, ссылки и рекомендации','channel',4),
('games','Настольный клуб','Встречи и игры по интересам','group',5),
('location','Навигация','Как добраться и где что находится','channel',6),
('rules','Правила','Правила общения и поведения','channel',7),
('help','Помощь в воскресной школе','Нужна помощь на занятиях','group',8),
('sport','Спортклуб','Совместные тренировки и игры','group',9),
('craft','Рукоделие','Творческие встречи и мастер-классы','group',10),
('music','Молодёжный хор','Репетиции и набор участников','group',11),
('prayer','Общая молитва','Совместные молитвенные просьбы','group',12),
('family','Клуб молодых семей','Общение и встречи семей','group',13)
 )as defaults(icon,title,description,kind,ordering) loop
  if not exists(select 1 from public.chat_rooms r where r.youth_id=g.id and
   (r.id=md5(g.id::text||':club-reference:'||v.icon)::uuid or lower(btrim(r.title))=lower(v.title))) then
   insert into public.chat_rooms(id,parish_id,youth_id,title,description,kind,access,icon_key,sort_order,created_by)
   values(md5(g.id::text||':club-reference:'||v.icon)::uuid,g.parish_id,g.id,v.title,v.description,v.kind,'parish',v.icon,v.ordering,g.created_by);
  end if;
 end loop;
end $$;
create or replace function app_private.club_chat_layout_on_create() returns trigger
language plpgsql security definer set search_path='' as $$
begin perform app_private.seed_club_chat_layout(new.id);return new;end $$;
drop trigger if exists youth_reference_chats on public.youth_groups;
create trigger youth_reference_chats after insert on public.youth_groups for each row execute function app_private.club_chat_layout_on_create();
do $existing$ declare g record; begin
 for g in select id from public.youth_groups where not is_archived loop perform app_private.seed_club_chat_layout(g.id);end loop;
end $existing$;
revoke all on function app_private.protect_deleted_chat(),app_private.seed_club_chat_layout(uuid),app_private.club_chat_layout_on_create() from public,anon,authenticated;
revoke all on function public.club_dashboard(uuid,jsonb),public.save_club_chat(uuid,uuid,text,text,text,text,text,integer,bigint,uuid),public.delete_club_chat(uuid,uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function public.club_dashboard(uuid,jsonb),public.save_club_chat(uuid,uuid,text,text,text,text,text,integer,bigint,uuid),public.delete_club_chat(uuid,uuid,bigint,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
