begin;
alter table app_private.profile_private add column phone text not null default '' check(length(phone)<=32);
alter table public.profiles add column avatar_path text;
-- Avatar references are changed only through the guarded RPC.
revoke update on public.profiles from authenticated;
grant update(display_name,directory_visibility) on public.profiles to authenticated;
create function public.my_profile_v2() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
 select to_jsonb(p) into v from public.my_profile() p;
 return v || (select jsonb_build_object('phone',d.phone,'avatar_path',p.avatar_path,'email',coalesce(to_jsonb(u)->>'email',''),
 'parish_name',(select pa.name from public.memberships m join public.parishes pa on pa.id=m.parish_id where m.user_id=p.id and m.status='active'),
 'youth_name',(select g.name from public.youth_memberships m join public.youth_groups g on g.id=m.youth_id where m.user_id=p.id and m.is_member and not g.is_archived))
 from public.profiles p join app_private.profile_private d on d.user_id=p.id join auth.users u on u.id=p.id where p.id=auth.uid());
end $$;
create function public.save_my_profile_v2(p_display_name text,p_directory_visibility text,p_given_name text,p_family_name text,p_birth_date date,p_profile_revision bigint,p_private_revision bigint,p_expected_user_id uuid,p_phone text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_public public.profiles; v_private app_private.profile_private;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user_id then raise exception 'forbidden' using errcode='42501'; end if;
 if p_phone is null or length(btrim(p_phone))>32 or p_phone<>'' and p_phone !~ '^[+0-9 ()-]{5,32}$' then raise exception 'invalid_phone' using errcode='22023'; end if;
 select * into v_public from public.profiles where id=auth.uid() for update;
 select * into v_private from app_private.profile_private where user_id=auth.uid() for update;
 if v_private.phone is distinct from btrim(p_phone) and (v_public.revision is distinct from p_profile_revision or v_private.revision is distinct from p_private_revision) then raise exception 'profile_edit_conflict' using errcode='40001'; end if;
 perform public.save_my_profile(p_display_name,p_directory_visibility,p_given_name,p_family_name,p_birth_date,p_profile_revision,p_private_revision,p_expected_user_id);
 if v_private.phone is distinct from btrim(p_phone) then update app_private.profile_private set phone=btrim(p_phone) where user_id=auth.uid(); end if;
 return public.my_profile_v2();
end $$;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('profile-avatars','profile-avatars',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;
create policy profile_avatar_select on storage.objects for select to authenticated using(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text);
create policy profile_avatar_insert on storage.objects for insert to authenticated with check(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text);
create policy profile_avatar_delete on storage.objects for delete to authenticated using(bucket_id='profile-avatars' and split_part(name,'/',1)=auth.uid()::text
 and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.avatar_path=name));
create function public.set_profile_avatar(p_path text,p_revision bigint,p_expected_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v public.profiles;
begin
 if auth.uid() is null or auth.uid() is distinct from p_expected_user then raise exception 'forbidden' using errcode='42501'; end if;
 select * into v from public.profiles where id=auth.uid() for update;
 if p_path is not null and (split_part(p_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='profile-avatars' and name=p_path)) then raise exception 'invalid_avatar' using errcode='22023'; end if;
 if v.avatar_path is not distinct from p_path then return public.my_profile_v2(); end if;
 if v.revision is distinct from p_revision then raise exception 'profile_edit_conflict' using errcode='40001'; end if;
 update public.profiles set avatar_path=p_path where id=auth.uid();
 return public.my_profile_v2();
end $$;
-- New RPCs and internal helpers do not inherit PostgreSQL's PUBLIC execute default.
do $privileges$
declare fn record;
begin
 for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname||'.'||p.proname in ('public.set_profile_avatar') loop
 execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $privileges$;
grant execute on function public.my_profile_v2(),public.save_my_profile_v2(text,text,text,text,date,bigint,bigint,uuid,text),public.set_profile_avatar(text,bigint,uuid) to authenticated;
commit;
