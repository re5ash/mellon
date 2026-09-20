import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const db=new PGlite();let checks=0;
const q=s=>db.query(s);
const val=async s=>Object.values((await q(s)).rows[0])[0];
async function test(name,fn){await fn();checks++;console.log('PASS '+name);}
async function login(id){await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id??''}',false);set role ${id?'authenticated':'anon'};`);}
const deny=(s,code='42501')=>assert.rejects(()=>q(s),e=>e.code===code);
const uid=n=>`a0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const pid=n=>`20000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const rid=n=>`40000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const a=pid(1),b=pid(2),ua=uid(1),ub=uid(2),admin=uid(3),superuser=uid(4),pending=uid(5);
try {
await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
create publication supabase_realtime;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated; grant select,insert,delete on storage.objects to authenticated;`);
for(const f of (await readdir(path.join(root,'supabase/migrations'))).sort()){
 await test('migration '+f,async()=>db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8')));
}
await db.exec(`insert into public.cities(id,name,country_code) values('10000000-0000-0000-0000-000000000001','Test','RU');
insert into public.parishes(id,city_id,slug,name,join_mode,is_published) values
('${a}','10000000-0000-0000-0000-000000000001','a','A','open',true),('${b}','10000000-0000-0000-0000-000000000001','b','B','approval',true);
insert into auth.users(id,raw_user_meta_data) values
('${ua}','{"role":"super_admin","parish_id":"${b}"}'),('${ub}','{}'),('${admin}','{}'),('${superuser}','{}'),('${pending}','{}');
-- Explicit consent: new accounts now default to private directory visibility.
update public.profiles set directory_visibility='parish' where id in ('${ua}','${ub}','${admin}');
insert into public.memberships(user_id,parish_id,status) values('${ua}','${a}','active'),('${ub}','${b}','active'),('${admin}','${a}','active');
insert into app_private.role_assignments(user_id,role_id,parish_id) select '${admin}',id,'${a}' from app_private.roles where key='parish_admin';
insert into app_private.role_assignments(user_id,role_id) select '${superuser}',id from app_private.roles where key='super_admin';
insert into public.posts(parish_id,author_id,title,body,visibility,status,published_at) values
('${a}','${admin}','Public A','public','public','published',now()-interval '1 day'),
('${a}','${admin}','Private A','secret A','parish','published',now()-interval '1 day'),
('${b}','${ub}','Private B','secret B','parish','published',now()-interval '1 day'),
('${a}','${admin}','Draft A','draft','public','draft',null),
('${a}','${admin}','Scheduled A','scheduled','public','published',now()+interval '1 day');
insert into public.chat_rooms(id,parish_id,title,access,kind,created_by) values
('${rid(1)}','${a}','A group','parish','group','${admin}'),('${rid(2)}','${a}','A restricted','restricted','group','${admin}'),
('${rid(3)}','${b}','B group','parish','group','${ub}'),('${rid(4)}','${a}','A channel','parish','channel','${admin}');
insert into public.notifications(id,user_id,kind,title,target_path) values
('50000000-0000-0000-0000-000000000001','${ua}','test','Private notice A','/feed'),
('50000000-0000-0000-0000-000000000002','${ub}','test','Private notice B','/feed');`);
await test('RLS enabled on every application table',async()=>assert.equal(await val(`select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','app_private') and c.relkind='r' and not c.relrowsecurity`),0));
await login(null);
await test('guest sees only published public content',async()=>assert.deepEqual((await q('select title from public.posts')).rows,[{title:'Public A'}]));
await test('guest can see parishes',async()=>assert.equal(await val('select count(*)::int from public.parishes'),2));
for(const t of ['profiles','memberships','chat_messages','notifications']) await test('guest denied '+t,()=>deny(`select * from public.${t}`));
await test('guest denied membership RPC',()=>deny(`select public.request_membership('${a}')`));
await login(ua);
await test('signup metadata cannot grant roles',async()=>assert.equal(await val("select app_private.has_permission('roles.manage')"),false));
await test('member A cannot see private B, drafts or future posts',async()=>assert.deepEqual((await q('select title from public.posts order by title')).rows,[{title:'Private A'},{title:'Public A'}]));
await test('member only sees own membership',async()=>assert.equal(await val('select count(*)::int from public.memberships'),1));
await test('direct membership forgery denied',()=>deny(`insert into public.memberships(user_id,parish_id,status) values('${ua}','${b}','active')`));
await test('self promotion RPC denied',()=>deny(`select public.grant_role('${ua}','super_admin')`));
for(const t of ['role_assignments','profile_private','audit_log']) await test('internal table inaccessible '+t,()=>deny(`select * from app_private.${t}`));
await test('private profile owner RPC works',async()=>{await q("select public.update_private_profile('Анна','Тест',date '1994-01-01')");assert.equal(await val('select given_name from public.my_private_profile()'),'Анна');});
await test('future birthday rejected',()=>deny("select public.update_private_profile('A','B',current_date+1)",'22023'));
await test('profile identity immutable',()=>deny(`update public.profiles set id='${ub}' where id='${ua}'`));
await test('only co-parish display profiles visible',async()=>assert.equal(await val('select count(*)::int from public.profiles'),2));
await test('second parish denied',()=>deny(`select public.request_membership('${b}')`,'23505'));
await test('member cannot publish',()=>deny(`insert into public.posts(parish_id,author_id,title,body) values('${a}','${ua}','forged','forged')`));
await test('restricted room hidden',async()=>assert.equal(await val(`select count(*)::int from public.chat_rooms where id='${rid(2)}'`),0));
for(const room of [rid(2),rid(3),rid(4)]) await test('send denied to restricted/foreign/channel '+room,()=>deny(`select public.send_message('${room}','forged','60000000-0000-0000-0000-000000000001')`));
let messageId;
await test('group message delivery and idempotent retry',async()=>{
 const command=`select (public.send_message('${rid(1)}','Hello','60000000-0000-0000-0000-000000000001')).id`;
 messageId=await val(command);assert.equal(await val(command),messageId);assert.equal(await val('select count(*)::int from public.chat_messages'),1);
});
await test('direct message forgery denied',()=>deny(`insert into public.chat_messages(room_id,author_id,client_nonce,body) values('${rid(1)}','${admin}','60000000-0000-0000-0000-000000000002','impersonation')`));
await test('notifications recipient-only',async()=>assert.equal(await val('select count(*)::int from public.notifications'),1));
await test('notification ownership immutable',()=>deny(`update public.notifications set user_id='${ub}'`));
await test('foreign notification cannot be marked read',async()=>{await q("select public.mark_notification_read('50000000-0000-0000-0000-000000000002')");await login(ub);assert.equal(await val('select read_at from public.notifications'),null);});
await login(admin);
await test('parish admin rights scoped correctly',async()=>{assert.equal(await val(`select app_private.has_permission('posts.manage','${a}')`),true);assert.equal(await val(`select app_private.has_permission('posts.manage','${b}')`),false);});
await test('A admin cannot publish in B',()=>deny(`insert into public.posts(parish_id,author_id,title,body) values('${b}','${admin}','forged','forged')`));
await test('post parish cannot be changed',()=>deny(`update public.posts set parish_id='${b}' where parish_id='${a}'`));
await test('parish admin cannot define roles',()=>deny("select public.define_role('editor','Editor','parish',array['posts.manage'])"));
await test('parish admin has no private profile table access',()=>deny('select * from app_private.profile_private'));
await test('parish publish flag not directly mutable',()=>deny(`update public.parishes set is_published=false where id='${a}'`));
await test('foreign member cannot be added to restricted chat',()=>deny(`select public.set_chat_member('${rid(2)}','${ub}',true)`,'23514'));
await test('authorized restricted chat invitation works',async()=>{await q(`select public.set_chat_member('${rid(2)}','${ua}',true)`);await login(ua);assert.equal(await val(`select count(*)::int from public.chat_rooms where id='${rid(2)}'`),1);await login(admin);});
await test('message moderation replaces body and is audited',async()=>{await q(`select public.hide_message('${messageId}')`);assert.equal(await val(`select body from public.chat_messages where id='${messageId}'`),'Сообщение удалено');assert.equal(await val(`select count(*)::int from public.read_audit('${a}') where action='message.hide'`),1);});
await test('parish admin denied global audit',async()=>assert.equal(await val('select count(*)::int from public.read_audit()'),0));
await login(pending);let pendingId;
await test('approval parish creates pending membership',async()=>{pendingId=await val(`select (public.request_membership('${b}')).id`);assert.equal(await val(`select app_private.is_member('${b}')`),false);});
await login(admin);
await test('A admin cannot approve B applicant',()=>deny(`select public.review_membership('${pendingId}','active')`));
await login(superuser);
await test('super admin can approve applicant',async()=>{await q(`select public.review_membership('${pendingId}','active')`);await login(pending);assert.equal(await val(`select app_private.is_member('${b}')`),true);await login(superuser);});
await test('custom role can grant one scoped permission',async()=>{
 await q("select public.define_role('editor','Редактор','parish',array['posts.manage'])");await q(`select public.grant_role('${ua}','editor','${a}')`);await login(ua);
 assert.equal(await val(`select app_private.has_permission('posts.manage','${a}')`),true);assert.equal(await val(`select app_private.has_permission('memberships.manage','${a}')`),false);await login(superuser);
});
await test('parish role cannot contain global permission',()=>deny("select public.define_role('unsafe','Unsafe','parish',array['roles.manage'])",'22023'));
await test('baseline roles protected from RPC changes',()=>deny("select public.define_role('user','User','global',array['roles.manage'])"));
await test('scoped role needs active matching membership',()=>deny(`select public.grant_role('${ub}','editor','${a}')`,'23514'));
await test('banned user cannot self reactivate',async()=>{await q(`select public.review_membership('${pendingId}','banned')`);await login(pending);await q('select public.leave_parish()');await deny(`select public.request_membership('${b}')`);await login(superuser);});
await test('role revoke effective without new JWT',async()=>{const id=await val(`select public.grant_role('${ua}','parish_admin','${a}')`);await q(`select public.revoke_role('${id}')`);await login(ua);assert.equal(await val(`select app_private.has_permission('memberships.manage','${a}')`),false);});
await test('leave revokes private content, roles and closed-chat invitation',async()=>{
 await q('select public.leave_parish()');assert.equal(await val(`select app_private.has_permission('posts.manage','${a}')`),false);
 assert.equal(await val('select count(*)::int from public.chat_rooms'),0);assert.equal(await val("select count(*)::int from public.posts where visibility='parish'"),0);
 await q(`select public.request_membership('${a}')`);assert.equal(await val(`select count(*)::int from public.chat_rooms where id='${rid(2)}'`),0);assert.equal(await val(`select app_private.has_permission('posts.manage','${a}')`),false);
});
await db.exec('reset role');
await test('unique index prevents duplicate current membership',()=>deny(`insert into public.memberships(user_id,parish_id,status) values('${ua}','${b}','active')`,'23505'));
await test('event cannot use another parish location',async()=>{
 await q(`insert into public.parish_locations(id,parish_id,name,address,latitude,longitude) values('70000000-0000-0000-0000-000000000001','${b}','B','B',0,0)`);
 await deny(`insert into public.events(parish_id,location_id,title,starts_at,ends_at,created_by) values('${a}','70000000-0000-0000-0000-000000000001','Mismatch',now(),now()+interval '1 hour','${admin}')`,'23503');
});
await test('notifications queue exactly once',async()=>assert.equal(await val('select count(*)::int from app_private.notification_outbox'),2));
await test('Realtime publication excludes all private tables',async()=>assert.deepEqual((await q("select tablename from pg_publication_tables where pubname='supabase_realtime' order by tablename")).rows.map(x=>x.tablename),['chat_messages','chat_pins','events','help_requests','notifications','posts']));
console.log(`RESULT: ${checks} checks passed. PGlite/PostgreSQL, auth.uid mocked. Live Auth/Realtime and parallel connections not tested.`);
} finally {await db.close();}
