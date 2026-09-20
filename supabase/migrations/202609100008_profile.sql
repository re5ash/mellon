begin;

-- Existing visibility choices remain unchanged; new accounts start private.
alter table public.profiles alter column directory_visibility set default 'private';
alter table public.profiles add column revision bigint not null default 0;
alter table app_private.profile_private add column revision bigint not null default 0;

-- Revisions also cover older clients using direct profile UPDATE / legacy RPC.
create function app_private.advance_profile_revision() returns trigger
language plpgsql set search_path='' as $$
begin
 new.revision=old.revision+1;
 new.updated_at=clock_timestamp();
 return new;
end $$;
create trigger zz_profile_revision before update on public.profiles
 for each row execute function app_private.advance_profile_revision();
create trigger zz_profile_revision before update on app_private.profile_private
 for each row execute function app_private.advance_profile_revision();

create function public.my_profile() returns table(
 user_id uuid,display_name text,directory_visibility text,given_name text,
 family_name text,birth_date date,profile_revision bigint,private_revision bigint
)
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not app_private.has_permission('profile.self') then
  raise exception 'forbidden' using errcode='42501';
 end if;
 return query select p.id,p.display_name,p.directory_visibility,d.given_name,
  d.family_name,d.birth_date,p.revision,d.revision
 from public.profiles p join app_private.profile_private d on d.user_id=p.id
 where p.id=auth.uid();
end $$;

-- The account always comes from the verified session; expected id only guards
-- against sending a form from a previous account after switching sessions.
-- Both records commit together. Equal-value retries are safe after lost replies.
create function public.save_my_profile(
 p_display_name text,p_directory_visibility text,p_given_name text,p_family_name text,
 p_birth_date date,p_profile_revision bigint,p_private_revision bigint,p_expected_user_id uuid
) returns table(
 user_id uuid,display_name text,directory_visibility text,given_name text,
 family_name text,birth_date date,profile_revision bigint,private_revision bigint
)
language plpgsql security definer set search_path='' as $$
declare v_public public.profiles; v_private app_private.profile_private;
begin
 if auth.uid() is null or p_expected_user_id is distinct from auth.uid()
  or not app_private.has_permission('profile.self') then
  raise exception 'forbidden' using errcode='42501';
 end if;
 p_display_name=btrim(p_display_name);
 p_given_name=btrim(p_given_name);
 p_family_name=btrim(p_family_name);
 if p_display_name is null or length(p_display_name) not between 1 and 100
  or p_given_name is null or length(p_given_name)>100
  or p_family_name is null or length(p_family_name)>100
  or p_directory_visibility is null or p_directory_visibility not in ('private','parish')
  or p_profile_revision is null or p_profile_revision<0
  or p_private_revision is null or p_private_revision<0 then
  raise exception 'invalid_profile' using errcode='22023';
 end if;
 if p_birth_date is not null and (not isfinite(p_birth_date)
  or p_birth_date<date '1900-01-01' or p_birth_date>(current_timestamp at time zone 'UTC')::date) then
  raise exception 'invalid_birth_date' using errcode='22023';
 end if;
 -- Same lock order as membership administration; no changes to membership/roles.
 select * into v_public from public.profiles where id=auth.uid() for update;
 if not found then raise exception 'profile_unavailable' using errcode='P0002'; end if;
 select * into v_private from app_private.profile_private where profile_private.user_id=auth.uid() for update;
 if not found then raise exception 'profile_unavailable' using errcode='P0002'; end if;
 if v_public.display_name=p_display_name and v_public.directory_visibility=p_directory_visibility
  and v_private.given_name=p_given_name and v_private.family_name=p_family_name
  and v_private.birth_date is not distinct from p_birth_date then
  return query select * from public.my_profile();
  return;
 end if;
 if v_public.revision<>p_profile_revision or v_private.revision<>p_private_revision then
  raise exception 'profile_edit_conflict' using errcode='40001';
 end if;
 update public.profiles set display_name=p_display_name,directory_visibility=p_directory_visibility where id=auth.uid();
 update app_private.profile_private set given_name=p_given_name,family_name=p_family_name,birth_date=p_birth_date
 where profile_private.user_id=auth.uid();
 return query select * from public.my_profile();
end $$;

revoke all on function app_private.advance_profile_revision() from public,anon,authenticated;
revoke all on function public.my_profile(),public.save_my_profile(text,text,text,text,date,bigint,bigint,uuid)
 from public,anon,authenticated;
grant execute on function public.my_profile(),public.save_my_profile(text,text,text,text,date,bigint,bigint,uuid)
 to authenticated;
-- Personal fields stay outside Realtime, audit payloads and the public schema.
commit;
