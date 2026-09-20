import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..'),db=new PGlite();
const q=(s,a=[])=>db.query(s,a),val=async(s,a=[])=>Object.values((await q(s,a)).rows[0])[0];
const id=n=>`f0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [sup,admin,member,outsider]=[1,2,3,4].map(id);
const [city,parish,club,foreign]=[100,101,201,202].map(id);
let actor,count=0,seq=600;
async function login(u){actor=u;await db.exec(`reset role;select set_config('request.jwt.claim.sub','${u??''}',false);set role ${u?'authenticated':'anon'};`);}
async function check(name,fn){await fn();count++;console.log('PASS '+name);}
const denied=(s,a=[])=>assert.rejects(()=>q(s,a),e=>e.code==='42501');
try {
await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text,email_confirmed_at timestamptz,created_at timestamptz not null default now());
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;`);
for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')).sort()) {
 await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
}
await db.exec(`insert into auth.users(id,email,email_confirmed_at) values ${[sup,admin,member,outsider].map((u,i)=>`('${u}','map${i}@example.test',now())`).join(',')};
 update app_private.account_access set guest_only=false,review_guest=false,review_status='verified';
 insert into public.cities(id,name,country_code)values('${city}','Калининград','RU');
 insert into public.parishes(id,city_id,slug,name,is_published)values('${parish}','${city}','map-parish','Приход',true);
 insert into app_private.role_assignments(user_id,role_id)select '${sup}',id from app_private.roles where key='super_admin';
 insert into public.youth_groups(id,parish_id,name,created_by)values('${club}','${parish}','Клуб А','${sup}'),('${foreign}','${parish}','Клуб Б','${sup}');
 insert into public.memberships(user_id,parish_id,status)values('${admin}','${parish}','active'),('${member}','${parish}','active');
 insert into public.youth_memberships(youth_id,user_id,is_member)values('${club}','${admin}',true),('${club}','${member}',true);
 insert into app_private.role_assignments(user_id,role_id,parish_id,youth_id)select '${admin}',id,'${parish}','${club}' from app_private.roles where key='youth_admin';`);

