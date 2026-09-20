begin;

-- Copy only personal registration fields once, when the account is created.
-- User metadata must never grant a role, parish membership or youth membership.
create or replace function app_private.on_signup() returns trigger
language plpgsql security definer set search_path='' as $$
declare
 v_registration jsonb := new.raw_user_meta_data -> 'club_registration';
 v_given text := '';
 v_family text := '';
 v_birth date;
 v_display text := 'Прихожанин';
begin
 if v_registration is not null then
  if jsonb_typeof(v_registration) is distinct from 'object'
   or jsonb_typeof(v_registration -> 'given_name') is distinct from 'string'
   or jsonb_typeof(v_registration -> 'family_name') is distinct from 'string'
   or jsonb_typeof(v_registration -> 'birth_date') is distinct from 'string' then
   raise exception 'invalid_registration_profile' using errcode='22023';
  end if;
  v_given := btrim(v_registration ->> 'given_name');
  v_family := btrim(v_registration ->> 'family_name');
  if length(v_given) not between 1 and 100 or length(v_family) not between 1 and 100
   or (v_registration ->> 'birth_date') !~ '^\d{4}-\d{2}-\d{2}$' then
   raise exception 'invalid_registration_profile' using errcode='22023';
  end if;
  begin
   v_birth := (v_registration ->> 'birth_date')::date;
  exception when invalid_datetime_format or datetime_field_overflow then
   raise exception 'invalid_birth_date' using errcode='22023';
  end;
  if v_birth < date '1900-01-01' or v_birth > (current_timestamp at time zone 'UTC')::date then
   raise exception 'invalid_birth_date' using errcode='22023';
  end if;
  v_display := left(v_given || ' ' || v_family, 100);
 end if;
 insert into public.profiles(id, display_name) values(new.id, v_display);
 insert into app_private.profile_private(user_id, given_name, family_name, birth_date)
 values(new.id, v_given, v_family, v_birth);
 return new;
end $$;

revoke all on function app_private.on_signup() from public, anon, authenticated;

commit;
