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
 await db.exec(sql);
 const live=await readFile(path.join(root,'supabase/updates/club_live.sql'),'utf8');
 await check('migration applies twice, roles unchanged',async()=>{await db.exec(live);await db.exec(live);assert.deepEqual((await q('select * from app_private.roles order by key')).rows,snapshot);});

 await db.exec(await readFile(path.join(root,'supabase/updates/map_events.sql'),'utf8'));
 await db.exec('grant usage on schema storage to anon;grant select on storage.objects to anon;');
 const publicationSQL=await readFile(path.join(root,'supabase/updates/feed_publications.sql'),'utf8');
 await check('publication migration is repeatable',async()=>{
   await db.exec(publicationSQL);await db.exec(publicationSQL);
 });
 const payload=(title,publish=false)=>({title,description:'Подробности события',
   starts_at:'2090-01-01T10:00:00Z',ends_at:'2090-01-01T11:00:00Z',location:'Зал',
   publish_to_feed:publish,photo_path:null,icon_id:'people_group',icon_manual:false,
   show_on_map:true,map_latitude:54.723306,map_longitude:20.526467});
 const savePub=(record,kind,data,expected=null,club=a,who=actor)=>val(
   'select public.save_club_publication($1,$2,$3,$4,$5,$6)',[club,record,kind,data,expected,who]);
 const dashboard=()=>val('select public.club_publication_dashboard($1)',[a]);
 const entry=async(record)=>(await dashboard()).events.find(e=>e.id===record);
 const general=()=>q('select * from public.mellon_general_feed order by published_at desc,id desc');
 const visible=async(record)=>(await general()).rows.filter(e=>e.source_id===record);
 const record=id(910),scheduleId=id(911);
 await check('events and schedule are private by default and public only when selected; no duplicates',async()=>{
   for(const [key,kind] of [[record,'events'],[scheduleId,'schedule']]) {
     await login(clubAdmin);await savePub(key,kind,payload(kind));
     assert.equal((await entry(key)).publish_to_feed,false);
     await login(null);assert.equal((await visible(key)).length,0);
     await login(clubAdmin);const current=await entry(key);
     await savePub(key,kind,payload(kind,true),current.updated_at);
     const revision=(await entry(key)).updated_at;
     await savePub(key,kind,payload('Повтор сети',true));
     assert.equal((await entry(key)).updated_at,revision);
     await login(null);assert.equal((await visible(key)).length,1);
     await db.exec('reset role');assert.equal(await val('select count(*)::int from public.posts where id=$1',[key]),0);
   }
 });
 await check('edit propagates; stale writes rejected; unpublish preserves club; delete removes from both',async()=>{
   for(const [key,kind] of [[record,'events'],[scheduleId,'schedule']]) {
     await login(clubAdmin);let row=await entry(key);
     const changed={...payload('Изменено',true),description:'Новое описание',icon_id:'learn_book',icon_manual:true};
     await savePub(key,kind,changed,row.updated_at);
     await assert.rejects(()=>savePub(key,kind,changed,row.updated_at),e=>e.code==='40001');
     row=await entry(key);assert.equal(row.icon_manual,true);assert.equal(row.map_latitude,54.723306);
     await login(null);let feed=(await visible(key))[0];assert.equal(feed.title,'Изменено');assert.equal(feed.icon_id,'learn_book');
     await login(null);const revision=await val('select revision from public.feed_publication_changes');
     await login(clubAdmin);await savePub(key,kind,{...changed,publish_to_feed:false},row.updated_at);
     await login(null);assert(Number(await val('select revision from public.feed_publication_changes'))>Number(revision));
     await login(clubAdmin);
     assert(await entry(key));await login(null);assert.equal((await visible(key)).length,0);
     await login(clubAdmin);row=await entry(key);await savePub(key,kind,changed,row.updated_at);
     row=await entry(key);await q('select public.remove_club_information($1,$2,$3,$4,$5)',[a,key,kind,row.updated_at,actor]);
     assert.equal(await entry(key),undefined);await login(null);assert.equal((await visible(key)).length,0);
   }
 });
 await check('authorization enforces actor, club and mutation permissions',async()=>{
   await login(member);await denied('select public.save_club_publication($1,$2,$3,$4,$5,$6)',[a,id(940),'events',payload('Нельзя',true),null,member]);
   await login(clubAdmin);await assert.rejects(()=>savePub(id(941),'events',payload('Чужой клуб',true),null,b),e=>e.code==='42501');
   await assert.rejects(()=>savePub(id(942),'events',payload('Подмена',true),null,a,sup),e=>e.code==='42501');
   await login(null);await denied('select public.club_publication_dashboard($1)',[a]);
   await denied('select public.save_club_publication($1,$2,$3,$4,$5,$6)',[a,id(943),'events',payload('Нет входа'),null,clubAdmin]);
 });
 await check('photo uploads respect club scope; public read tracks the one event',async()=>{
   const key=id(950),photo=`${a}/${key}/${id(951)}.png`;
   await login(member);await denied("insert into storage.objects(bucket_id,name) values('event-photos',$1)",[photo]);
   await login(clubAdmin);await q("insert into storage.objects(bucket_id,name) values('event-photos',$1)",[photo]);
   await savePub(key,'events',{...payload('С фото'),photo_path:photo});
   await login(null);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='event-photos' and name=$1",[photo]),0);
   await login(clubAdmin);await savePub(key,'events',{...payload('С фото',true),photo_path:photo},(await entry(key)).updated_at);
   await login(null);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='event-photos' and name=$1",[photo]),1);
   assert.equal((await visible(key))[0].photo_path,photo);
   await login(clubAdmin);await savePub(key,'events',{...payload('Без фото',true),photo_path:null},(await entry(key)).updated_at);
   await login(null);assert.equal((await visible(key))[0].photo_path,null);
   assert.equal(await val("select count(*)::int from storage.objects where bucket_id='event-photos' and name=$1",[photo]),0);
   await login(clubAdmin);await assert.rejects(()=>savePub(id(952),'events',{...payload('Чужое фото',true),photo_path:photo}),e=>e.code==='22023');
 });
 await check('equal timestamps and different source IDs paginate without gaps or duplicates',async()=>{
   await db.exec('reset role');
   await q(`insert into public.posts(id,parish_id,author_id,title,body,status,visibility,published_at)
     values($1,$2,$3,'Публикация','Текст','published','public',now())`,[id(950),pa,sup]);
   await q('update public.events set feed_published_at=(select published_at from public.posts where id=$1) where id=$1',[id(950)]);
   await login(null);const rows=(await general()).rows;
   assert.equal(rows.filter(e=>e.source_id===id(950)).length,2);
   const ids=[];let stamp=null,last=null;
   for(let i=0;i<10;i++) {
     const result=await q('select * from public.mellon_general_feed where $1::timestamptz is null or (published_at,id)<($1::timestamptz,$2::text) order by published_at desc,id desc limit 1',[stamp,last]);
     if(!result.rows.length) break;const row=result.rows[0];ids.push(row.id);stamp=row.published_at;last=row.id;
   }
   assert.deepEqual(ids,rows.map(r=>r.id));assert.equal(ids.length,new Set(ids).size);
 });
 console.log(`${count} database scenarios passed`);
}finally{await db.close();}