const pathFor=(n,owner=admin,group=club,ext='png')=>`${group}/${owner}/${id(n)}.${ext}`;
const upload=async(n,owner=admin,group=club,ext='png')=>q("insert into storage.objects(bucket_id,name) values('club-stories',$1)",[pathFor(n,owner,group,ext)]);
const publish=(n,{owner=admin,group=club,mime='image/png',ext='png',duration=null,bytes=1024,expected=actor}={})=>val('select public.publish_club_story($1,$2,$3,$4,$5,$6,$7)',[id(n),group,pathFor(n,owner,group,ext),mime,bytes,duration,expected]);
await check('SQL applies twice and preserves club permissions',async()=>{
 const before=(await q('select * from app_private.role_assignments order by user_id,role_id')).rows;
 const sql=await readFile(path.join(root,'supabase/updates/club_stories.sql'),'utf8');await db.exec(sql);await db.exec(sql);
 assert.deepEqual((await q('select * from app_private.role_assignments order by user_id,role_id')).rows,before);
});
await check('members and outsiders cannot upload or publish',async()=>{
 for(const u of [member,outsider]){await login(u);await denied("insert into storage.objects(bucket_id,name) values('club-stories',$1)",[pathFor(800,u)]);await denied('select public.publish_club_story($1,$2,$3,$4,$5,$6,$7)',[id(800),club,pathFor(800,u),'image/png',1024,null,u]);}
});
await check('admin is scoped to their own club and expected actor',async()=>{
 await login(admin);await denied("insert into storage.objects(bucket_id,name) values('club-stories',$1)",[pathFor(801,admin,foreign)]);
 await upload(802);await assert.rejects(()=>publish(802,{expected:member}),e=>e.code==='42501');
 const s=await publish(802);assert.equal(s.media_path,pathFor(802));assert.equal(s.author_id,admin);
 assert.equal(new Date(s.expires_at)-new Date(s.created_at),24*3600000);
 const retry=await publish(802);assert.equal(retry.id,s.id);assert.equal(await val('select count(*)::int from public.club_stories'),1);
});
await check('active stories and objects visible only inside club, bucket private',async()=>{
 await login(member);assert.equal(await val('select count(*)::int from public.club_stories'),1);
 assert.equal(await val("select count(*)::int from storage.objects where bucket_id='club-stories'"),1);
 for(const u of [outsider,null]){await login(u);if(u){assert.equal(await val('select count(*)::int from public.club_stories'),0);assert.equal(await val("select count(*)::int from storage.objects where bucket_id='club-stories'"),0);}else await denied('select * from public.club_stories');}
 await db.exec('reset role');assert.equal(await val("select public from storage.buckets where id='club-stories'"),false);
});
await check('unpublished uploads stay hidden and invalid video metadata is refused',async()=>{
 await login(admin);await upload(803,admin,club,'mp4');
 await assert.rejects(()=>publish(803,{mime:'video/mp4',ext:'mp4',duration:60001}),e=>e.code==='22023');
 await assert.rejects(()=>publish(803,{mime:'video/mp4',ext:'mp4',duration:null}),e=>e.code==='22023');
 await assert.rejects(()=>publish(803,{mime:'video/mp4',ext:'mp4',duration:5000,bytes:52428801}),e=>e.code==='22023');
 await login(member);assert.equal(await val('select count(*)::int from public.club_stories'),1);assert.equal(await val("select count(*)::int from storage.objects where name=$1",[pathFor(803,admin,club,'mp4')]),0);
 await login(admin);assert.equal((await publish(803,{mime:'video/mp4',ext:'mp4',duration:5000})).duration_ms,5000);
 await assert.rejects(()=>publish(804),e=>e.code==='22023');
});
await check('clients cannot forge records, timestamps or ownership',async()=>{
 await login(admin);await denied("insert into public.club_stories(id,youth_id,author_id,media_path,mime_type,byte_size)values($1,$2,$3,$4,'image/png',10)",[id(805),club,admin,pathFor(805)]);
 await denied("update public.club_stories set expires_at=now()+interval '1 year'");
 await denied('delete from public.club_stories');
});
await check('expiry hides stories, Storage deletion precedes record cleanup',async()=>{
 await db.exec('reset role');await q("update public.club_stories set expires_at=now()-interval '1 second' where id=$1",[id(802)]);
 await login(member);assert.equal(await val('select count(*)::int from public.club_stories'),1);assert.equal(await val("select count(*)::int from storage.objects where name=$1",[pathFor(802)]),0);await denied('select * from public.expired_club_stories($1)',[club]);
 await login(admin);const expired=(await q('select * from public.expired_club_stories($1)',[club])).rows;assert.equal(expired.length,1);
 await assert.rejects(()=>q('select public.remove_club_story($1,$2)',[id(802),admin]),e=>e.code==='22023');
 await q("delete from storage.objects where bucket_id='club-stories' and name=$1",[pathFor(802)]);
 await q('select public.remove_club_story($1,$2)',[id(802),admin]);await q('select public.remove_club_story($1,$2)',[id(802),admin]);
});
await check('leaving a club revokes reading, revoked admin cannot finish upload',async()=>{
 await login(admin);await upload(806);
 await login(member);await q('select public.leave_youth_club($1,$2)',[club,member]);assert.equal(await val('select count(*)::int from public.club_stories'),0);
 await db.exec('reset role');await q('delete from app_private.role_assignments where user_id=$1 and youth_id=$2',[admin,club]);
 await login(admin);await assert.rejects(()=>publish(806),e=>e.code==='42501');
});
console.log(`${count} club story SQL checks passed.`);
}finally{await db.close();}
