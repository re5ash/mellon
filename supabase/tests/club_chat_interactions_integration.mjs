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
 const interactionSQL=await readFile(path.join(root,'supabase/updates/club_chat_interactions.sql'),'utf8');
 await check('Block 7 applies twice and preserves feed, rooms and roles',async()=>{
  const beforeRooms=(await q('select * from public.chat_rooms order by id')).rows;
  const feedDefinition=await val("select pg_get_functiondef('public.club_publication_dashboard(uuid)'::regprocedure)");
  await db.exec(interactionSQL);await db.exec(interactionSQL);
  assert.deepEqual((await q('select * from public.chat_rooms order by id')).rows,beforeRooms);
  assert.equal(await val("select pg_get_functiondef('public.club_publication_dashboard(uuid)'::regprocedure)"),feedDefinition);
  assert.deepEqual((await q('select * from app_private.roles order by key')).rows,snapshot);
 });
 const oldMessage=await val('select id from public.chat_messages where room_id=$1 limit 1',[existing]);
 const extra=id(950), foreignMessage=id(951);
 await q(`insert into public.chat_messages(id,room_id,author_id,client_nonce,body,created_at) values
 ($1,$2,$3,$4,'Второе сообщение',now()-interval '2 days'),($5,$6,$3,$7,'Другой клуб',now()-interval '1 day')`,[extra,existing,sup,id(seq++),foreignMessage,foreign,id(seq++)]);
 const interactions=(room=existing,ids=[oldMessage,extra])=>val('select public.chat_interactions($1,$2)',[room,ids]);
 const pin=(message,value=true,room=existing,who=actor)=>q('select public.set_chat_message_pin($1,$2,$3,$4)',[room,message,value,who]);
 const react=(emoji,value=true,room=existing,message=oldMessage,who=actor)=>q('select public.set_chat_reaction($1,$2,$3,$4,$5)',[room,message,emoji,value,who]);
 const meta=(title=null,icon=null,revision=null,room=existing,club=a,who=actor)=>q('select public.edit_club_chat_meta($1,$2,$3,$4,$5,$6)',[club,room,title,icon,revision,who]);
 await check('member can pin several messages and another member can unpin exactly one',async()=>{
  await login(member);assert.equal((await val('select public.chat_capabilities($1)',[existing])).pin,true);
  await pin(oldMessage);await pin(extra);await pin(extra);
  assert.equal((await interactions()).pins.length,2);
  await login(moderator);await pin(extra,false);
  assert.deepEqual((await interactions()).pins.map(p=>p.message_id),[oldMessage]);
  await db.exec('reset role');await db.exec(interactionSQL);await login(member);
  assert.deepEqual((await interactions()).pins.map(p=>p.message_id),[oldMessage]);
 });
 await check('reactions are idempotent, per-user, counted, and emit room revisions',async()=>{
  await login(member);await react('❤️');await react('❤️');
  assert.deepEqual((await interactions()).reactions,[{message_id:oldMessage,emoji:'❤️',count:1,mine:true}]);
  const revision=await val('select revision from public.chat_interaction_changes where room_id=$1',[existing]);
  await login(moderator);await react('❤️');
  assert.equal((await interactions()).reactions[0].count,2);
  assert.ok(await val('select revision from public.chat_interaction_changes where room_id=$1',[existing])>revision);
  await react('❤️',false);assert.equal((await interactions()).reactions[0].mine,false);
  await login(member);assert.equal((await interactions()).reactions[0].mine,true);
  await assert.rejects(()=>react('arbitrary text'),e=>e.code==='22023');
 });
 await check('cross-room targets, guests, spoofed actors and direct writes are rejected',async()=>{
  await login(member);
  await assert.rejects(()=>pin(foreignMessage),e=>e.code==='22023');
  await assert.rejects(()=>react('👍',true,existing,foreignMessage),e=>e.code==='22023');
  await denied('select public.set_chat_reaction($1,$2,$3,true,$4)',[existing,oldMessage,'👍',sup]);
  await denied('insert into public.chat_message_pins(room_id,message_id,pinned_by)values($1,$2,$3)',[existing,extra,member]);
  await login(null);await denied('select public.chat_interactions($1,$2)',[existing,[oldMessage]]);
  await login(legacyAdmin);await denied('select public.set_chat_message_pin($1,$2,true,$3)',[existing,extra,legacyAdmin]);
  await login(moderator);await denied('select public.chat_interactions($1,$2)',[foreign,[foreignMessage]]);
  assert.equal(await val('select count(*)::int from public.chat_message_reactions where room_id=$1',[foreign]),0);
 });
 const replyNonce=id(980);let replyId;
 await check('reply preserves author and snippet, retry has no duplicate, cross-room reply denied',async()=>{
  await login(member);
  await assert.rejects(()=>val('select public.send_chat_reply($1,$2,$3,$4,$5)',[existing,'Ответ',foreignMessage,replyNonce,member]),e=>e.code==='22023');
  const send=()=>val('select to_jsonb(public.send_chat_reply($1,$2,$3,$4,$5))',[existing,'Спасибо',oldMessage,replyNonce,member]);
  const reply=await send();replyId=reply.id;assert.equal(reply.reply_to,oldMessage);assert.equal((await send()).id,replyId);
  const history=await val('select public.chat_history_v2($1)',[existing]);
  assert.equal(history.find(m=>m.id===replyId).reply.id,oldMessage);
  assert.equal(history.find(m=>m.id===replyId).reply.body,'Старое сообщение');
  await assert.rejects(()=>val('select public.send_chat_reply($1,$2,$3,$4,$5)',[existing,'Другой текст',oldMessage,replyNonce,member]),e=>e.code==='22023');
  assert.equal(history.filter(m=>m.id===replyId).length,1);
 });
 await check('member and leader cannot manage chats; administrator and superadministrator can',async()=>{
  for(const u of [member,leader,moderator]){
   await login(u);assert.equal((await dash()).can_manage_chats,false);
   const row=await chat(existing);
   await assert.rejects(()=>meta('Нельзя',null,row.revision),e=>e.code==='42501');
   await assert.rejects(()=>remove(existing,row.revision),e=>e.code==='42501');
  }
  await login(clubAdmin);assert.equal((await dash()).can_manage_chats,true);
  let row=await chat(existing);const originalDescription=row.description;
  await meta('Беседа клуба',null,row.revision);row=await chat(existing);
  await meta(null,'music_4',row.revision);const edited=await chat(existing);
  assert.equal(edited.icon_key,'music_4');assert.equal(edited.title,'Беседа клуба');assert.equal(edited.description,originalDescription);
  await assert.rejects(()=>meta('Устаревшее',null,row.revision),e=>e.code==='40001');
  await assert.rejects(()=>meta(null,'unknown_900',edited.revision),e=>e.code==='22023');
  await login(sup);assert.equal((await dash()).can_manage_chats,true);
  await meta(null,'auto',edited.revision);assert.equal((await chat(existing)).icon_key,'auto');
 });
 await check('existing chat creation permission and idempotent retry survive; later edits require admin',async()=>{
  await login(leader);const created=id(990);
  await edit(created,'Новый чат',null,a,'sport_5');
  await edit(created,'Новый чат',null,a,'sport_5');
  const row=await chat(created);assert.equal(row.icon_key,'sport_5');
  await assert.rejects(()=>edit(created,'Запрещено',row.revision,a,'sport_5'),e=>e.code==='42501');
  await denied('select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)',[
    'chats',created,pa,a,{title:'Обход старым API',body:'Описание',kind:'group',access:'parish',sort_order:50,is_archived:false},String(row.revision),leader]);
 });
 await check('all catalog icons are accepted and invalid values rejected',async()=>{
  await db.exec('reset role');
  for(const topic of ['chat','announcements','news','craft','sport','games','travel','volunteer','help','music','study','books','photo','ideas','youth','church','events'])
   for(let variant=1;variant<=5;variant++)assert.equal(await val('select app_private.valid_chat_icon($1)',[`${topic}_${variant}`]),true);
  assert.equal(await val("select app_private.valid_chat_icon('not-an-icon')"),false);
 });
 await check('deleting a message clears pins/reactions and redacts its reply snippet',async()=>{
  await login(sup);await q('select public.delete_chat_message($1,$2)',[oldMessage,sup]);
  assert.equal((await interactions()).pins.length,0);assert.equal((await interactions()).reactions.length,0);
  const reply=(await val('select public.chat_history_v2($1)',[existing])).find(m=>m.id===replyId);
  assert.equal(reply.reply.deleted,true);assert.equal(reply.reply.body,'Сообщение удалено');
 });
 await check('history uses stable cursor and anchor outside the latest 50',async()=>{
  await db.exec('reset role');
  await q(`insert into public.chat_messages(room_id,author_id,client_nonce,body,created_at)
  select $1,$2,gen_random_uuid(),'История '||n,now()-interval '10 days'+n*interval '1 minute' from generate_series(1,80)n`,[existing,sup]);
  await login(member);const page=await val('select public.chat_history_v2($1)',[existing]);assert.equal(page.length,50);
  const last=page.at(-1);const older=await val('select public.chat_history_v2($1,$2,$3)',[existing,last.created_at,last.id]);
  assert.ok(older.length>0);assert.equal(page.filter(m=>older.some(o=>o.id===m.id)).length,0);
  assert.equal((await val('select public.chat_history_v2($1,null,null,$2)',[existing,older.at(-1).id]))[0].id,older.at(-1).id);
 });
 await check('delete chat hides history and interactions from all participants',async()=>{
  await login(clubAdmin);await remove(existing,(await chat(existing)).revision);
  await login(member);await denied('select public.chat_history_v2($1)',[existing]);await denied('select public.chat_interactions($1,$2)',[existing,[extra]]);
  assert.equal((await dash()).chats.some(r=>r.id===existing),false);
 });
 console.log(`Passed ${count} SQL integration checks`);
} catch(error) { console.error('SQL TEST FAILURE:',error); process.exitCode=1; } finally {await db.close();}
