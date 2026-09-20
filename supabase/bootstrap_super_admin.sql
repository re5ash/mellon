-- Run only as database owner in SQL Editor/psql AFTER selecting a known Auth user.
-- No automatic first-user promotion and no client endpoint for initial bootstrap.
do $$
declare v_user uuid := nullif(current_setting('app.bootstrap_user_id',true),'')::uuid;
begin
 if v_user is null or not exists(select 1 from auth.users where id=v_user) then
  raise exception 'Set app.bootstrap_user_id to an existing, verified Auth user UUID first';
 end if;
 insert into app_private.role_assignments(user_id,role_id,granted_by)
 select v_user,id,v_user from app_private.roles where key='super_admin' on conflict do nothing;
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id)
 values(v_user,'role.bootstrap','profile',v_user);
end $$;
