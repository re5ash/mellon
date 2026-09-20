import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),db=new PGlite();
const q=(s,a=[])=>db.query(s,a),val=async(s,a=[])=>Object.values((await q(s,a)).rows[0])[0];
const id=n=>`f0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [sup,leader,moderator,member,newcomer,legacyAdmin,clubAdmin]=[1,2,3,4,5,6,7].map(id);
const [city,pa,a,b]=[100,101,201,202].map(id);
let actor,count=0,seq=500;
async function login(u){actor=u;await db.exec(`reset role;select set_config('request.jwt.claim.sub','${u??''}',false);set role ${u?'authenticated':'anon'};`);}
async function check(name,fn){await fn();count++;console.log('PASS '+name);}
const denied=(s,a=[])=>assert.rejects(()=>q(s,a),e=>e.code==='42501');
const details=u=>val('select public.role_manager_person_v2($1)',[u]);
const roles=async(u,clubs=[],global=null)=>q('select public.save_person_roles_v2($1,$2,$3,$4,$5,$6)',[u,global,clubs,(await details(u)).revision,id(seq++),actor]);
const request=(club=a,receipt=id(seq++),expected=actor)=>val('select public.request_youth_club($1,$2,$3)',[club,receipt,expected]);
const save=(club=id(203),name='Новый клуб',revision=0)=>val('select public.save_youth_club($1,$2,$3,$4,false,$5,$6)',[club,city,name,'Описание',revision,actor]);
try{
 await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;`);
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')&&f<'202609120018').sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
 await db.exec(`insert into auth.users(id,email,email_confirmed_at) values ${[sup,leader,moderator,member,legacyAdmin,clubAdmin].map((u,i)=>`('${u}','person${i}@example.test',now())`).join(',')};
 insert into public.cities(id,name,country_code)values('${city}','Город','RU');
 insert into public.parishes(id,city_id,slug,name,is_published)values('${pa}','${city}','existing','Существующая связь',true);
 insert into app_private.role_assignments(user_id,role_id)select '${sup}',id from app_private.roles where key='super_admin';
 insert into public.memberships(user_id,parish_id,status)values('${legacyAdmin}','${pa}','active');
 insert into app_private.role_assignments(user_id,role_id,parish_id)select '${legacyAdmin}',id,'${pa}' from app_private.roles where key='parish_admin';
 insert into public.youth_groups(id,parish_id,name,created_by)values('${a}','${pa}','Клуб А','${sup}'),('${b}','${pa}','Клуб Б','${sup}');`);
 await login(sup);
 for(const [u,r] of [[leader,'youth_leader'],[moderator,'youth_moderator'],[member,'user'],[clubAdmin,'youth_admin']])await roles(u,[{id:a,role:r}]);
 await roles(member,[{id:b,role:'youth_moderator'}]);
 await db.exec('reset role');
 await db.exec(await readFile(path.join(root,'supabase/updates/club_navigation.sql'),'utf8'));
 const snapshot=(await q('select * from app_private.roles order by key')).rows;
 const tables=(await q("select tablename from pg_tables where schemaname='public' order by tablename")).rows;
 const existing=id(600),foreign=id(601),closed=id(602);
 await q(`insert into public.chat_rooms(id,parish_id,youth_id,title,description,kind,access,icon_key,created_by)values($1,$2,$3,'Существующий чат','Сохранить','group','parish','chat',$4),($5,$2,$6,'Другой клуб','','group','parish','chat',$4),($7,$2,$3,'Личный состав','','group','restricted','rules',$4)`,[existing,pa,a,sup,foreign,b,closed]);
 await q(`insert into public.chat_messages(room_id,author_id,client_nonce,body,created_at)values($1,$2,$3,'Старое сообщение',now()-interval '1 hour')`,[existing,sup,id(seq++)]);
 const original=(await q('select * from public.chat_rooms where id=$1',[existing])).rows[0];
 const sql=await readFile(path.join(root,'supabase/updates/club_dashboard.sql'),'utf8');
 const dash=(club=a,reads={})=>val('select public.club_dashboard($1,$2)',[club,reads]);
 const chat=async(room)=>{await db.exec('reset role');const row=(await q('select * from public.chat_rooms where id=$1',[room])).rows[0];await login(actor);return row;};
 const edit=(room,title,rev=null,club=a,icon='chat',expected=actor,desc='Описание')=>val('select public.save_club_chat($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)',[club,room,title,desc,icon,'group','parish',50,rev,expected]);
 const remove=(room,rev,club=a,expected=actor)=>q('select public.delete_club_chat($1,$2,$3,$4)',[club,room,rev,expected]);
 await check('migration repeats; no new public entity or role, existing chat/message retained',async()=>{
   await db.exec(sql);await db.exec(sql);
   assert.deepEqual((await q('select * from app_private.roles order by key')).rows,snapshot);
   assert.deepEqual((await q("select tablename from pg_tables where schemaname='public' order by tablename")).rows,tables);
   const row=(await q('select * from public.chat_rooms where id=$1',[existing])).rows[0];delete row.deleted_at;assert.deepEqual(row,original);
   assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[existing]),1);
   assert.equal(await val("select count(*)::int from public.chat_rooms where youth_id=$1 and sort_order between 1 and 13",[a]),13);
 });
 await check('member sees all 13 template chats with descriptions and stable order; private Active remains private',async()=>{
   await login(member);const d=await dash();assert.equal(d.can_manage_chats,false);assert.equal(d.can_create_chats,false);
   assert.equal(d.chats.filter(r=>r.sort_order>=1&&r.sort_order<=13).length,13);
   assert.equal(d.chats[0].title,'Болталка');assert(d.chats.every(r=>r.youth_id===a&&r.access==='parish'));
   assert(!d.chats.some(r=>r.id===closed||r.access==='active'));assert(d.chats.some(r=>r.id===existing));
 });
 await check('outsiders and anonymous callers cannot see dashboard or write rooms',async()=>{
   await login(legacyAdmin); // Historical parish admins retain their existing rights.
   await login(null);await denied('select public.club_dashboard($1)',[a]);await assert.rejects(()=>edit(id(700),'Нельзя'),e=>e.code==='42501');
   await db.exec('reset role');await q('insert into auth.users(id,email,email_confirmed_at)values($1,$2,now())',[newcomer,'outside@example.test']);await login(newcomer);
   await assert.rejects(()=>dash(),e=>e.code==='42501');await assert.rejects(()=>edit(id(700),'Нельзя'),e=>e.code==='42501');
 });
 await check('member and moderator cannot create, rename or delete a club chat',async()=>{
   const rev=(await chat(existing)).revision;
   for(const u of [member,moderator]) {await login(u);await assert.rejects(()=>edit(id(700),'Нельзя'),e=>e.code==='42501');await assert.rejects(()=>edit(existing,'Нельзя',rev),e=>e.code==='42501');await assert.rejects(()=>remove(existing,rev),e=>e.code==='42501');}
 });
 await check('club administrator creates with retry identity; icon and all fields persist',async()=>{
   await login(clubAdmin);assert.equal((await dash()).can_create_chats,true);
   assert.equal(await edit(id(701),'Встречи',null,a,'family'),id(701));assert.equal(await edit(id(701),'Встречи',null,a,'family'),id(701));
   const row=await chat(id(701));assert.equal(row.icon_key,'family');assert.equal(row.description,'Описание');assert.equal(row.youth_id,a);
 });
 await check('rename preserves messages and room identity; stale edits are rejected',async()=>{
   await login(leader);const rev=(await chat(existing)).revision;
   await edit(existing,'Новое имя',rev,a,'music');const row=await chat(existing);assert.equal(row.title,'Новое имя');assert.equal(row.icon_key,'music');
   await assert.rejects(()=>edit(existing,'Устаревшее',rev),e=>e.code==='40001');
   assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[existing]),1);
 });
 await check('club admin cannot target another club or falsify the expected account',async()=>{
   await login(clubAdmin);await assert.rejects(()=>edit(id(702),'Чужое',null,b),e=>e.code==='42501');
   await assert.rejects(async()=>edit(foreign,'Перенос',(await chat(foreign)).revision,a),e=>['22023','42501'].includes(e.code));
   await assert.rejects(async()=>remove(foreign,(await chat(foreign)).revision,b),e=>e.code==='42501');
   await assert.rejects(()=>edit(id(702),'Подмена',null,a,'chat',sup),e=>e.code==='42501');
 });
 await check('unread counts reflect only other users, skip deleted, and honor the local cursor',async()=>{
   await db.exec('reset role');const stamp=new Date();
   await q('update public.youth_memberships set updated_at=$1 where user_id=$2 and youth_id=$3',[new Date(stamp.getTime()-20000).toISOString(),member,a]);
   await q(`insert into public.chat_messages(room_id,author_id,client_nonce,body,created_at,deleted_at)values
    ($1,$2,$3,'Новое',$7,null),($1,$4,$5,'Своё',$7,null),($1,$2,$6,'Удалено',$7,$7)`,[existing,leader,id(seq++),member,id(seq++),id(seq++),new Date(stamp.getTime()-1000).toISOString()]);
   await login(member);let d=await dash(a,{[existing]:new Date(stamp.getTime()-2000).toISOString()});assert.equal(d.chats.find(r=>r.id===existing).unread_count,1);
   d=await dash(a,{[existing]:stamp.toISOString()});assert.equal(d.chats.find(r=>r.id===existing).unread_count,0);
   assert((await dash()).chats.find(r=>r.id===existing).unread_count>=1);
 });
 await check('delete denies old URLs/messages, removes pins, rejects stale revision and retries safely',async()=>{
   await login(leader);const row=await chat(existing);await assert.rejects(()=>remove(existing,row.revision-1),e=>e.code==='40001');
   await db.exec('reset role');await q('insert into public.chat_pins(room_id,message_id,pinned_by)select $1,id,$2 from public.chat_messages where room_id=$1 limit 1',[existing,leader]);await login(leader);
   await remove(existing,row.revision);await remove(existing,row.revision);
   assert(!(await dash()).chats.some(r=>r.id===existing));assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[existing]),0);
   await denied('select public.chat_capabilities($1)',[existing]);await denied('select public.send_message($1,$2,$3)',[existing,'Нет',id(seq++)]);
   await db.exec('reset role');assert.equal(await val('select count(*)::int from public.chat_pins where room_id=$1',[existing]),0);
   assert(await val('select count(*)::int from public.chat_messages where room_id=$1',[existing])>0);
 });
 await check('legacy editors cannot resurrect a deleted chat, including superadmin',async()=>{
   await login(sup);const row=await chat(existing);
   await assert.rejects(()=>q('select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)',['chats',existing,pa,a,{title:row.title,body:row.description,kind:'group',access:'parish',sort_order:50,is_archived:false},String(row.revision),sup]),e=>e.message==='chat_unavailable');
 });
 await check('reinstall and seed do not restore renamed/deleted template rooms',async()=>{
   await login(sup);const seeded=(await dash()).chats.find(r=>r.title==='Болталка');await remove(seeded.id,seeded.revision);
   const news=(await dash()).chats.find(r=>r.title==='Важные новости');await edit(news.id,'Новости команды',news.revision,a,'news');
   await db.exec('reset role');await db.exec(sql);await q('select app_private.seed_club_chat_layout($1)',[a]);await login(sup);
   const d=await dash();assert(!d.chats.some(r=>r.id===seeded.id));assert.equal(d.chats.find(r=>r.id===news.id).title,'Новости команды');assert(!d.chats.some(r=>r.title==='Важные новости'));
 });
 await check('new clubs receive the same template once without roles or cross-club data',async()=>{
   await login(sup);await save(id(203));let d=await dash(id(203));assert.equal(d.chats.filter(r=>r.access==='parish').length,13);
   assert(!d.chats.some(r=>r.id===foreign));await save(id(203));d=await dash(id(203));assert.equal(d.chats.filter(r=>r.access==='parish').length,13);
 });
 await check('events and help reuse existing tables; only selected club and published statuses are returned',async()=>{
   await db.exec('reset role');
   await q(`insert into public.events(parish_id,youth_id,title,description,starts_at,ends_at,status,created_by)values
   ($1,$2,'Открытое','Текст',now()+interval '1 hour',now()+interval '2 hours','published',$4),
   ($1,$3,'Чужое','Текст',now()+interval '1 hour',now()+interval '2 hours','published',$4),
   ($1,$2,'Черновик','Текст',now()+interval '1 hour',now()+interval '2 hours','draft',$4),
   ($1,$2,'Отменено','Текст',now()+interval '1 hour',now()+interval '2 hours','cancelled',$4)`,[pa,a,b,sup]);
   await q(`insert into public.help_requests(parish_id,youth_id,author_id,title,description,status)values($1,$2,$4,'Помощь А','Описание','published'),($1,$3,$4,'Помощь Б','Чужое','published'),($1,$2,$4,'Черновик','Текст','draft')`,[pa,a,b,sup]);
   await login(member);const d=await dash();assert.deepEqual(d.events.map(e=>e.title).sort(),['Открытое','Отменено'].sort());assert.deepEqual(d.help.map(h=>h.title),['Помощь А']);
   assert.equal((await q("select title from public.help_requests where title='Помощь Б'")).rows.length,1); // member belongs to B too
   await login(moderator);assert.equal((await q("select title from public.help_requests where title='Помощь Б'")).rows.length,0);
 });
 await check('global guest restriction suspends dashboard, retaining independent club assignments',async()=>{
   await login(sup);await roles(member,[],'guest');await login(member);await assert.rejects(()=>dash(),e=>e.code==='42501');await login(sup);await roles(member,[],'user');
   const d=await details(member);assert.equal(d.clubs.find(g=>g.id===b).role,'youth_moderator');
 });
 console.log(`${count} club-dashboard checks passed.`);
}finally{await db.close();}
