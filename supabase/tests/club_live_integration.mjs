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
 const unread=async()=> (await dash()).chats.find(c=>c.id===existing).unread_count;
 const mark=(message,stamp,room=existing,expected=actor)=>q('select public.mark_chat_read($1,$2,$3,$4)',[room,stamp,expected,message]);
 const info=(kind,record,title,club=a,expected=null)=>val('select public.save_club_information($1,$2,$3,$4,$5,$6)',[club,record,kind,{title,description:'Описание',starts_at:'2090-01-01T10:00:00Z',ends_at:'2090-01-01T11:00:00Z',location:'Зал'},expected,actor]);
 await check('outsider sees basic card only; legacy parish rights do not bypass membership',async()=>{
   await db.exec('reset role');await q('insert into auth.users(id,email,email_confirmed_at)values($1,$2,now())',[newcomer,'new@example.test']);
   for(const u of [newcomer,legacyAdmin]){await login(u);const e=await val('select public.club_entry($1)',[a]);assert.equal(e.can_open,false);assert.equal(e.can_edit_photo,false);await denied('select public.club_dashboard($1)',[a]);assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[existing]),0);await denied('select public.send_message($1,$2,$3)',[existing,'Нельзя',id(seq++)]);}
   await login(null);await denied('select public.club_entry($1)',[a]);
 });
 await check('database unread cursor is private, monotonic, ignores deleted/own and forged local cursors',async()=>{
   await db.exec('reset role');
   const stamp=new Date(Date.now()-1000).toISOString();
   // The cutoff predates new messages; updating unrelated membership fields must preserve it.
   await db.exec('alter table public.youth_memberships disable trigger club_membership_dates');
   await q('update public.youth_memberships set joined_at=$1 where youth_id=$2',[new Date(Date.now()-10000).toISOString(),a]);
   await db.exec('alter table public.youth_memberships enable trigger club_membership_dates');
   for(const [n,u,deleted] of [[801,leader,false],[802,leader,false],[803,member,false],[804,leader,true]])await q('insert into public.chat_messages(id,room_id,author_id,body,client_nonce,created_at,deleted_at)values($1,$2,$3,$4,$5,$6,$7)',[id(n),existing,u,`Сообщение ${n}`,id(seq++),stamp,deleted?stamp:null]);
   await login(member);assert.equal(await unread(),2);
   assert.equal((await dash(a,{[existing]:'2099-01-01T00:00:00Z'})).chats.find(c=>c.id===existing).unread_count,2);
   await mark(id(801),stamp);assert.equal(await unread(),1); // Equal timestamps still have distinct cursors.
   await mark(id(802),stamp);assert.equal(await unread(),0);
   await mark(id(801),stamp);assert.equal(await unread(),0);
   await login(member);assert.equal(await unread(),0);assert.equal(Object.keys(await val('select public.my_chat_reads($1)',[member])).length,1);
   await denied('select public.my_chat_reads($1)',[leader]);
   await denied('insert into public.club_chat_reads(user_id,room_id,read_at,read_message_id)values($1,$2,now(),$3)',[leader,existing,id(802)]);
   await login(moderator);assert.equal(await unread(),3);assert.equal(await val('select count(*)::int from public.club_chat_reads'),0);
   await denied('select public.mark_chat_read($1,now(),$2,$3)',[foreign,moderator,id(802)]);
   await db.exec('reset role');const joined=await val('select joined_at from public.youth_memberships where youth_id=$1 and user_id=$2',[a,moderator]);await q('update public.youth_memberships set updated_at=now() where youth_id=$1 and user_id=$2',[a,moderator]);assert.deepEqual(await val('select joined_at from public.youth_memberships where youth_id=$1 and user_id=$2',[a,moderator]),joined);
 });
 await check('only admin, leader, superadmin can manage information; existing write paths obey same rights',async()=>{
   for(const u of [member,moderator]){await login(u);assert.equal((await dash()).can_manage_information,false);for(const kind of ['events','schedule','help'])await denied('select public.save_club_information($1,$2,$3,$4,null,$5)',[a,id(seq++),kind,{title:'Нет'},u]);assert.equal(await val("select app_private.has_scope_permission('events.edit',$1,$2)",[pa,a]),false);}
   for(const [u,n] of [[clubAdmin,810],[leader,811],[sup,812]]){await login(u);assert.equal((await dash()).can_manage_information,true);for(const [i,kind] of ['events','schedule','help'].entries()){const record=id(n*10+i);assert.equal(await info(kind,record,kind),record);assert.equal(await info(kind,record,kind),record);}}
   await login(clubAdmin);await assert.rejects(()=>info('events',id(830),'Чужой',b),e=>e.code==='42501');
   await login(member);const d=await dash();assert.equal(d.events.filter(e=>e.club_section==='schedule').length,3);assert.equal(d.help.length,3);
   const row=d.events[0];await denied('select public.remove_club_information($1,$2,$3,$4,$5)',[a,row.id,row.club_section,row.updated_at,member]);
   await login(leader);await info(row.club_section,row.id,'Новое',a,row.updated_at);await assert.rejects(()=>info(row.club_section,row.id,'Устаревшее',a,row.updated_at),e=>e.code==='40001');
   const updated=(await dash()).events.find(e=>e.id===row.id);await q('select public.remove_club_information($1,$2,$3,$4,$5)',[a,row.id,row.club_section,updated.updated_at,leader]);assert(!(await dash()).events.some(e=>e.id===row.id));
 });
 const photoPath=`${a}/${clubAdmin}/${id(850)}.png`;
 await check('club photos require admin/superadmin, scope, storage policy, expected actor and revision',async()=>{
   for(const u of [member,moderator,leader]){await login(u);assert.equal((await dash()).club.can_edit_photo,false);await denied("insert into storage.objects(bucket_id,name)values('club-photos',$1)",[`${a}/${u}/${id(seq++)}.png`]);await denied('select public.set_club_photo($1,$2,0,$3)',[a,photoPath,u]);}
   await login(clubAdmin);assert.equal((await dash()).club.can_edit_photo,true);
   await denied("insert into storage.objects(bucket_id,name)values('club-photos',$1)",[`${b}/${clubAdmin}/${id(seq++)}.png`]);
   await q("insert into storage.objects(bucket_id,name)values('club-photos',$1)",[photoPath]);
   await denied('select public.set_club_photo($1,$2,0,$3)',[a,photoPath,sup]);
   const photo=await val('select public.set_club_photo($1,$2,0,$3)',[a,photoPath,clubAdmin]);assert.equal(photo.photo_revision,1);
   assert.equal((await val('select public.set_club_photo($1,$2,0,$3)',[a,photoPath,clubAdmin])).photo_revision,1);
   await q("delete from storage.objects where bucket_id='club-photos' and name=$1",[photoPath]);assert.equal(await val("select count(*)::int from storage.objects where name=$1",[photoPath]),1);
   const next=`${a}/${clubAdmin}/${id(851)}.png`;await q("insert into storage.objects(bucket_id,name)values('club-photos',$1)",[next]);await assert.rejects(()=>q('select public.set_club_photo($1,$2,0,$3)',[a,next,clubAdmin]),e=>e.code==='40001');
   await login(newcomer);assert.equal(await val("select count(*)::int from storage.objects where name=$1",[photoPath]),1);assert.equal(await val("select count(*)::int from storage.objects where name=$1",[next]),0);
   await login(sup);const own=`${b}/${sup}/${id(852)}.png`;await q("insert into storage.objects(bucket_id,name)values('club-photos',$1)",[own]);assert.equal((await val('select public.set_club_photo($1,$2,0,$3)',[b,own,sup])).photo_path,own);
 });
 await check('leave is idempotent and revokes only selected club including old chat URLs',async()=>{
   await login(sup);const before=(await details(member)).clubs.find(c=>c.id===b).role;
   await login(member);await denied('select public.leave_youth_club($1,$2)',[a,sup]);
   await q('select public.leave_youth_club($1,$2)',[a,member]);await q('select public.leave_youth_club($1,$2)',[a,member]);
   assert.equal((await val('select public.club_entry($1)',[a])).can_open,false);assert.equal((await val('select public.club_entry($1)',[a])).request_status,null);
   await denied('select public.chat_capabilities($1)',[existing]);await denied('select public.club_dashboard($1)',[a]);await denied('select public.send_message($1,$2,$3)',[existing,'Запрещено',id(seq++)]);await dash(b);
   await login(sup);assert.equal((await details(member)).clubs.find(c=>c.id===b).role,before);
 });
 await check('pending request persists, duplicate submit reuses request, approval grants only that club',async()=>{
   await db.exec('reset role');await q("update app_private.profile_private set given_name='Имя',family_name='Фамилия',birth_date='2000-01-01',phone='+79990000000' where user_id=$1",[member]);
   await login(member);const receipt=id(seq++);const requested=await request(a,receipt);assert(requested);assert.equal(await request(a,receipt),requested);assert.equal((await val('select public.club_entry($1)',[a])).request_status,'pending');await denied('select public.club_dashboard($1)',[a]);
   await login(leader);await q('select public.review_youth_join_request($1,$2,$3)',[requested,'accepted',leader]);
   await login(member);assert.equal((await val('select public.club_entry($1)',[a])).can_open,true);await dash();await dash(b);
 });
 await check('revoked photo permission cannot finish stale upload and guest blocks internal access',async()=>{
   await login(sup);await roles(clubAdmin,[{id:a,role:'user'}]);await login(clubAdmin);
   await denied('select public.set_club_photo($1,$2,1,$3)',[a,`${a}/${clubAdmin}/${id(851)}.png`,clubAdmin]);
   await login(sup);await roles(member,[],'guest');await login(member);await denied('select public.club_dashboard($1)',[a]);assert.equal(await val('select count(*)::int from public.events where youth_id=$1',[a]),0);
   await login(sup);await roles(member,[],'user');await login(member);await dash();
 });
 console.log(`${count} club-live checks passed.`);
}finally{await db.close();}
