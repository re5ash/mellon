import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');const db=new PGlite();
const q=(sql,args=[])=>db.query(sql,args);const val=async(sql,args=[])=>Object.values((await q(sql,args)).rows[0])[0];
const id=n=>`d0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [superuser,admin,leader,moderator,member,active,peer,foreign]=[1,2,3,4,5,6,7,8].map(id);
const [parish,other,youth,sibling,far,room,peerroom]=[101,102,201,202,203,301,302].map(id);
let count=0;let actor;
async function login(user){actor=user;await db.exec(`reset role; select set_config('request.jwt.claim.sub','${user??''}',false);set role ${user?'authenticated':'anon'};`);}
async function check(title,fn){await fn();count++;console.log('PASS '+title);}
const denied=(sql,args=[],code='42501')=>assert.rejects(()=>q(sql,args),e=>e.code===code);
const grant=(user,role,group=youth,pa=parish)=>q('select public.assign_scoped_role($1,$2,$3,$4)',[user,role,pa,group]);
const setMember=(user,group=youth,activist=false,rev=0,joined=true)=>q('select public.set_youth_member($1,$2,$3,$4,$5)',[group,user,joined,activist,rev]);
const contentSql='select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)';
const content=(kind,key,data,expected=null,group=youth,pa=parish)=>q(contentSql,[kind,key,pa,group,data,expected,actor]);
const chat={title:'Чат',body:'Описание',kind:'group',access:'parish',sort_order:100,is_archived:false};
const event={title:'Встреча',body:'Приглашаем',status:'published',visibility:'parish',starts_at:'2030-01-01T10:00:00Z',ends_at:'2030-01-01T12:00:00Z',location:'Дом прихода'};
try{
 await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;`);
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
 await db.exec(`insert into auth.users(id,email) values ${[superuser,admin,leader,moderator,member,active,peer,foreign].map((u,i)=>`('${u}','person${i}@example.test')`).join(',')};
 insert into public.cities(id,name,country_code)values('${id(100)}','Город','RU');
 insert into public.parishes(id,city_id,slug,name,is_published)values('${parish}','${id(100)}','a','Приход А',true),('${other}','${id(100)}','b','Приход Б',true);
 insert into public.memberships(user_id,parish_id,status)values ${[admin,leader,moderator,member,active,peer].map(u=>`('${u}','${parish}','active')`).join(',')},('${foreign}','${other}','active');
 insert into app_private.role_assignments(user_id,role_id)select '${superuser}',id from app_private.roles where key='super_admin';
 insert into app_private.role_assignments(user_id,role_id,parish_id)select '${admin}',id,'${parish}' from app_private.roles where key='parish_admin';`);
 await login(admin);
 for(const [g,name]of[[youth,'Первая'],[sibling,'Вторая']])await q('select public.save_youth_group($1,$2,$3,$4,false,0)',[g,parish,name,'']);
 for(const u of[leader,moderator,member,active])await setMember(u,youth,u===active);
 await setMember(peer,sibling);await grant(leader,'youth_leader');await grant(moderator,'youth_moderator');
 await content('chats',room,chat);await content('chats',peerroom,chat,null,sibling);
 const activeRoom=await val("select id from public.chat_rooms where youth_id=$1 and access='active'",[youth]);
 await check('parish admin cannot create a foreign youth or grant global authority',async()=>{
 await denied('select public.save_youth_group($1,$2,$3,$4,false,0)',[far,other,'Чужая','']);
 await denied('select public.assign_scoped_role($1,$2,null,null)',[admin,'super_admin']);
 await denied('select public.assign_scoped_role($1,$2,$3,null)',[foreign,'parish_admin',other]);});
 await login(leader);
 await check('leader has group rights without rights over whole parish or sibling',async()=>{
 assert.equal(await val("select app_private.has_scope_permission('chats.create',$1,$2)",[parish,youth]),true);
 assert.equal(await val("select app_private.has_permission('chats.manage',$1)",[parish]),false);
 assert.equal(await val('select count(*)::int from public.admin_parishes()'),0);
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[peerroom]),0);
 await denied(contentSql,['chats',id(390),parish,sibling,chat,null,leader]);});
 await check('leader may assign a moderator but cannot escalate to leader or parish admin',async()=>{
 await grant(member,'youth_moderator');await denied('select public.assign_scoped_role($1,$2,$3,$4)',[member,'youth_leader',parish,youth]);
 await denied('select public.assign_scoped_role($1,$2,$3,null)',[member,'parish_admin',parish]);
 const assignments=(await q('select * from public.scope_members($1,$2)',[parish,youth])).rows.find(r=>r.user_id===member).assignments;
 await q('select public.revoke_role($1)',[assignments[0].id]);});
 await check('leader can read active chat and create youth posts and events',async()=>{
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),1);
 await content('posts',id(401),{title:'Новость',body:'Текст',status:'published',visibility:'parish'});await content('events',id(501),event);});
 await login(moderator);
 await check('moderator can edit events, cannot delete/archive them or create chats',async()=>{
 await content('events',id(502),event);
 let revision=await val('select updated_at from public.events where id=$1',[id(502)]);
 await content('events',id(502),{...event,title:'Изменено'},revision);
 await denied(contentSql,['events',id(502),parish,youth,{...event,status:'archived'},revision,moderator]);
 await denied('select public.delete_scope_content($1,$2,$3,$4,$5,$6)',['events',id(502),parish,youth,revision,moderator]);
 await denied(contentSql,['chats',id(303),parish,youth,chat,null,moderator]);
 await denied("update public.events set status='archived' where id=$1",[id(502)]);
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),0);});
 await login(member);
 await check('member sees own youth content, not sibling or active chat',async()=>{
 assert.equal(await val('select count(*)::int from public.my_youth()'),1);
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[room]),1);
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[peerroom]),0);
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),0);
 assert.equal(await val('select count(*)::int from public.posts where id=$1',[id(401)]),1);
 await denied('select * from public.scope_members($1,$2)',[parish,youth]);});
 await login(active);assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),1);
 await login(superuser);await db.exec('reset role');
 for(let n=0;n<65;n++)await q('insert into public.chat_messages(id,room_id,author_id,client_nonce,body,created_at)values($1,$2,$3,$4,$5,$6)',[id(600+n),room,n%2?member:peer,id(700+n),'Сообщение '+n,new Date(Date.UTC(2020,0,1,0,n)).toISOString()]);
 await q('insert into public.chat_messages(id,room_id,author_id,client_nonce,body)values($1,$2,$3,$4,$5)',[id(800),peerroom,peer,id(801),'Чужая группа']);
 await login(member);
 await check('member can delete own message; deleting other or pinning is forbidden',async()=>{
 await q('select public.delete_chat_message($1,$2)',[id(601),member]);
 assert.equal(await val('select body from public.chat_messages where id=$1',[id(601)]),'Сообщение удалено');
 await denied('select public.delete_chat_message($1,$2)',[id(602),member]);
 await denied('select public.set_chat_pin($1,$2,$3)',[room,id(602),member]);});
 await login(moderator);
 await check('moderator pins older message and history locates it outside latest 50',async()=>{
 const latest=(await q('select * from public.chat_history($1)',[room])).rows;assert.equal(latest.length,50);assert(!latest.some(x=>x.id===id(602)));
 await q('select public.set_chat_pin($1,$2,$3)',[room,id(602),moderator]);assert.equal((await val('select public.current_chat_pin($1)',[room])).message_id,id(602));
 assert.equal((await q('select * from public.chat_history($1,null,null,$2)',[room,id(602)])).rows[0].id,id(602));
 await denied('select public.set_chat_pin($1,$2,$3)',[room,id(800),moderator],'22023');
 await denied('select public.delete_chat_message($1,$2)',[id(800),moderator]);
 await denied('select public.delete_chat_message($1,$2)',[id(602),member]);});
 await check('deleting pinned message removes pin and scrubs content; retry is safe',async()=>{
 await q('select public.delete_chat_message($1,$2)',[id(602),moderator]);await q('select public.delete_chat_message($1,$2)',[id(602),moderator]);assert.equal(await val('select public.current_chat_pin($1)',[room]),null);await denied('select public.set_chat_pin($1,$2,$3)',[room,id(602),moderator],'22023');});
 await login(leader);
 await check('active status revocation closes private chat immediately',async()=>{await setMember(active,youth,false,1);await login(active);assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),0);});
 await login(admin);const moderatorAssignment=await val("select public.assign_scoped_role($1,'youth_moderator',$2,$3)",[moderator,parish,youth]);await q('select public.revoke_role($1)',[moderatorAssignment]);await login(moderator);
 await check('role revocation takes effect without JWT refresh',async()=>{await denied('select public.set_chat_pin($1,$2,$3)',[room,id(603),moderator]);assert.equal((await val('select public.chat_capabilities($1)',[room])).pin,false);});
 await login(admin);
 await check('leaving youth removes roles and restricted invitations; rejoin does not restore role',async()=>{
 await grant(member,'youth_moderator');await setMember(member,youth,false,1,false);await setMember(member,youth,false,2,true);await login(member);assert.equal((await val('select public.chat_capabilities($1)',[room])).pin,false);});
 await login(peer);
 await check('sibling participant cannot read private news, history, pin or youth events',async()=>{assert.equal(await val('select count(*)::int from public.posts where id=$1',[id(401)]),0);assert.equal(await val('select count(*)::int from public.events where id=$1',[id(501)]),0);await denied('select * from public.chat_history($1)',[room]);await denied('select public.current_chat_pin($1)',[room]);});
 await login(superuser);
 await check('superadmin controls groups without membership; last superadmin cannot be removed',async()=>{
 assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[activeRoom]),1);
 const assignment=await val("select public.assign_scoped_role($1,'super_admin',null,null)",[superuser]);await denied('select public.revoke_role($1)',[assignment],'23514');
 await q('select public.save_app_configuration($1,$2,$3,1)',['Мой приход','Вместе','help@example.test']);});
 await check('chat creation is independent and cannot be bypassed with legacy RPC',async()=>{
 await q("select public.define_role('chat_editor_v2','Редактор','parish',array['chats.manage'])");await grant(member,'chat_editor_v2',null);
 await login(member);await denied('select public.admin_save_chat($1,$2,true,$3,$4,$5,$6,100,false,null,$7)',[id(900),parish,'Чат','','group','chat',member]);
 await login(superuser);await q("select public.define_role('chat_creator','Создатель','youth',array['chat.read','chats.create'])");await grant(moderator,'chat_creator');await login(moderator);await content('chats',id(901),chat);await content('chats',id(901),chat);await denied(contentSql,['chats',id(901),parish,youth,{...chat,title:'Недопустимое изменение'},'1',moderator]);});
 await login(member);
 await check('phone remains private, avatar requires own uploaded object and optimistic revision',async()=>{
 const p=await val('select public.my_profile_v2()');assert.equal(p.email,'person4@example.test');
 const saved=await val('select public.save_my_profile_v2($1,$2,$3,$4,$5,$6,$7,$8,$9)',['Иван','private','Иван','Иванов','2000-01-01',p.profile_revision,p.private_revision,member,'+7 900 123-45-67']);assert.equal(saved.phone,'+7 900 123-45-67');
 await denied('select phone from app_private.profile_private');
 await denied('select public.set_profile_avatar($1,$2,$3)',[`${member}/missing.jpg`,saved.profile_revision,member],'22023');
 await q("insert into storage.objects(bucket_id,name)values('profile-avatars',$1)",[`${member}/one.jpg`]);
 const next=await val('select public.set_profile_avatar($1,$2,$3)',[`${member}/one.jpg`,saved.profile_revision,member]);assert.equal(next.avatar_path,`${member}/one.jpg`);
 await denied('select public.set_profile_avatar(null,$1,$2)',[saved.profile_revision,member],'40001');
 await denied('select public.set_profile_avatar(null,$1,$2)',[next.profile_revision,peer]);
 await q("delete from storage.objects where bucket_id='profile-avatars' and name=$1",[`${member}/one.jpg`]);assert.equal(await val('select count(*)::int from storage.objects'),1);
 await val('select public.set_profile_avatar(null,$1,$2)',[next.profile_revision,member]);await q("delete from storage.objects where bucket_id='profile-avatars' and name=$1",[`${member}/one.jpg`]);assert.equal(await val('select count(*)::int from storage.objects'),0);
 await denied("insert into storage.objects(bucket_id,name)values('profile-avatars',$1)",[`${peer}/other.jpg`]);});
 await login(null);
 await check('guests can read public configuration and groups but no administration or private messages',async()=>{
 assert.equal(await val('select welcome_text from public.app_configuration'),'Вместе');assert.equal(await val('select count(*)::int from public.youth_groups'),2);
 await denied('select public.my_profile_v2()');await denied('select * from public.chat_messages');await denied('select public.my_youth()');await denied('select public.save_app_configuration($1,$2,$3,2)',['Bad','','']);});
 console.log(`RESULT: ${count} community security checks passed (PGlite, mocked Auth/Storage schema; no live services).`);
}finally{await db.close();}
