import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const db=new PGlite();
const q=(sql,args=[])=>db.query(sql,args);
const val=async(sql,args=[])=>Object.values((await q(sql,args)).rows[0])[0];
const id=n=>`e0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [superuser,adminA,adminB,leader,member,farMember,peerAdmin,parishAdmin]=[1,2,3,4,5,6,7,8].map(id);
const [parish,other,a,b,c]=[101,102,201,202,203].map(id);
let actor,req=9000,count=0;
async function login(user){actor=user;await db.exec(`reset role;select set_config('request.jwt.claim.sub','${user??''}',false);set role ${user?'authenticated':'anon'};`);}
async function check(title,fn){await fn();console.log('PASS '+title);count++;}
const denied=(sql,args=[])=>assert.rejects(()=>q(sql,args),e=>e.code==='42501');
const details=user=>val('select public.role_manager_person_v2($1)',[user]);
const patch=(club,role)=>({id:club,role});
const save=async(user,clubs,global=null)=>val('select public.save_person_roles_v2($1,$2,$3,$4,$5,$6)',[user,global,clubs,(await details(user)).revision,id(req++),actor]);
const permission=async(key,club=a,pa=parish)=>(await q('select * from public.my_scope_permissions($1,$2)',[pa,club])).rows.some(r=>r.permission_key===key);
const createChat=(key,club=a,pa=parish)=>q('select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)',[
 'chats',key,pa,club,{title:'Клубный чат',body:'Общение',kind:'group',access:'parish',sort_order:100,is_archived:false},null,actor]);
async function removeMember(user,club=a){
 const rev=await val('select revision from public.youth_memberships where user_id=$1 and youth_id=$2',[user,club]);
 return q('select public.set_youth_member($1,$2,false,false,$3)',[club,user,rev]);
}
try{
 await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;`);
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')&&f<'202609120017').sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
 await db.exec(`insert into auth.users(id,email) values ${[superuser,adminA,adminB,leader,member,farMember,peerAdmin,parishAdmin].map((u,i)=>`('${u}','person${i}@example.test')`).join(',')};
 insert into public.cities(id,name,country_code)values('${id(100)}','Город','RU');
 insert into public.parishes(id,city_id,slug,name,is_published)values('${parish}','${id(100)}','a','Приход А',true),('${other}','${id(100)}','b','Приход Б',true);
 insert into app_private.role_assignments(user_id,role_id)select '${superuser}',id from app_private.roles where key='super_admin';
 insert into public.memberships(user_id,parish_id,status)values('${parishAdmin}','${parish}','active');
 insert into app_private.role_assignments(user_id,role_id,parish_id)select '${parishAdmin}',id,'${parish}' from app_private.roles where key='parish_admin';
 insert into public.youth_groups(id,parish_id,name,created_by)values('${a}','${parish}','Клуб А','${superuser}'),('${b}','${parish}','Клуб Б','${superuser}'),('${c}','${other}','Клуб В','${superuser}');`);
 await login(superuser);
 await save(leader,[patch(a,'youth_leader')]);
 await save(member,[patch(a,'user'),patch(b,'youth_moderator')]);
 await save(adminA,[patch(a,'user'),patch(b,'user')]);
 await save(farMember,[patch(c,'user')]);
 await db.exec('reset role');
 const oldRoles=(await q('select * from app_private.roles order by key')).rows;
 const oldGrants=(await q('select * from app_private.role_assignments order by id')).rows;
 const oldPermissions=(await q('select * from app_private.role_permissions order by role_id,permission_key')).rows;
 const install=await readFile(path.join(root,'supabase/updates/club_administrator.sql'),'utf8');
 await check('wrapper adds one youth role, preserves old catalog and assignments, repeats safely',async()=>{
 await db.exec(install);await db.exec(install);
 assert.equal(await val("select count(*)::int from app_private.installed_features where feature='club_administrator_20260912'"),1);
 assert.equal(await val('select count(*)::int from app_private.roles'),oldRoles.length+1);
 assert.deepEqual((await q("select * from app_private.roles where key<>'youth_admin' order by key")).rows,oldRoles);
 assert.deepEqual((await q('select * from app_private.role_assignments order by id')).rows,oldGrants);
 assert.deepEqual((await q("select rp.* from app_private.role_permissions rp join app_private.roles r on r.id=rp.role_id where r.key<>'youth_admin' order by rp.role_id,rp.permission_key")).rows,oldPermissions);
 assert.equal(await val("select scope from app_private.roles where key='youth_admin'"),'youth');
 });
 await login(superuser);
 await check('administrator appears only in club catalog and is not globally assignable',async()=>{
 const d=await details(member);
 assert(!d.global_roles.some(r=>r.key==='youth_admin'));
 assert(d.clubs.every(g=>g.roles.some(r=>r.key==='youth_admin'&&r.title==='Администратор'&&r.assignable)));
 await assert.rejects(()=>save(member,[],'youth_admin'),e=>e.message==='invalid_role');
 });
 await check('each club has an independent administrator and unrelated roles survive',async()=>{
 await save(adminA,[patch(a,'youth_admin')]);await save(adminB,[patch(b,'youth_admin')]);await save(peerAdmin,[patch(a,'youth_admin')]);
 const d=await details(adminA);
 assert.equal(d.global_role,'user');assert.equal(d.clubs.find(g=>g.id===a).role,'youth_admin');assert.equal(d.clubs.find(g=>g.id===b).role,'user');
 await login(adminA);assert.equal(await val('select count(*)::int from public.memberships'),0);
 });
 await check('club admin gets management entry and own-club rights only',async()=>{
 const access=await val('select public.my_account_access()');assert.equal(access.can_manage_roles,true);assert.equal(access.super_admin,false);
 for(const key of ['youth.roles.manage','chats.create','chats.manage']){
 assert.equal(await permission(key),true);assert.equal(await permission(key,b),false);assert.equal(await permission(key,c,other),false);assert.equal(await permission(key,null),false);
 }
 for(const key of ['roles.manage','roles.assign','settings.manage','youths.manage'])assert.equal(await permission(key),false);
 assert(!(await q('select * from public.role_manager_people()')).rows.some(p=>p.user_id===farMember));
 await denied('select public.role_manager_person_v2($1)',[farMember]);
 });
 await check('administrator promotes and demotes leader/moderator/member without resetting other clubs or global rights',async()=>{
 for(const role of ['youth_leader','youth_moderator','user']){
 await save(member,[patch(a,role)]);
 const d=await details(member);assert.equal(d.clubs.find(g=>g.id===a).role,role);assert.equal(d.global_role,'user');
 await login(member);assert.equal(await permission('messages.pin'),role!=='user');assert.equal(await permission('messages.pin',b),true);await login(adminA);
 }
 const d=await details(member);const options=d.clubs.find(g=>g.id===a).roles;
 assert(options.find(r=>r.key==='youth_leader').assignable);assert(!options.find(r=>r.key==='youth_admin').assignable);
 assert.equal(d.clubs.find(g=>g.id===b).can_edit,false);
 });
 await check('forbidden cross-club/global patches are atomic',async()=>{
 const before=(await details(member)).revision;
 await assert.rejects(()=>save(member,[patch(a,'youth_leader'),patch(b,'user')]),e=>e.code==='42501');
 for(const role of ['super_admin','guest','user'])await assert.rejects(()=>save(member,[],role),e=>e.code==='42501');
 assert.equal((await details(member)).revision,before);
 });
 await check('club administrator cannot grant administrator, revoke peers or remove peers via membership',async()=>{
 await assert.rejects(()=>save(member,[patch(a,'youth_admin')]),e=>e.code==='42501');
 await assert.rejects(()=>save(peerAdmin,[patch(a,'user')]),e=>e.code==='42501');
 await denied('select public.assign_scoped_role($1,$2,$3,$4)',[member,'youth_admin',parish,a]);
 await assert.rejects(()=>removeMember(peerAdmin),e=>e.code==='42501');
 const d=await details(peerAdmin);assert.equal(d.clubs.find(g=>g.id===a).can_edit,false);
 });
 await check('leader cannot elevate itself or downgrade administrator using any role/member endpoint',async()=>{
 await login(leader);
 await assert.rejects(()=>save(leader,[patch(a,'youth_admin')]),e=>e.code==='42501');
 await assert.rejects(()=>save(adminA,[patch(a,'user')]),e=>e.code==='42501');
 await denied('select public.assign_scoped_role($1,$2,$3,$4)',[leader,'youth_admin',parish,a]);
 await assert.rejects(()=>removeMember(adminA),e=>e.code==='42501');
 await db.exec('reset role');const assignment=await val('select a.id from app_private.role_assignments a join app_private.roles r on r.id=a.role_id where a.user_id=$1 and a.youth_id=$2 and r.key=$3',[adminA,a,'youth_admin']);await login(leader);
 await denied('select public.revoke_role($1)',[assignment]);
 await denied('select public.save_person_roles($1,null,$2,$3,$4,$5)',[adminA,[patch(a,'user')],(await val('select public.role_manager_person($1)',[adminA])).revision,id(req++),leader]);
 });
 await check('admin creates and edits chat in own club; other clubs and parish-wide chats are rejected',async()=>{
 await login(adminA);await createChat(id(301));
 assert.equal(await val('select youth_id from public.chat_rooms where id=$1',[id(301)]),a);
 await q('select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)',['chats',id(301),parish,a,{title:'Чат администратора',body:'Общение',kind:'group',access:'parish',sort_order:100,is_archived:false},'1',adminA]);
 assert.equal(await val('select title from public.chat_rooms where id=$1',[id(301)]),'Чат администратора');
 for(const [club,pa] of [[b,parish],[c,other],[null,parish]])await assert.rejects(()=>createChat(id(req++),club,pa),e=>e.code==='42501');
 await login(adminB);await createChat(id(302),b);await assert.rejects(()=>createChat(id(303),a),e=>e.code==='42501');
 });
 await check('moderator and participant cannot create club chats or open role management',async()=>{
 for(const role of ['youth_moderator','user']){
 await login(superuser);await save(member,[patch(a,role)]);await login(member);
 await assert.rejects(()=>createChat(id(req++)),e=>e.code==='42501');await denied('select * from public.role_manager_people()');
 }
 });
 await check('expired administrator cannot manage roles or create chats',async()=>{
 await db.exec('reset role');await q('update app_private.role_assignments set created_at=now()-interval \'2 hours\',expires_at=now()-interval \'1 hour\' where user_id=$1 and youth_id=$2',[adminA,a]);await login(adminA);
 assert.equal((await val('select public.my_account_access()')).can_manage_roles,false);await denied('select * from public.role_manager_people()');await assert.rejects(()=>createChat(id(req++)),e=>e.code==='42501');
 await db.exec('reset role');await q('update app_private.role_assignments set expires_at=null where user_id=$1 and youth_id=$2',[adminA,a]);
 });
 await check('guest restriction suspends admin powers; restoring account preserves scoped role',async()=>{
 await login(superuser);await save(adminA,[],'guest');await login(adminA);
 assert.equal(await permission('chats.create'),false);await denied('select * from public.role_manager_people()');
 await login(superuser);await save(adminA,[],'user');await login(adminA);assert.equal(await permission('chats.create'),true);
 });
 await check('membership removal and archived club immediately disable admin rights',async()=>{
 await login(superuser);await removeMember(adminA);await login(adminA);assert.equal(await permission('chats.create'),false);assert.equal((await val('select public.my_account_access()')).can_manage_roles,false);
 await login(superuser);await save(adminA,[patch(a,'youth_admin')]);
 await db.exec('reset role');await q('update public.youth_groups set is_archived=true where id=$1',[a]);await login(adminA);
 assert.equal(await permission('chats.create'),false);await denied('select * from public.role_manager_people()');
 await db.exec('reset role');await q('update public.youth_groups set is_archived=false where id=$1',[a]);
 });
 await check('built-in administrator catalog cannot be edited or re-scoped; legacy parish delegation remains bounded',async()=>{
 await login(superuser);await assert.rejects(()=>q('select public.define_role($1,$2,$3,$4)',['youth_admin','Changed','youth',['chat.read']]),e=>e.message==='protected_role');
 await login(parishAdmin);await save(member,[patch(a,'youth_admin')]);
 await assert.rejects(()=>save(farMember,[patch(c,'youth_admin')]),e=>e.code==='42501');
 });
 await check('future club has its own catalog and administrator without borrowing existing club rights',async()=>{
 await db.exec('reset role');await q('insert into public.youth_groups(id,parish_id,name,created_by)values($1,$2,$3,$4)',[id(204),other,'Новый клуб',superuser]);
 await login(superuser);const d=await details(farMember);assert(d.clubs.find(g=>g.id===id(204)).roles.some(r=>r.key==='youth_admin'&&r.assignable));
 await save(farMember,[patch(id(204),'youth_admin')]);await login(farMember);await createChat(id(304),id(204),other);
 assert.equal(await permission('chats.create',c,other),false);assert.equal(await permission('chats.create',a,parish),false);
 await login(superuser);await save(farMember,[patch(id(204),'user')]);await login(farMember);
 assert.equal(await permission('chats.create',id(204),other),false);assert.equal((await val('select public.my_account_access()')).can_manage_roles,false);
 });
 await check('anonymous callers have no administrator or role-management access',async()=>{
 await login(null);await denied('select * from public.role_manager_people()');await denied('select app_private.is_club_admin($1)',[a]);
 });
 console.log(`${count} club-administrator checks passed.`);
}finally{await db.close();}
