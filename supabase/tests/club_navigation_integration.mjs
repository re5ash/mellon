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
 const catalog=(await q('select * from app_private.roles order by key')).rows;
 const assignments=(await q('select * from app_private.role_assignments order by id')).rows;
 const memberships=(await q('select * from public.youth_memberships order by youth_id,user_id')).rows;
 await check('installation repeats safely and preserves every existing role and club assignment',async()=>{
 const sql=await readFile(path.join(root,'supabase/updates/club_navigation.sql'),'utf8');await db.exec(sql);await db.exec(sql);
 assert.deepEqual((await q('select * from app_private.roles order by key')).rows,catalog);
 assert.deepEqual((await q('select * from app_private.role_assignments order by id')).rows,assignments);
 assert.deepEqual((await q('select * from public.youth_memberships order by youth_id,user_id')).rows,memberships);
 });
 await check('generic registration copies profile without choosing a club or granting membership',async()=>{
 await q('insert into auth.users(id,email,raw_user_meta_data,email_confirmed_at)values($1,$2,$3,now())',[newcomer,'new@example.test',{club_registration:{given_name:'Иван',family_name:'Иванов',birth_date:'2000-01-01'}}]);
 assert.equal(await val('select given_name from app_private.profile_private where user_id=$1',[newcomer]),'Иван');
 for(const table of ['public.memberships','public.youth_memberships','app_private.youth_join_requests','app_private.role_assignments'])assert.equal(await val(`select count(*)::int from ${table} where user_id=$1`,[newcomer]),0);
 });
 await check('club selector lists clubs and only the current account request status',async()=>{
 await login(newcomer);let d=(await q('select * from public.youth_club_directory()')).rows;
 assert.equal(d.length,2);assert(d.every(g=>!g.can_open&&g.request_status===null));
 const receipt=id(401),r=await request(a,receipt);assert.equal(await request(a,receipt),r);assert.equal(await request(a),r);
 await request(b);d=(await q('select * from public.youth_club_directory()')).rows;assert(d.every(g=>g.request_status==='pending'&&!g.can_open));
 await login(member);d=(await q('select * from public.youth_club_directory()')).rows;assert(d.every(g=>g.can_open&&g.request_status===null));
 });
 await check('applicant cannot access administrative club endpoints or private application tables',async()=>{
 await login(newcomer);
 for(const s of ['select * from public.managed_youth_groups()','select * from public.club_management_cities()','select * from app_private.youth_join_requests'])await denied(s);
 await assert.rejects(()=>save(),e=>e.code==='42501');
 await denied('select public.save_youth_group($1,$2,$3,$4,false,0)',[id(204),pa,'Запрещённый','']);
 await denied('insert into public.youth_groups(id,parish_id,name,created_by)values($1,$2,$3,$4)',[id(204),pa,'Запрещённый',newcomer]);
 await assert.rejects(()=>request(a,id(seq++),member),e=>e.code==='42501');
 });
 await check('leader accepts club application without parish admission and preserves other pending club',async()=>{
 await login(newcomer);const r=await request(a);await login(leader);
 await q('select public.review_youth_join_request($1,$2,$3)',[r,'accepted',leader]);
 await q('select public.review_youth_join_request($1,$2,$3)',[r,'accepted',leader]);
 await login(newcomer);const d=(await q('select * from public.youth_club_directory()')).rows;
 assert.equal(d.find(g=>g.id===a).can_open,true);assert.equal(d.find(g=>g.id===b).can_open,false);assert.equal(d.find(g=>g.id===b).request_status,'pending');
 assert.equal(await val('select count(*)::int from public.memberships where user_id=$1',[newcomer]),0);
 });
 await check('content workspaces remain scoped; catalog settings are denied to all local roles',async()=>{
 for(const u of [leader,moderator,clubAdmin,legacyAdmin]){
 await login(u);const rows=(await q('select * from public.my_club_workspaces()')).rows;
 assert(rows.some(g=>g.id===a));if(u!==legacyAdmin)assert(!rows.some(g=>g.id===b));
 await denied('select * from public.managed_youth_groups()');await assert.rejects(()=>save(),e=>e.code==='42501');
 await denied('select public.save_youth_group($1,$2,$3,$4,false,0)',[id(204),pa,'Запрещённый','']);
 }
 await login(newcomer);assert.equal((await q('select * from public.my_club_workspaces()')).rows.length,0);
 });
 await check('superadmin creates club without parish chooser, safely retries and handles stale edits',async()=>{
 await login(sup);assert.equal((await q('select * from public.club_management_cities()')).rows.length,1);
 assert.equal(await save(),id(203));assert.equal(await save(),id(203));
 let rev=await val('select revision from public.youth_groups where id=$1',[id(203)]);
 await save(id(203),'Новое название',rev);await assert.rejects(()=>save(id(203),'Устаревшее',rev),e=>e.code==='40001');
 assert.equal((await q('select * from public.managed_youth_groups()')).rows.length,3);
 await denied('select public.save_youth_club($1,$2,$3,$4,false,0,$5)',[id(205),city,'Подмена','',''+member]);
 await assert.rejects(()=>q('select public.save_youth_club($1,$2,$3,$4,false,0,$5)',[id(205),id(999),'Нет города','',sup]),e=>e.message==='invalid_city');
 });
 await check('archived clubs reject applications and leave the public selector',async()=>{
 await login(sup);const rev=await val('select revision from public.youth_groups where id=$1',[id(203)]);
 await q('select public.save_youth_club($1,null,$2,$3,true,$4,$5)',[id(203),'Новое название','Описание',rev,sup]);
 await login(newcomer);assert.equal((await q('select * from public.youth_club_directory()')).rows.length,2);
 await assert.rejects(()=>request(id(203)),e=>e.message==='club_unavailable');
 });
 await check('guest restriction suspends club access without deleting account or stored club roles',async()=>{
 await login(sup);await roles(member,[],'guest');await login(member);
 assert.equal((await q('select * from public.youth_club_directory()')).rows.length,0);assert.equal((await q('select * from public.my_club_workspaces()')).rows.length,0);
 await assert.rejects(()=>request(a),e=>e.code==='42501');
 await login(sup);await roles(member,[],'user');const d=await details(member);
 assert.equal(d.clubs.find(g=>g.id===a).role,'user');assert.equal(d.clubs.find(g=>g.id===b).role,'youth_moderator');
 assert(!d.clubs.some(g=>g.roles.some(r=>r.key==='guest')));
 });
 await check('role changes in one club preserve other clubs and global access',async()=>{
 await roles(member,[{id:a,role:'youth_leader'}]);const d=await details(member);
 assert.equal(d.global_role,'user');assert.equal(d.clubs.find(g=>g.id===b).role,'youth_moderator');
 assert.equal(d.clubs.find(g=>g.id===a).role,'youth_leader');
 });
 await check('unconfirmed or incomplete accounts must complete admission data; no hidden join occurs',async()=>{
 await db.exec('reset role');await q('insert into auth.users(id,email)values($1,$2)',[id(99),'blank@example.test']);await login(id(99));
 await assert.rejects(()=>request(a),e=>e.message==='email_confirmation_required');
 await db.exec('reset role');await q('update auth.users set email_confirmed_at=now() where id=$1',[id(99)]);await login(id(99));
 await assert.rejects(()=>request(a),e=>e.message==='club_profile_required');
 });
 await check('anonymous visitors cannot request membership or change roles/settings',async()=>{
 await login(null);await denied('select * from public.youth_club_directory()');await denied('select * from public.managed_youth_groups()');await assert.rejects(()=>request(a),e=>e.code==='42501');
 });
 console.log(`${count} club-navigation checks passed.`);
}finally{await db.close();}
