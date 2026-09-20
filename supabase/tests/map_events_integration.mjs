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
const today=await val("select (date_trunc('day',now() at time zone 'Europe/Kaliningrad') at time zone 'Europe/Kaliningrad')::text");
const start=new Date(new Date(today).getTime()+18*3600000).toISOString(),end=new Date(new Date(start).getTime()+3600000).toISOString();
const data={title:'Сплав по реке Анграпа',body:'Встреча',description:'Встреча',status:'published',visibility:'public',starts_at:start,ends_at:end,location:'Точка сбора',show_on_map:true,map_latitude:54.41,map_longitude:22.0};
const save=(record,values=data,expected=null,youth=null,expectedActor=actor)=>val('select public.save_scope_content($1,$2,$3,$4,$5,$6,$7)',['events',record,parish,youth,values,expected,expectedActor]);
const info=(record,values=data,expected=null,youth=club)=>val('select public.save_club_information($1,$2,$3,$4,$5,$6)',[youth,record,'events',values,expected,actor]);
const points=async()=> (await q('select * from public.map_events_today()')).rows;
const record=async record=>{await db.exec('reset role');const row=(await q('select * from public.events where id=$1',[record])).rows[0];await login(actor);return row;};
await check('migration is repeatable and retains permission catalog',async()=>{
 const before=(await q('select * from app_private.role_assignments order by user_id,role_id')).rows;
 await db.exec(await readFile(path.join(root,'supabase/updates/map_events.sql'),'utf8'));
 assert.deepEqual((await q('select * from app_private.role_assignments order by user_id,role_id')).rows,before);
});
await login(sup);
const publicId=id(seq++),privateId=id(seq++),foreignId=id(seq++);
await save(publicId);await save(privateId,{...data,visibility:'parish'},null,club);await save(foreignId,{...data,visibility:'parish'},null,foreign);
for(const changes of [{status:'draft'},{status:'cancelled'},{show_on_map:false},{starts_at:new Date(new Date(start).getTime()+86400000).toISOString(),ends_at:new Date(new Date(end).getTime()+86400000).toISOString()},{starts_at:new Date(new Date(start).getTime()-86400000).toISOString(),ends_at:new Date(new Date(end).getTime()-86400000).toISOString()}])await save(id(seq++),{...data,...changes});
await check('guest sees only published public pins from today',async()=>{
 await login(null);const rows=await points();assert.deepEqual(rows.map(r=>r.id),[publicId]);assert.equal(rows[0].time_label,'18:00');
});
await check('members see own club; outsiders cannot see private map events',async()=>{
 await login(member);assert.deepEqual(new Set((await points()).map(r=>r.id)),new Set([publicId,privateId]));
 await login(outsider);assert.deepEqual((await points()).map(r=>r.id),[publicId]);
});
await check('members cannot save pins or bypass RPCs through table writes',async()=>{
 await login(member);await assert.rejects(()=>save(id(seq++)),e=>e.code==='42501');
 await denied('update public.events set show_on_map=false where id=$1',[publicId]);
 await assert.rejects(()=>info(id(seq++)),e=>e.code==='42501');
});
await check('club admin can save a map event only inside own club',async()=>{
 await login(admin);const n=id(seq++);await info(n);const row=await record(n);assert.equal(row.show_on_map,true);assert.equal(row.map_latitude,54.41);
 await assert.rejects(()=>info(id(seq++),data,null,foreign),e=>e.code==='42501');
});
await check('both save paths reject missing or out-of-range coordinates atomically',async()=>{
 await login(sup);
 for(const patch of [{map_latitude:null,map_longitude:null},{map_latitude:91},{map_longitude:-181},{show_on_map:'yes'}]){
  const n=id(seq++);await assert.rejects(()=>save(n,{...data,...patch}),e=>e.code==='22023');assert.equal(await record(n),undefined);
  await assert.rejects(()=>info(id(seq++),{...data,...patch}),e=>e.code==='22023');
 }
});
await check('map-only edits persist and stale revisions cannot overwrite them',async()=>{
 await login(sup);const old=await record(publicId);
 await save(publicId,{...data,map_latitude:54.5},old.updated_at);
 assert.equal((await record(publicId)).map_latitude,54.5);
 await assert.rejects(()=>save(publicId,{...data,map_latitude:54.6},old.updated_at),e=>e.code==='40001');
 await assert.rejects(()=>save(publicId,data,null,null,member),e=>e.code==='42501');
});
await check('legacy clients preserve map metadata; disabling removes the public marker',async()=>{
 const row=await record(publicId);const legacy={...data,title:'Обновлено'};delete legacy.show_on_map;delete legacy.map_latitude;delete legacy.map_longitude;
 await save(publicId,legacy,row.updated_at);assert.equal((await record(publicId)).map_latitude,54.5);
 const updated=await record(publicId);await save(publicId,{...legacy,show_on_map:false},updated.updated_at);
 await login(null);assert.equal((await points()).length,0);
});
await check('today uses Kaliningrad midnight regardless of database session timezone',async()=>{
 await login(sup);const n=id(seq++);await save(n,{...data,starts_at:today,ends_at:new Date(new Date(today).getTime()+3600000).toISOString()});
 await login(null);await db.exec("set timezone='America/Los_Angeles'");const rows=await points();assert.equal(rows[0].id,n);assert.equal(rows[0].time_label,'00:00');
});
await check('visible pins include future and ongoing events while old Today RPC remains unchanged',async()=>{
 await login(sup);
 const future=id(seq++),past=id(seq++),ongoing=id(seq++),hidden=id(seq++);
 const shift=(time,days)=>new Date(new Date(time).getTime()+days*86400000).toISOString();
 await save(future,{...data,starts_at:shift(start,2),ends_at:shift(end,2)});
 await save(past,{...data,starts_at:shift(start,-2),ends_at:shift(end,-2)});
 await save(ongoing,{...data,starts_at:shift(start,-1),ends_at:shift(end,1)});
 await save(hidden,{...data,starts_at:shift(start,2),ends_at:shift(end,2),visibility:'parish'},null,foreign);
 await db.exec('reset role');
 await db.exec(await readFile(path.join(root,'supabase/updates/map_events_visible.sql'),'utf8'));
 await login(null);
 const rows=(await q('select * from public.map_events_visible()')).rows;
 assert(rows.some(r=>r.id===future));assert(rows.some(r=>r.id===ongoing));
 assert(!rows.some(r=>r.id===past));assert(!rows.some(r=>r.id===hidden));
 assert.equal(rows.find(r=>r.id===future).is_today,false);
 assert.notEqual(rows.find(r=>r.id===future).date_label,'Сегодня');
 assert(!(await points()).some(r=>r.id===future));
 await login(sup);const old=await record(future);await save(future,{...data,starts_at:shift(start,2),ends_at:shift(end,2),show_on_map:false},old.updated_at);
 await login(null);assert(!(await q('select * from public.map_events_visible()')).rows.some(r=>r.id===future));
});
console.log(`${count} map SQL checks passed`);
} finally {await db.close();}
