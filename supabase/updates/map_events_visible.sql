-- Mellon: show marked events before their date; the Today banner stays separate.
-- Run after map_events.sql. Safe to repeat. Does not change event access rules.
begin;
create or replace function public.map_events_visible()
returns table(
 id uuid,title text,location_label text,starts_at timestamptz,
 map_latitude double precision,map_longitude double precision,
 time_label text,date_label text,is_today boolean
)
language sql stable security invoker set search_path='' as $$
 with calendar as (
  select date_trunc('day',now() at time zone 'Europe/Kaliningrad') as today
 )
 select e.id,e.title,e.location_label,e.starts_at,e.map_latitude,e.map_longitude,
 to_char(e.starts_at at time zone 'Europe/Kaliningrad','HH24:MI'),
 case when date_trunc('day',e.starts_at at time zone 'Europe/Kaliningrad')=c.today
      then 'Сегодня'
      else to_char(e.starts_at at time zone 'Europe/Kaliningrad','DD.MM.YYYY') end,
 date_trunc('day',e.starts_at at time zone 'Europe/Kaliningrad')=c.today
 from public.events e cross join calendar c
 where e.show_on_map and e.status='published'
 and e.map_latitude is not null and e.map_longitude is not null
 and e.ends_at >= (c.today at time zone 'Europe/Kaliningrad')
 order by e.starts_at,e.id;
$$;
revoke all on function public.map_events_visible() from public;
grant execute on function public.map_events_visible() to anon,authenticated;
notify pgrst, 'reload schema';
commit;
