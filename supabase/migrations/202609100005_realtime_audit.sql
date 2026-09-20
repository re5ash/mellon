begin;
-- Postgres Changes is a freshness signal; the client re-reads through RLS.
-- No private profiles, memberships, role tables or outbox in the publication.
alter publication supabase_realtime add table public.posts,public.events,public.help_requests,public.chat_messages,public.notifications;
create function app_private.audit_content_write() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into app_private.audit_log(actor_id,action,entity_type,entity_id,parish_id)
 values(auth.uid(),lower(tg_op),tg_table_name,new.id,new.parish_id);
 return new;
end $$;
do $$ declare t text; begin
 foreach t in array array['posts','events','help_requests','chat_rooms','parish_locations'] loop
  execute format('create trigger audit_write after insert or update on public.%I for each row execute function app_private.audit_content_write()',t);
 end loop;
end $$;
create function app_private.enqueue_notification() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into app_private.notification_outbox(notification_id) values(new.id) on conflict do nothing;
 return new;
end $$;
create trigger enqueue_notification after insert on public.notifications for each row execute function app_private.enqueue_notification();
commit;
