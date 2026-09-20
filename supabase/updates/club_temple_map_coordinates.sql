-- Выполнить один раз в Supabase → SQL Editor.
-- Используется существующий ID храма. Новые храмы/метки не создаются.
-- Адрес остаётся в parishes.address и не дублируется.
begin;

do $$
begin
  if not exists (
    select 1 from public.parishes
    where id = 'c9102d4b-4ad0-4b03-b523-179052cbc0c0'::uuid
  ) then
    raise exception 'Связанный храм не найден. Изменения не применены.';
  end if;
end $$;

-- Координаты перенесены из существующей метки приложения.
-- Уже заполненные координаты сохраняются.
update public.parishes
set latitude = 54.723306, longitude = 20.526467
where id = 'c9102d4b-4ad0-4b03-b523-179052cbc0c0'::uuid
  and latitude is null and longitude is null;

select id, name, address, latitude, longitude
from public.parishes
where id = 'c9102d4b-4ad0-4b03-b523-179052cbc0c0'::uuid;

commit;
