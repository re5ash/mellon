begin;

-- Server-owned author identity also makes create retries safe.
alter table public.parishes add column created_by uuid references public.profiles on delete set null;
create index memberships_pending_review on public.memberships(parish_id,requested_at desc,id desc) where status='pending';
create index posts_administration on public.posts(parish_id,created_at desc,id desc);

create function public.admin_parishes(p_after uuid default null, p_only uuid default null, p_limit integer default 31)
returns table(id uuid, city_name text, name text, description text, address text, join_mode text,
  is_published boolean, updated_at timestamptz, permissions text[])
language sql stable security definer set search_path='' as $$
  select p.id, c.name, p.name, p.description, p.address, p.join_mode, p.is_published, p.updated_at,
    array(select k from unnest(array['parish.manage','posts.manage','memberships.manage']) k
      where app_private.has_permission(k,p.id))
  from public.parishes p join public.cities c on c.id=p.city_id
  where auth.uid() is not null and (p_after is null or p.id>p_after) and (p_only is null or p.id=p_only)
    and (app_private.has_permission('parishes.manage') or app_private.has_permission('parish.manage',p.id)
      or app_private.has_permission('posts.manage',p.id) or app_private.has_permission('memberships.manage',p.id))
  order by p.id limit greatest(1,least(coalesce(p_limit,31),101));
$$;

create function public.admin_pending_memberships(p_parish uuid, p_before timestamptz default null,
  p_before_id uuid default null, p_limit integer default 21)
returns table(id uuid, user_id uuid, display_name text, requested_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
  if auth.uid() is null or not app_private.has_permission('memberships.manage',p_parish) then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if (p_before is null)<>(p_before_id is null) then raise exception 'invalid_cursor' using errcode='22023'; end if;
  -- An applicant's display name is available to reviewers. No email, phone, birthday or private profile.
  return query select m.id,m.user_id,p.display_name,m.requested_at
  from public.memberships m join public.profiles p on p.id=m.user_id
  where m.parish_id=p_parish and m.status='pending'
    and (p_before is null or (m.requested_at,m.id)<(p_before,p_before_id))
  order by m.requested_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,21),101));
end $$;

create function public.admin_save_parish(p_id uuid, p_create boolean, p_city_name text, p_name text,
  p_description text, p_address text, p_join_mode text, p_is_published boolean,
  p_expected_updated_at timestamptz default null, p_country_code text default 'RU',
  p_timezone text default 'Europe/Kaliningrad') returns uuid
language plpgsql security definer set search_path='' as $$
declare v_existing public.parishes; v_city uuid;
begin
  if auth.uid() is null or p_create is null or p_id is null then raise exception 'forbidden' using errcode='42501'; end if;
  if (p_create and not app_private.has_permission('parishes.manage')) or
     (not p_create and not app_private.has_permission('parish.manage',p_id)) then
    raise exception 'forbidden' using errcode='42501';
  end if;
  if p_name is null or length(trim(p_name)) not between 1 and 200
    or p_description is null or length(p_description)>10000 or p_address is null or length(p_address)>500
    or p_join_mode is null or p_join_mode not in ('open','approval') or p_is_published is null then
    raise exception 'invalid_parish' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,0));
  select * into v_existing from public.parishes where id=p_id for update;
  if p_create then
    if found then
      if v_existing.created_by is distinct from auth.uid() then raise exception 'forbidden' using errcode='42501'; end if;
      return v_existing.id;
    end if;
    if p_city_name is null or length(trim(p_city_name)) not between 1 and 160
      or p_country_code is null or p_country_code !~ '^[A-Z]{2}$'
      or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone) then
      raise exception 'invalid_city' using errcode='22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(p_country_code||':'||lower(trim(p_city_name)),1));
    select id into v_city from public.cities where country_code=p_country_code and lower(name)=lower(trim(p_city_name)) order by id limit 1;
    if v_city is null then
      insert into public.cities(name,country_code,timezone) values(trim(p_city_name),p_country_code,p_timezone) returning id into v_city;
    end if;
    insert into public.parishes(id,city_id,slug,name,description,address,join_mode,is_published,created_by)
    values(p_id,v_city,'parish-'||replace(p_id::text,'-',''),trim(p_name),trim(p_description),trim(p_address),p_join_mode,p_is_published,auth.uid());
  else
    if not found then raise exception 'parish_unavailable' using errcode='22023'; end if;
    if p_expected_updated_at is null or p_expected_updated_at<>v_existing.updated_at then
      raise exception 'edit_conflict' using errcode='40001';
    end if;
    if p_is_published<>v_existing.is_published and not app_private.has_permission('parishes.manage') then
      raise exception 'forbidden' using errcode='42501';
    end if;
    update public.parishes set name=trim(p_name),description=trim(p_description),address=trim(p_address),
      join_mode=p_join_mode,is_published=p_is_published where id=p_id;
  end if;
  insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id)
  values(auth.uid(),case when p_create then 'parish.create' else 'parish.update' end,'parish',p_id,p_id);
  return p_id;
end $$;

create function public.admin_save_post(p_id uuid, p_parish uuid, p_create boolean, p_title text, p_body text,
  p_visibility text, p_status text, p_expected_updated_at timestamptz default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_existing public.posts;
begin
  if auth.uid() is null or p_id is null or p_create is null
    or not app_private.has_permission('posts.manage',p_parish) then raise exception 'forbidden' using errcode='42501'; end if;
  if p_title is null or length(trim(p_title)) not between 1 and 200
    or p_body is null or length(p_body)>30000
    or p_visibility is null or p_visibility not in ('public','parish')
    or p_status is null or p_status not in ('draft','published','archived') then
    raise exception 'invalid_post' using errcode='22023';
  end if;
  if not exists(select 1 from public.parishes where id=p_parish) then raise exception 'parish_unavailable' using errcode='22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id::text,2));
  select * into v_existing from public.posts where id=p_id for update;
  if p_create then
    if found then
      if v_existing.author_id<>auth.uid() or v_existing.parish_id<>p_parish then raise exception 'forbidden' using errcode='42501'; end if;
      return v_existing.id;
    end if;
    insert into public.posts(id,parish_id,author_id,title,body,visibility,status,published_at)
    values(p_id,p_parish,auth.uid(),trim(p_title),trim(p_body),p_visibility,p_status,
      case when p_status='published' then now() else null end);
  else
    if not found or v_existing.parish_id<>p_parish then raise exception 'post_unavailable' using errcode='22023'; end if;
    if p_expected_updated_at is null or p_expected_updated_at<>v_existing.updated_at then
      raise exception 'edit_conflict' using errcode='40001';
    end if;
    update public.posts set title=trim(p_title),body=trim(p_body),visibility=p_visibility,status=p_status,
      published_at=case when p_status='published' then coalesce(v_existing.published_at,now()) else v_existing.published_at end
    where id=p_id;
  end if;
  return p_id;
end $$;

revoke all on function public.admin_parishes(uuid,uuid,integer),
  public.admin_pending_memberships(uuid,timestamptz,uuid,integer),
  public.admin_save_parish(uuid,boolean,text,text,text,text,text,boolean,timestamptz,text,text),
  public.admin_save_post(uuid,uuid,boolean,text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function public.admin_parishes(uuid,uuid,integer),
  public.admin_pending_memberships(uuid,timestamptz,uuid,integer),
  public.admin_save_parish(uuid,boolean,text,text,text,text,text,boolean,timestamptz,text,text),
  public.admin_save_post(uuid,uuid,boolean,text,text,text,text,timestamptz) to authenticated;

commit;
