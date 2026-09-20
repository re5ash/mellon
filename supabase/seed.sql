-- Local fixture only. Not verified real parish data; never seed into production.
insert into public.cities(id,name,country_code,timezone) values
 ('10000000-0000-0000-0000-000000000001','Демонстрационный город','RU','Europe/Kaliningrad');
insert into public.parishes(id,city_id,slug,name,description,address,join_mode,is_published) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001',
 'demo-parish','Тестовый приход','Демонстрационные данные для локальной разработки','Адрес ещё не указан','approval',true);
