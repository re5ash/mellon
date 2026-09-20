begin;
-- Extensible roles can be managed without deploying new Flutter code.
-- Baseline roles are intentionally changed only by a reviewed migration.
create function public.define_role(p_key text,p_title text,p_scope text,p_permissions text[]) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_role app_private.roles; v_id uuid;
begin
 if not app_private.has_permission('roles.manage') then raise exception 'forbidden' using errcode='42501'; end if;
 if p_key is null or p_key !~ '^[a-z][a-z0-9_]{2,63}$' or p_title is null or length(trim(p_title)) not between 1 and 100
 or p_scope is null or p_scope not in ('global','parish') or p_permissions is null then raise exception 'invalid_role' using errcode='22023'; end if;
 if exists(select 1 from unnest(p_permissions) as x(key) left join app_private.permissions p on p.key=x.key
   where p.key is null or (p_scope='parish' and p.scope='global')) then raise exception 'invalid_permissions' using errcode='22023'; end if;
 select * into v_role from app_private.roles where key=p_key for update;
 if found then
  if v_role.baseline is not null or v_role.scope<>p_scope then raise exception 'protected_role' using errcode='42501'; end if;
  v_id=v_role.id;
  update app_private.roles set title=trim(p_title) where id=v_id;
  delete from app_private.role_permissions where role_id=v_id;
 else
  insert into app_private.roles(key,title,scope) values(p_key,trim(p_title),p_scope) returning id into v_id;
 end if;
 insert into app_private.role_permissions(role_id,permission_key) select distinct v_id,x from unnest(p_permissions) x;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'role.define','role',v_id,jsonb_build_object('key',p_key,'permissions',p_permissions));
 return v_id;
end $$;
create function public.role_catalog() returns table(role_key text,title text,scope text,permissions text[])
language sql stable security definer set search_path='' as $$
 select r.key,r.title,r.scope,coalesce(array_agg(rp.permission_key) filter(where rp.permission_key is not null),'{}'::text[])
 from app_private.roles r left join app_private.role_permissions rp on rp.role_id=r.id
 where app_private.has_permission('roles.manage') group by r.id order by r.key;
$$;
create function public.read_audit(p_parish uuid default null,p_before bigint default null) returns table(
 id bigint,actor_id uuid,action text,entity_type text,entity_id uuid,parish_id uuid,created_at timestamptz,metadata jsonb)
language sql stable security definer set search_path='' as $$
 select a.id,a.actor_id,a.action,a.entity_type,a.entity_id,a.parish_id,a.created_at,a.metadata
 from app_private.audit_log a where app_private.has_permission('audit.read',p_parish)
 and (p_parish is null or a.parish_id=p_parish) and (p_before is null or a.id<p_before)
 order by a.id desc limit 50;
$$;
revoke all on function public.define_role(text,text,text,text[]),public.role_catalog(),public.read_audit(uuid,bigint) from public,anon,authenticated;
grant execute on function public.define_role(text,text,text,text[]),public.role_catalog(),public.read_audit(uuid,bigint) to authenticated;
commit;
