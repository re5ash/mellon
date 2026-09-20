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
let count=0;let actor;let req=9000;
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
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')&&f<'202609120015').sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
 const install=await readFile(path.join(root,'supabase/updates/role_manager.sql'),'utf8');
 await db.exec(install);await db.exec(install);
 assert.equal(await val("select count(*)::int from app_private.installed_features where feature='role_manager_20260912'"),1);
 console.log('PASS SQL Editor update applied twice without duplicate state');
 const originalRoles=JSON.stringify((await q('select * from app_private.roles order by id')).rows);
 const catalogInstall=await readFile(path.join(root,'supabase/updates/dynamic_role_catalog.sql'),'utf8');
 await db.exec(catalogInstall);await db.exec(catalogInstall);
 assert.equal(JSON.stringify((await q('select * from app_private.roles order by id')).rows),originalRoles);
 console.log('PASS catalog migration is repeatable and does not create or rename roles');
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')&&f>'202609120016_dynamic_role_catalog.sql').sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
 await db.exec(`insert into auth.users(id,email) values ${[superuser,admin,leader,moderator,member,active,peer,foreign].map((u,i)=>`('${u}','person${i}@example.test')`).join(',')};
 insert into public.cities(id,name,country_code)values('${id(100)}','Город','RU');
 insert into public.parishes(id,city_id,slug,name,is_published)values('${parish}','${id(100)}','a','Приход А',true),('${other}','${id(100)}','b','Приход Б',true);
 insert into public.memberships(user_id,parish_id,status)values ${[admin,leader,moderator,member,active,peer].map(u=>`('${u}','${parish}','active')`).join(',')},('${foreign}','${other}','active');
 insert into app_private.role_assignments(user_id,role_id)select '${superuser}',id from app_private.roles where key='super_admin';
 insert into app_private.role_assignments(user_id,role_id,parish_id)select '${admin}',id,'${parish}' from app_private.roles where key='parish_admin';`);

 await db.exec(`insert into public.youth_groups(id,parish_id,name,created_by) values('${youth}','${parish}','Клуб А','${superuser}'),('${sibling}','${parish}','Клуб Б','${superuser}'),('${far}','${other}','Клуб В','${superuser}');`);
 const details=user=>val('select public.role_manager_person_v2($1)',[user]);
 const save=async(user,global,clubs,options={})=>{
   const revision=options.revision??(await details(user)).revision;
   return val('select public.save_person_roles_v2($1,$2,$3,$4,$5,$6)',[user,global,clubs,revision,options.request??id(req++),options.actor??actor]);
 };
 const patch=(club,role)=>({id:club,role});
 await login(superuser);
 await check('superadmin sees all people and all clubs; no parish block or invented roles',async()=>{
 assert.equal((await q("select * from public.role_manager_people()" )).rows.length,8);
 const d=await details(member);assert.equal(d.clubs.length,3);assert.equal(d.global_role,'user');assert.equal(d.can_global,true);assert(!('parish' in d));
 });
 await check('name search and cursor pagination',async()=>{
 await db.exec('reset role');await q("update public.profiles set display_name='Иван Иванов' where id=$1",[member]);await login(superuser);
 assert.equal((await q("select * from public.role_manager_people('ИВАН')")).rows[0].user_id,member);
 assert.equal((await q('select * from public.role_manager_people($1,$2)',['',foreign])).rows.length,0);
 });
 await check('independent clubs across parishes without granting parish membership',async()=>{
 await save(member,null,[patch(youth,'youth_moderator'),patch(far,'user')]);
 await login(member);assert.equal(await val('select count(*)::int from public.my_youth()'),2);
 assert.equal(await val("select app_private.has_scope_permission('messages.pin',$1,$2)",[parish,youth]),true);
 assert.equal(await val("select app_private.has_scope_permission('messages.pin',$1,$2)",[other,far]),false);
 assert.equal(await val("select app_private.has_permission('parish.read',$1)",[other]),false);
 assert((await val('select public.my_profile_v2()')).youth_name.includes('Клуб В','${superuser}'));
 });
 await login(superuser);
 await check('changing one club keeps other clubs and active status',async()=>{
 await db.exec('reset role');await q('update public.youth_memberships set is_activist=true where user_id=$1 and youth_id=$2',[member,youth]);await login(superuser);
 await save(member,null,[patch(far,'youth_moderator')]);
 const d=await details(member);assert.equal(d.clubs.find(c=>c.id===youth).role,'youth_moderator');
 await db.exec('reset role');assert.equal(await val('select is_activist from public.youth_memberships where user_id=$1 and youth_id=$2',[member,youth]),true);await login(superuser);
 });
 await check('role replacement removes only selected club grants',async()=>{
 await save(member,null,[patch(youth,'user')]);const d=await details(member);
 assert.equal(d.clubs.find(c=>c.id===youth).role,'user');assert.equal(d.clubs.find(c=>c.id===far).role,'youth_moderator');
 });
 await check('guest restriction retains account and club roles, blocks private rights immediately',async()=>{
 await save(member,'guest',[]);let d=await details(member);assert.equal(d.global_role,'guest');assert.equal(d.clubs.find(c=>c.id===far).role,'youth_moderator');
 await login(member);assert.equal((await val('select public.my_account_access()')).restricted_guest,true);
 assert.equal(await val('select count(*)::int from public.my_youth()'),0);
 assert.equal(await val('select count(*)::int from public.memberships'),0);
 for(const [pa,club] of [[parish,youth],[other,far]]) {
 for(const perm of ['chat.read','chat.send','messages.pin','events.edit','youth.roles.manage']) assert.equal(await val('select app_private.has_scope_permission($1,$2,$3)',[perm,pa,club]),false);
 }
 assert.equal(await val("select app_private.has_permission('public.read')"),true);
 assert.equal(await val('select count(*)::int from public.parishes'),2);
 await denied('select public.role_manager_person_v2($1)',[peer]);
 await db.exec('reset role');assert.equal(await val('select count(*)::int from auth.users where id=$1',[member]),1);
 assert.equal(await val('select count(*)::int from public.youth_memberships where user_id=$1 and is_member',[member]),2);
 await login(superuser);
 });
 await check('restoring global participant reactivates saved club settings',async()=>{
 await save(member,'user',[]);await login(member);assert.equal(await val('select count(*)::int from public.my_youth()'),2);
 assert.equal(await val("select app_private.has_scope_permission('messages.pin',$1,$2)",[other,far]),true);await login(superuser);
 });
 await check('last effective superadmin cannot be downgraded or made guest',async()=>{
 for(const role of ['guest','user'])await assert.rejects(()=>save(superuser,role,[]),e=>e.message==='last_super_admin');
 });
 await check('guest is rejected as a club role; invalid patches are fully atomic',async()=>{
 const before=await details(member);
 await assert.rejects(()=>save(member,'guest',[patch(sibling,'user'),patch(far,'guest')]),e=>e.message==='invalid_role');
 assert.equal((await details(member)).revision,before.revision);
 });
 await check('archived club changes and duplicate club patches are rejected',async()=>{
 await db.exec('reset role');await q('update public.youth_groups set is_archived=true where id=$1',[sibling]);await login(superuser);
 await assert.rejects(()=>save(member,null,[patch(sibling,'user')]),e=>e.message==='club_unavailable');
 await assert.rejects(()=>save(member,null,[patch(youth,'user'),patch(youth,'youth_leader')]),e=>e.message==='invalid_role');
 await db.exec('reset role');await q('update public.youth_groups set is_archived=false where id=$1',[sibling]);await login(superuser);
 });
 await check('same request retries safely, changed payload does not reuse receipt',async()=>{
 const options={revision:(await details(member)).revision,request:id(req++)};
 await save(member,null,[patch(youth,'youth_moderator')],options);
 const after=(await details(member)).revision;
 await save(member,null,[patch(youth,'youth_moderator')],options);assert.equal((await details(member)).revision,after);
 await assert.rejects(()=>save(member,'guest',[],options),e=>e.message==='role_request_conflict');
 });
 await check('stale editor cannot overwrite newer settings',async()=>{
 const revision=(await details(member)).revision;
 await save(member,null,[patch(youth,'user')]);
 await assert.rejects(()=>save(member,null,[patch(far,'user')],{revision}),e=>e.message==='role_edit_conflict');
 assert.equal((await details(member)).clubs.find(c=>c.id===far).role,'youth_moderator');
 });
 await check('request cannot execute after actor changes',async()=>{
 await assert.rejects(()=>save(member,'guest',[],{actor:leader}),e=>e.code==='42501');
 });
 await save(leader,null,[patch(youth,'youth_leader')]);
 await login(leader);
 await check('leader sees managed people, but unrelated club membership stays private',async()=>{
 const d=await details(member);assert.equal(d.can_global,false);assert.equal(d.clubs.find(c=>c.id===far).role,null);assert.equal(d.clubs.find(c=>c.id===far).can_edit,false);
 await denied('select public.role_manager_person_v2($1)',[foreign]);
 });
 await check('leader assigns moderator/member only in own club without global escalation',async()=>{
 await save(member,null,[patch(youth,'youth_moderator')]);await save(member,null,[patch(youth,'user')]);
 for(const role of ['super_admin','user','guest'])await assert.rejects(()=>save(member,role,[]),e=>e.code==='42501');
 await assert.rejects(()=>save(member,null,[patch(youth,'youth_leader')]),e=>e.code==='42501');
 await assert.rejects(()=>save(leader,null,[patch(youth,'user')]),e=>e.code==='42501');
 await assert.rejects(()=>save(member,null,[patch(sibling,'user')]),e=>e.code==='42501');
 });
 await login(superuser);await save(moderator,null,[patch(youth,'youth_moderator')]);
 await check('member/moderator/anonymous cannot open role management',async()=>{
 for(const u of [member,moderator,null]) { await login(u);await denied('select * from public.role_manager_people()');await denied('select public.role_manager_person_v2($1)',[leader]); }
 });
 await login(superuser);
 await check('avatar manager policy uses exact profile path and respects authority',async()=>{
 await db.exec('reset role');await q("insert into storage.objects(bucket_id,name) values('profile-avatars',$1),('profile-avatars',$2)",[`${member}/avatar.png`,`${member}/unused.png`]);
 await q('update public.profiles set avatar_path=$1 where id=$2',[`${member}/avatar.png`,member]);
 await login(superuser);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='profile-avatars'"),1);
 await login(leader);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='profile-avatars'"),1);
 await login(foreign);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='profile-avatars'"),0);
 await login(superuser);
 });
 await check('ending parish membership preserves independent club roles',async()=>{
 await db.exec('reset role');await q("update public.memberships set status='left',ended_at=now() where user_id=$1",[member]);await login(member);
 assert.equal(await val('select count(*)::int from public.my_youth()'),2);
 assert.equal(await val("select app_private.has_scope_permission('messages.pin',$1,$2)",[other,far]),true);await login(superuser);
 });
 await check('legacy superadmin grant to restricted guest cannot bypass last-admin protection',async()=>{
 await save(peer,'guest',[]);await q("select public.assign_scoped_role($1,'super_admin',null,null)",[peer]);
 const a=await val("select public.assign_scoped_role($1,'super_admin',null,null)",[superuser]);
 await denied('select public.revoke_role($1)',[a],'23514');
 await login(peer);assert.equal((await val('select public.my_account_access()')).super_admin,false);
 });

 await login(superuser);
 await check('catalog reads every existing global and youth role, including custom titles',async()=>{
 await q("select public.define_role('test_global_auditor','Наблюдатель приложения','global',array['audit.read'])");
 await q("select public.define_role('test_club_editor','Редактор событий клуба','youth',array['events.edit'])");
 await q("select public.define_role('test_parish_editor','Редактор прихода','parish',array['events.edit'])");
 const d=await details(member);
 assert(d.global_roles.some(r=>r.key==='test_global_auditor' && r.title==='Наблюдатель приложения' && r.assignable));
 assert(!d.global_roles.some(r=>r.key.startsWith('youth_') || r.key==='test_club_editor' || r.key==='test_parish_editor'));
 for(const c of d.clubs){
 assert(c.roles.some(r=>r.key==='test_club_editor' && r.title==='Редактор событий клуба'));
 assert(c.roles.some(r=>r.key==='user' && r.baseline==='authenticated'));
 assert(!c.roles.some(r=>r.key==='guest'||r.key==='super_admin'||r.key==='test_global_auditor'||r.key==='test_parish_editor'));
 }
 });
 await check('custom role selection survives reload and has actual scoped permissions',async()=>{
 await save(member,'test_global_auditor',[patch(youth,'test_club_editor')]);
 const d=await details(member);assert.equal(d.global_role,'test_global_auditor');assert.equal(d.clubs.find(c=>c.id===youth).role,'test_club_editor');
 assert.equal(d.clubs.find(c=>c.id===far).role,'youth_moderator');
 assert((await q("select * from public.role_manager_people('Иван')")).rows[0].summary.includes('Редактор событий клуба'));
 await login(member);
 assert.equal(await val("select app_private.has_permission('audit.read')"),true);
 assert.equal(await val("select app_private.has_scope_permission('events.edit',$1,$2)",[parish,youth]),true);
 assert.equal(await val("select app_private.has_scope_permission('messages.pin',$1,$2)",[parish,youth]),false);
 await login(superuser);
 });
 await check('only one direct role in each edited scope, other scopes retain exact grants',async()=>{
 await db.exec('reset role');const otherBefore=(await q('select * from app_private.role_assignments where user_id=$1 and youth_id=$2 order by id',[member,far])).rows;await login(superuser);
 await save(member,'super_admin',[patch(youth,'youth_moderator')]);
 await save(member,'test_global_auditor',[patch(youth,'test_club_editor')]);
 await db.exec('reset role');
 assert.equal(await val('select count(*)::int from app_private.role_assignments where user_id=$1 and parish_id is null and youth_id is null',[member]),1);
 assert.equal(await val('select count(*)::int from app_private.role_assignments where user_id=$1 and youth_id=$2',[member,youth]),1);
 assert.deepEqual((await q('select * from app_private.role_assignments where user_id=$1 and youth_id=$2 order by id',[member,far])).rows,otherBefore);
 await login(superuser);
 });
 await check('cross-scope roles and missing roles rejected without any partial update',async()=>{
 for(const [global,clubs] of [[null,[patch(youth,'test_global_auditor')]],['test_club_editor',[]],[null,[patch(youth,'test_parish_editor')]],['missing_role',[]]]){
 const before=(await details(member)).revision;
 await assert.rejects(()=>save(member,global,clubs),e=>e.message==='invalid_role');
 assert.equal((await details(member)).revision,before);
 }
 });
 await check('catalog edits invalidate open drafts and renamed titles load automatically',async()=>{
 const revision=(await details(member)).revision;
 await q("select public.define_role('test_club_editor','Новый заголовок существующей роли','youth',array['events.edit'])");
 await assert.rejects(()=>save(member,null,[patch(youth,'test_club_editor')],{revision}),e=>e.message==='role_edit_conflict');
 assert((await details(member)).clubs.find(c=>c.id===youth).roles.some(r=>r.title==='Новый заголовок существующей роли'));
 });
 await check('leader sees custom options but cannot assign roles beyond own permissions',async()=>{
 await q("select public.define_role('test_club_power','Полные права клуба','youth',array['roles.assign'])");
 await login(leader);
 const c=(await details(member)).clubs.find(c=>c.id===youth);
 assert(c.roles.find(r=>r.key==='test_club_editor').assignable);
 assert(!c.roles.find(r=>r.key==='test_club_power').assignable);
 assert(!c.roles.find(r=>r.key==='youth_leader').assignable);
 await save(member,null,[patch(youth,'test_club_editor')]);
 await assert.rejects(()=>save(member,null,[patch(youth,'test_club_power')]),e=>e.code==='42501');
 await login(superuser);
 });
 await check('multiple legacy grants are reported and consolidated only on explicit save',async()=>{
 await q("select public.assign_scoped_role($1,'youth_moderator',$2,$3)",[member,parish,youth]);
 await q("select public.assign_scoped_role($1,'super_admin',null,null)",[member]);
 const d=await details(member);assert(d.global_multiple_roles);assert(d.clubs.find(c=>c.id===youth).multiple_roles);
 await save(member,null,[patch(far,'user')]);
 assert((await details(member)).global_multiple_roles);assert((await details(member)).clubs.find(c=>c.id===youth).multiple_roles);
 await save(member,'test_global_auditor',[patch(youth,'test_club_editor')]);
 const after=await details(member);assert(!after.global_multiple_roles);assert(!after.clubs.find(c=>c.id===youth).multiple_roles);
 });
 await check('last superadmin protection also rejects a custom global downgrade',async()=>{
 await assert.rejects(()=>save(superuser,'test_global_auditor',[]),e=>e.message==='last_super_admin');
 });
 await check('guest restriction preserves custom club role and account',async()=>{
 await save(member,'guest',[]);assert.equal((await details(member)).clubs.find(c=>c.id===youth).role,'test_club_editor');
 await login(member);assert.equal(await val("select app_private.has_scope_permission('events.edit',$1,$2)",[parish,youth]),false);
 await login(superuser);await save(member,'user',[]);
 });
 await check('all registered profiles are reachable through cursor pagination',async()=>{
 await db.exec('reset role');
 await q(`insert into auth.users(id,email) values ${Array.from({length:65},(_,i)=>`('${id(10000+i)}','page${i}@example.test')`).join(',')}`);
 await login(superuser);let after=null;const seen=new Set();
 while(true){const rows=(await q('select * from public.role_manager_people($1,$2)',['',after])).rows;for(const row of rows.slice(0,30)){assert(!seen.has(row.user_id));seen.add(row.user_id);}if(rows.length<=30)break;after=rows[29].user_id;}
 assert.equal(seen.size,73);
 });
 console.log(`RESULT: ${count} role manager checks passed (PGlite; mocked Auth/Storage, no live services).`);
} finally {await db.close();}
