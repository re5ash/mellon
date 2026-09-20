import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const db = new PGlite();
const q = (sql, params=[]) => db.query(sql,params);
const val = async (sql,params=[]) => Object.values((await q(sql,params)).rows[0])[0];
const uuid = n => `c0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const [superuser,admin,member,editor,outsider] = [1,2,3,4,5].map(uuid);
const [a,b,room,channel,restricted] = [101,102,201,202,203].map(uuid);
let checks=0, assignment;
async function test(name,fn) {await fn(); checks++; console.log('PASS '+name);}
async function login(id) {await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id??''}',false); set role ${id?'authenticated':'anon'};`);}
const denied = (sql,params=[],code='42501') => assert.rejects(()=>q(sql,params),e=>e.code===code);
const saveSql = 'select public.admin_save_chat($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)';
const input = (o={}) => {
 const v={id:room,parish:a,create:true,title:'Болталка',description:'Общение прихожан',kind:'group',icon:'chat',sort:10,archived:false,revision:null,actor:admin,...o};
 return [v.id,v.parish,v.create,v.title,v.description,v.kind,v.icon,v.sort,v.archived,v.revision,v.actor];
};
const sendSql = 'select public.send_message($1,$2,$3)';
try {
 await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}');
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to anon,authenticated; grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated; grant select,insert,delete on storage.objects to authenticated;`);
 for (const file of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')).sort()) await db.exec(await readFile(path.join(root,'supabase/migrations',file),'utf8'));
 await db.exec(`insert into public.cities(id,name,country_code) values('${uuid(100)}','Город','RU');
 insert into public.parishes(id,city_id,slug,name,join_mode,is_published) values
 ('${a}','${uuid(100)}','chat-a','A','approval',true),('${b}','${uuid(100)}','chat-b','B','approval',false);
 insert into auth.users(id) values ${[superuser,admin,member,editor,outsider].map(id=>`('${id}')`).join(',')};
 insert into public.memberships(user_id,parish_id,status) values ('${admin}','${a}','active'),('${member}','${a}','active'),('${editor}','${a}','active'),('${outsider}','${b}','active');
 insert into app_private.role_assignments(user_id,role_id,parish_id) select '${admin}',id,'${a}' from app_private.roles where key='parish_admin';
 insert into app_private.role_assignments(user_id,role_id) select '${superuser}',id from app_private.roles where key='super_admin';
 insert into public.chat_rooms(id,parish_id,title,kind,access,created_by) values('${restricted}','${a}','Закрытый','group','restricted','${admin}');`);
 await login(null);
 await test('guest cannot call either administration RPC',async()=>{
  await denied('select * from public.admin_chat_rooms($1)',[a]); await denied(saveSql,input());
 });
 await login(member);
 await test('member cannot list or create managed chats',async()=>{
  await denied('select * from public.admin_chat_rooms($1)',[a]); await denied(saveSql,input({actor:member}));
 });
 await login(admin);
 await test('parish administrator cannot act on foreign parish',async()=>{
  await denied('select * from public.admin_chat_rooms($1)',[b]); await denied(saveSql,input({parish:b}));
 });
 await test('create returns JSON object with server identity and private parish access',async()=>{
  const r=await val(saveSql,input());
  assert.equal(r.id,room); assert.equal(r.created_by,admin); assert.equal(r.access,'parish');
  assert.equal(r.description,'Общение прихожан'); assert.equal(r.icon_key,'chat'); assert.equal(r.revision,1);
 });
 await test('lost-response retry creates one room and one audit record',async()=>{
  assert.equal((await val(saveSql,input())).revision,1);
  assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[room]),1);
  await login(superuser);
  assert.equal(await val("select count(*)::int from public.read_audit() where entity_id=$1 and action='chat.create'",[room]),1);
  await login(admin);
 });
 await test('all validation occurs on server',async()=>{
  for (const change of [{title:''},{title:' '.repeat(3)},{title:'x'.repeat(101)},{description:'x'.repeat(301)},{kind:'direct'},{icon:'javascript'},{sort:-1},{sort:10001},{archived:null},{create:null}]) await denied(saveSql,input({id:uuid(204),...change}),'22023');
 });
 await test('account mismatch cannot save under a different session',()=>denied(saveSql,input({actor:member})));
 await test('direct insert/update and role-table writes remain blocked',async()=>{
  await denied('insert into public.chat_rooms(parish_id,title,kind,access,created_by) values($1,$2,$3,$4,$5)',[a,'Direct','group','parish',admin]);
  await denied('update public.chat_rooms set title=$1 where id=$2',['Direct',room]);
  await denied('update public.chat_rooms set description=$1 where id=$2',['Direct',room]);
  await denied('delete from public.chat_rooms where id=$1',[room]);
  await denied("update app_private.roles set key='forged'");
 });
 await test('update uses revision and supports identical retry without extra revision',async()=>{
  const args=input({create:false,revision:1,title:'Болталка прихода',sort:1});
  assert.equal((await val(saveSql,args)).revision,2);
  assert.equal((await val(saveSql,args)).revision,2);
  await denied(saveSql,input({create:false,revision:1,title:'Stale'}),'40001');
  await denied(saveSql,input({create:false,revision:null,title:'Missing revision'}),'40001');
 });
 await test('missing edited room and foreign identifier never create or move a room',async()=>{
  await denied(saveSql,input({id:uuid(999),create:false,revision:1}),'22023');
  await login(superuser);
  await denied(saveSql,input({parish:b,actor:superuser,create:false,revision:2}));
  await denied(saveSql,input({actor:superuser,title:'Болталка прихода',sort:1}),'40001');
  await login(admin);
 });
 await test('restricted chat update retains invitation access and original owner',async()=>{
  const r=await val(saveSql,input({id:restricted,create:false,revision:1,title:'Закрытый обновлён'}));
  assert.equal(r.access,'restricted'); assert.equal(r.created_by,admin);
  await login(member);assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1',[restricted]),0); await login(admin);
 });
 await test('channel creation and public directory order reflect stored values',async()=>{
  await val(saveSql,input({id:channel,title:'Объявления',kind:'channel',icon:'announcements',sort:20}));
  await login(member);
  assert.deepEqual((await q('select id from public.chat_rooms where parish_id=$1 and not is_archived order by sort_order,title,id',[a])).rows.map(r=>r.id),[room,channel]);
 });
 await test('member may send to group but cannot publish into channel',async()=>{
  await q(sendSql,[room,'Добрый день',uuid(401)]);
  await denied(sendSql,[channel,'Поддельное объявление',uuid(402)]);
 });
 await login(admin);
 await test('archive preserves history and blocks sending even for administrator',async()=>{
  await val(saveSql,input({create:false,revision:2,title:'Болталка прихода',sort:1,archived:true}));
  await denied(sendSql,[room,'Archived send',uuid(403)]);
  await login(member);
  assert.equal(await val('select count(*)::int from public.chat_rooms where id=$1 and not is_archived',[room]),0);
  assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[room]),1);
  await denied(sendSql,[room,'Member archived send',uuid(404)]);
  await login(admin);
  assert.equal((await q('select is_archived from public.admin_chat_rooms($1,p_only=>$2)',[a,room])).rows[0].is_archived,true);
 });
 await test('restore reveals same room and same history',async()=>{
  const r=await val(saveSql,input({create:false,revision:3,title:'Болталка прихода',sort:1}));
  assert.equal(r.revision,4); assert.equal(r.is_archived,false);
  assert.equal(await val('select count(*)::int from public.chat_messages where room_id=$1',[room]),1);
 });
 await login(superuser);
 await test('custom chat-only role grants entry without parish or post administration',async()=>{
  await q("select public.define_role('chat_editor','Чаты','parish',array['chats.manage','chats.create'])");
  assignment=await val('select public.grant_role($1,$2,$3)',[editor,'chat_editor',a]);
  await login(editor);
  assert.deepEqual((await q('select id,permissions from public.admin_parishes()')).rows,[{id:a,permissions:['chats.manage','chats.create']}]);
  await val(saveSql,input({id:uuid(210),actor:editor,title:'Клуб',icon:'games'}));
  await denied(sendSql,[channel,'No publish grant',uuid(405)]);
 });
 await login(superuser);
 await test('channel publisher permission is independent from room management',async()=>{
  await q("select public.define_role('channel_author','Автор','parish',array['channels.publish'])");
  await q('select public.grant_role($1,$2,$3)',[member,'channel_author',a]);
  // Age the fixture message so permission testing does not depend on wall-clock delays.
  await db.exec("reset role; update public.chat_messages set created_at=now()-interval '2 seconds';");
  await login(member);
  await q(sendSql,[channel,'Объявление',uuid(406)]);
  await denied(saveSql,input({actor:member}));
 });
 await login(admin);
 await test('administration pagination is bounded and does not repeat identifiers',async()=>{
  const first=(await q('select id from public.admin_chat_rooms($1,p_limit=>2)',[a])).rows;
  const next=(await q('select id from public.admin_chat_rooms($1,p_after=>$2,p_limit=>2)',[a,first.at(-1).id])).rows;
  assert.equal(first.length,2);assert.equal(next.length,2);assert.equal(new Set([...first,...next].map(r=>r.id)).size,4);
 });
 await login(superuser);
 await test('revocation is enforced without refreshing a JWT',async()=>{
  await q('select public.revoke_role($1)',[assignment]);
  await login(editor);
  await denied('select * from public.admin_chat_rooms($1)',[a]);
  await denied(saveSql,input({id:uuid(211),actor:editor}));
 });
 await login(outsider);
 await test('foreign member cannot read parish rooms or messages',async()=>{
  assert.equal(await val('select count(*)::int from public.chat_rooms where parish_id=$1',[a]),0);
  assert.equal(await val('select count(*)::int from public.chat_messages'),0);
 });
 await login(superuser);
 await test('audit metadata excludes chat content and RPC grants exclude guests',async()=>{
  const rows=(await q("select metadata from public.read_audit() where action in ('chat.create','chat.update')")).rows;
  assert.ok(rows.length>=6);
  for (const r of rows) assert.deepEqual(Object.keys(r.metadata).sort(),['archived','revision']);
  assert.equal(await val("select has_function_privilege('anon','public.admin_chat_rooms(uuid,uuid,uuid,integer)','execute')"),false);
 });
 console.log(`RESULT: ${checks} chat administration checks passed. PostgreSQL/PGlite; mocked auth.uid; no parallel connection or live PostgREST test.`);
} catch(e) {console.error('FAIL',e.message,e.code??'',e.where??'');process.exitCode=1;}
finally {await db.close();}
