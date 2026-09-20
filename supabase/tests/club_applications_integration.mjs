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
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text,email_confirmed_at timestamptz);
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

 await db.exec('reset role');
 const applicant=id(910), receipt=id(911);
 const metadata={club_registration:{given_name:'Анна',family_name:'Иванова',birth_date:'2000-01-01',youth_id:youth,receipt_key:receipt}};
 await q('insert into auth.users(id,email,raw_user_meta_data)values($1,$2,$3)',[applicant,'anna@example.test',metadata]);
 const request=await val('select id from app_private.youth_join_requests where user_id=$1',[applicant]);
 await check('signup atomically creates a pending request, no youth membership or role',async()=>{
 assert.equal(await val('select status from public.memberships where user_id=$1',[applicant]),'pending');
 assert.equal(await val('select count(*)::int from public.youth_memberships where user_id=$1',[applicant]),0);
 assert.equal(await val('select count(*)::int from app_private.role_assignments where user_id=$1',[applicant]),0);
 assert.equal(await val("select count(*)::int from public.notifications where user_id=$1 and kind='youth_request'",[leader]),1);
 assert.equal(await val("select count(*)::int from public.notifications where user_id=$1 and kind='youth_request'",[moderator]),0);
 });
 await login(null);
 await check('anonymous receipt discloses status only; no guessed identity or private table access',async()=>{
 assert.deepEqual(await val('select public.club_application_receipt($1)',[receipt]),{status:'pending'});
 assert.equal(await val('select public.club_application_receipt($1)',[id(912)]),null);
 await denied('select * from app_private.youth_join_requests');
 await denied('select * from public.my_club_applications()');
 await denied('select * from public.youth_join_requests($1)',[youth]);
 await denied('select app_private.can_review_youth_request($1,$2,$3)',[leader,parish,youth]);
 assert.equal(await val('select count(*)::int from public.available_youth_clubs()'),2);
 });
 await login(leader);
 await check('own leader sees pending requests; email and parish gates remain enforced',async()=>{
 const rows=(await q('select * from public.youth_join_requests($1)',[youth])).rows;
 assert.equal(rows.length,1);assert.equal(rows[0].email_confirmed,false);assert.equal(rows[0].parish_active,false);
 await denied('select * from public.youth_join_requests($1)',[sibling]);
 await denied('select public.review_youth_join_request($1,$2,$3)',[request,'accepted',leader],'22023');
 });
 await login(moderator);await denied('select public.review_youth_join_request($1,$2,$3)',[request,'rejected',moderator]);
 await login(member);await denied('select * from public.youth_join_requests($1)',[youth]);
 await login(applicant);
 assert.equal(await val('select count(*)::int from public.my_club_applications()'),1);
 await denied('select public.review_youth_join_request($1,$2,$3)',[request,'accepted',applicant]);
 await db.exec('reset role');await q('update auth.users set email_confirmed_at=now() where id=$1',[applicant]);
 await login(leader);await denied('select public.review_youth_join_request($1,$2,$3)',[request,'accepted',leader],'23514');
 await login(admin);
 const membership=await val('select id from public.memberships where user_id=$1',[applicant]);
 await q("select public.review_membership($1,'active')",[membership]);
 await login(leader);
 await check('approval creates ordinary membership, not active status or a role; retry sends one notification',async()=>{
 await q('select public.review_youth_join_request($1,$2,$3)',[request,'accepted',leader]);
 await q('select public.review_youth_join_request($1,$2,$3)',[request,'accepted',leader]);
 await denied('select public.review_youth_join_request($1,$2,$3)',[request,'rejected',leader],'40001');
 await db.exec('reset role');
 const membership=(await q('select * from public.youth_memberships where user_id=$1',[applicant])).rows[0];
 assert.equal(membership.is_member,true);assert.equal(membership.is_activist,false);
 assert.equal(await val("select count(*)::int from public.notifications where user_id=$1 and kind='youth_decision'",[applicant]),1);
 assert.equal(await val('select count(*)::int from app_private.role_assignments where user_id=$1',[applicant]),0);
 });
 await check('invalid club signup rolls back profile and account; installing twice retains requests',async()=>{
 await assert.rejects(()=>q('insert into auth.users(id,email,raw_user_meta_data)values($1,$2,$3)',[id(915),'bad@example.test', {club_registration:{...metadata.club_registration,youth_id:id(999),receipt_key:id(916)}}]),e=>e.code==='22023');
 assert.equal(await val('select count(*)::int from auth.users where id=$1',[id(915)]),0);
 await db.exec(await readFile(path.join(root,'supabase/migrations/202609120014_club_applications.sql'),'utf8'));
 assert.equal(await val('select status from app_private.youth_join_requests where id=$1',[request]),'accepted');
 });
 await q('insert into auth.users(id,email,raw_user_meta_data)values($1,$2,$3)',[id(920),'other@example.test',{club_registration:{...metadata.club_registration,receipt_key:id(921)}}]);
 const rejected=await val('select id from app_private.youth_join_requests where user_id=$1',[id(920)]);
 await login(leader);
 await check('rejection is scoped, preserves no-access status and notifies the applicant once',async()=>{
 await denied('select public.review_youth_join_request($1,$2,$3)',[rejected,'rejected',admin]);
 await q('select public.review_youth_join_request($1,$2,$3)',[rejected,'rejected',leader]);
 await q('select public.review_youth_join_request($1,$2,$3)',[rejected,'rejected',leader]);
 await db.exec('reset role');
 assert.equal(await val('select count(*)::int from public.youth_memberships where user_id=$1',[id(920)]),0);
 assert.equal(await val("select count(*)::int from public.notifications where user_id=$1 and kind='youth_decision'",[id(920)]),1);
 });
 await db.exec('reset role');
 const combined=await readFile(path.join(root,'supabase/updates/club_applications.sql'),'utf8');
 await db.exec(combined);await db.exec(combined);
 assert.equal(await val('select count(*)::int from app_private.youth_join_requests'),2);
 console.log('PASS combined SQL Editor update can be applied twice without duplicating requests');
 console.log(`RESULT: ${count} application scenarios passed; mocked Auth, no live signup or email.`);
} finally {await db.close();}
