begin;
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;
-- Only public is exposed through PostgREST; app_private is never an API schema.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema app_private revoke all on tables from public, anon, authenticated;
alter default privileges in schema app_private revoke execute on functions from public;

create table public.cities (
 id uuid primary key default gen_random_uuid(), name text not null check (length(name) between 1 and 160),
 country_code text not null check (length(country_code)=2), timezone text not null default 'Europe/Kaliningrad'
);
create table public.parishes (
 id uuid primary key default gen_random_uuid(), city_id uuid not null references public.cities,
 slug text unique not null check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
 name text not null check (length(name) between 1 and 200), description text not null default '',
 address text not null default '', latitude double precision check (latitude between -90 and 90),
 longitude double precision check (longitude between -180 and 180),
 join_mode text not null default 'approval' check (join_mode in ('open','approval')),
 is_published boolean not null default false, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), check ((latitude is null)=(longitude is null))
);
create index parishes_city on public.parishes(city_id) where is_published;
create table public.parish_locations (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 name text not null, address text not null, latitude double precision not null check (latitude between -90 and 90),
 longitude double precision not null check (longitude between -180 and 180), unique(id,parish_id)
);
-- A profile is a display identity, not a public directory of personal details.
create table public.profiles (
 id uuid primary key references auth.users on delete cascade,
 display_name text not null default 'Прихожанин' check (length(display_name) between 1 and 100),
 directory_visibility text not null default 'parish' check (directory_visibility in ('private','parish')),
 updated_at timestamptz not null default now()
);
create table app_private.profile_private (
 user_id uuid primary key references public.profiles on delete cascade,
 given_name text not null default '' check (length(given_name)<=100),
 family_name text not null default '' check (length(family_name)<=100), birth_date date,
 updated_at timestamptz not null default now()
);
create table public.memberships (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles on delete cascade,
 parish_id uuid not null references public.parishes,
 status text not null check (status in ('pending','active','left','rejected','banned')),
 requested_at timestamptz not null default now(), reviewed_at timestamptz,
 reviewed_by uuid references public.profiles on delete set null, ended_at timestamptz,
 check ((status in ('left','rejected','banned')) = (ended_at is not null))
);
-- Enforced even when two requests arrive concurrently.
create unique index memberships_one_current on public.memberships(user_id) where status in ('pending','active');
create index memberships_parish_status on public.memberships(parish_id,status,user_id);
create index memberships_user_history on public.memberships(user_id,requested_at desc);

create table app_private.permissions (
 key text primary key, description text not null,
 scope text not null check(scope in ('global','parish','both'))
);
create table app_private.roles (
 id uuid primary key default gen_random_uuid(), key text unique not null, title text not null,
 scope text not null check(scope in ('global','parish')),
 baseline text unique check(baseline in ('guest','authenticated')),
 check (baseline is null or scope='global')
);
create table app_private.role_permissions (
 role_id uuid not null references app_private.roles on delete cascade,
 permission_key text not null references app_private.permissions on delete cascade,
 primary key(role_id,permission_key)
);
create table app_private.role_assignments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles on delete cascade,
 role_id uuid not null references app_private.roles,
 parish_id uuid references public.parishes, granted_by uuid references public.profiles on delete set null,
 created_at timestamptz not null default now(), expires_at timestamptz,
 check(expires_at is null or expires_at>created_at)
);
create unique index role_assignment_global on app_private.role_assignments(user_id,role_id) where parish_id is null;
create unique index role_assignment_parish on app_private.role_assignments(user_id,role_id,parish_id) where parish_id is not null;
create index role_assignment_lookup on app_private.role_assignments(user_id,parish_id);

create table public.posts (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 author_id uuid not null references public.profiles,
 title text not null check(length(title) between 1 and 200), body text not null check(length(body)<=30000),
 visibility text not null default 'parish' check(visibility in ('public','parish')),
 status text not null default 'draft' check(status in ('draft','published','archived')),
 published_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(status<>'published' or published_at is not null)
);
create index posts_feed on public.posts(published_at desc,id desc) where status='published';
create index posts_parish_feed on public.posts(parish_id,published_at desc,id desc);
create table public.events (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 location_id uuid, title text not null check(length(title) between 1 and 200), description text not null default '',
 starts_at timestamptz not null, ends_at timestamptz not null, timezone text not null default 'Europe/Kaliningrad',
 visibility text not null default 'parish' check(visibility in ('public','parish')),
 status text not null default 'draft' check(status in ('draft','published','cancelled','archived')),
 created_by uuid not null references public.profiles, created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(), check(ends_at>starts_at),
 foreign key(location_id,parish_id) references public.parish_locations(id,parish_id)
);
create index events_calendar on public.events(parish_id,starts_at,id);
create table public.event_attendees (
 event_id uuid not null references public.events on delete cascade,
 user_id uuid not null references public.profiles on delete cascade,
 created_at timestamptz not null default now(), primary key(event_id,user_id)
);
create table public.help_requests (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 author_id uuid not null references public.profiles, title text not null check(length(title) between 1 and 200),
 description text not null check(length(description)<=10000),
 visibility text not null default 'parish' check(visibility in ('public','parish')),
 status text not null default 'draft' check(status in ('draft','published','fulfilled','archived')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index help_feed on public.help_requests(parish_id,created_at desc,id desc);
create table public.help_responses (
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.help_requests on delete cascade,
 user_id uuid not null references public.profiles on delete cascade,
 message text not null check(length(message) between 1 and 2000),
 created_at timestamptz not null default now(), unique(request_id,user_id)
);
create table public.chat_rooms (
 id uuid primary key default gen_random_uuid(), parish_id uuid not null references public.parishes,
 title text not null check(length(title) between 1 and 100),
 kind text not null default 'group' check(kind in ('group','channel')),
 access text not null default 'parish' check(access in ('parish','restricted')),
 is_archived boolean not null default false, created_by uuid not null references public.profiles,
 created_at timestamptz not null default now()
);
create index chat_rooms_parish on public.chat_rooms(parish_id);
create table public.chat_members (
 room_id uuid not null references public.chat_rooms on delete cascade,
 user_id uuid not null references public.profiles on delete cascade,
 added_at timestamptz not null default now(), primary key(room_id,user_id)
);
create table public.chat_messages (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.chat_rooms,
 author_id uuid not null references public.profiles,
 client_nonce uuid not null, body text not null check(length(body) between 1 and 4000),
 created_at timestamptz not null default now(), deleted_at timestamptz,
 unique(author_id,client_nonce)
);
create index chat_messages_page on public.chat_messages(room_id,created_at desc,id desc);
create table public.notifications (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles on delete cascade,
 kind text not null, title text not null, body text not null default '',
 target_path text not null check(target_path like '/%' and target_path not like '//%'),
 created_at timestamptz not null default now(), read_at timestamptz
);
create index notifications_inbox on public.notifications(user_id,created_at desc,id desc);
create table app_private.push_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles on delete cascade,
 platform text not null check(platform in ('web','android')), device_key text not null,
 subscription jsonb not null, created_at timestamptz not null default now(), unique(user_id,device_key)
);
create table app_private.notification_outbox (
 id uuid primary key default gen_random_uuid(), notification_id uuid not null unique references public.notifications on delete cascade,
 attempts integer not null default 0 check(attempts>=0), available_at timestamptz not null default now(),
 locked_until timestamptz, delivered_at timestamptz, last_error_code text
);
create index outbox_pending on app_private.notification_outbox(available_at) where delivered_at is null;
create table app_private.audit_log (
 id bigint generated always as identity primary key, actor_id uuid, action text not null,
 entity_type text not null, entity_id uuid, parish_id uuid, created_at timestamptz not null default now(),
 metadata jsonb not null default '{}'::jsonb
);
create index audit_parish_time on app_private.audit_log(parish_id,created_at desc);

-- Every table, including internal tables, has RLS; internal tables have no client grants.
do $$ declare t record; begin
 for t in select schemaname,tablename from pg_tables where schemaname in ('public','app_private') loop
  execute format('alter table %I.%I enable row level security',t.schemaname,t.tablename);
  execute format('revoke all on table %I.%I from public,anon,authenticated',t.schemaname,t.tablename);
 end loop;
end $$;
commit;
