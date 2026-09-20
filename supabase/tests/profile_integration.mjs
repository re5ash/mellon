import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const db = new PGlite();
let checks = 0;
const q = (sql, params = []) => db.query(sql, params);
const val = async (sql, params = []) => Object.values((await q(sql, params)).rows[0])[0];
const uuid = n => `c0000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [owner, peer, outsider, admin, superuser, pending] = [1,2,3,4,5,6].map(uuid);
const [a,b] = [101,102].map(uuid);
async function login(id) {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub','${id ?? ''}',false); set role ${id ? 'authenticated' : 'anon'};`);
}
async function test(name, fn) { await fn(); checks++; console.log('PASS '+name); }
const denied = (sql, params = [], code = '42501') => assert.rejects(() => q(sql, params), e => e.code === code);
const read = async () => (await q('select * from public.my_profile()')).rows[0];
const sql = 'select * from public.save_my_profile($1,$2,$3,$4,$5,$6,$7,$8)';
const args = (profile, changes = {}) => {
  const row = {...profile, ...changes};
  return [row.display_name,row.directory_visibility,row.given_name,row.family_name,row.birth_date,
    profile.profile_revision,profile.private_revision,profile.user_id];
};
const save = async (profile, changes = {}) => (await q(sql,args(profile, changes))).rows[0];

try {
  await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
    create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}');
    create function auth.uid() returns uuid language sql stable as $$
      select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth to anon,authenticated;
    grant execute on function auth.uid() to anon,authenticated;
    create publication supabase_realtime;
    create schema storage;
    create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
    alter table storage.objects enable row level security;
    grant usage on schema storage to authenticated; grant select,insert,delete on storage.objects to authenticated;`);
  const files = (await readdir(path.join(root,'supabase/migrations'))).sort();
  for (const f of files.filter(f=>f<'202609100008')) {
    await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));
  }
  await db.exec(`insert into auth.users(id) values('${owner}');
    update public.profiles set display_name='Старое имя' where id='${owner}';
    update app_private.profile_private set given_name='Прежнее имя',birth_date='1994-08-06' where user_id='${owner}';`);
  await db.exec(await readFile(path.join(root,'supabase/migrations/202609100008_profile.sql'),'utf8'));
  for (const f of files.filter(f=>f>'202609100008_profile.sql')) await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8')); 
  await db.exec(`insert into auth.users(id) values ${[peer,outsider,admin,superuser,pending].map(id=>`('${id}')`).join(',')};
    insert into public.cities(id,name,country_code) values('${uuid(100)}','Город','RU');
    insert into public.parishes(id,city_id,slug,name,is_published) values
      ('${a}','${uuid(100)}','profile-a','A',true),('${b}','${uuid(100)}','profile-b','B',true);
    insert into public.memberships(user_id,parish_id,status) values
      ('${owner}','${a}','active'),('${peer}','${a}','active'),('${admin}','${a}','active'),
      ('${outsider}','${b}','active'),('${pending}','${a}','pending');
    insert into app_private.role_assignments(user_id,role_id,parish_id)
      select '${admin}',id,'${a}' from app_private.roles where key='parish_admin';
    insert into app_private.role_assignments(user_id,role_id)
      select '${superuser}',id from app_private.roles where key='super_admin';`);

  await test('migration preserves old personal data and visibility; new accounts start private', async () => {
    assert.equal(await val('select directory_visibility from public.profiles where id=$1',[owner]),'parish');
    assert.equal(await val('select given_name from app_private.profile_private where user_id=$1',[owner]),'Прежнее имя');
    assert.equal(await val('select directory_visibility from public.profiles where id=$1',[peer]),'private');
  });
  await login(null);
  await test('guest cannot read or save a profile, or access private table', async () => {
    await denied('select * from public.my_profile()');
    await denied(sql,['Имя','private','','',null,0,0,owner]);
    await denied('select * from app_private.profile_private');
  });
  await login(owner);
  let initial;
  await test('read RPC returns only own private record', async () => {
    initial = await read();
    assert.equal(initial.user_id,owner);
    assert.equal(initial.given_name,'Прежнее имя');
    assert.equal((await q('select * from public.my_profile()')).rows.length,1);
    assert.equal((await q('select * from public.my_profile() where user_id=$1',[peer])).rows.length,0);
  });
  let saved;
  const personal = {display_name:'Анна',given_name:'Анна',family_name:'Частная-Фамилия',birth_date:'1994-08-06',directory_visibility:'private'};
  await test('one RPC saves both records, trims names and returns fresh revisions', async () => {
    saved=await save(initial,{...personal,display_name:'  Анна  ',given_name:' Анна '});
    assert.equal(saved.display_name,'Анна'); assert.equal(saved.given_name,'Анна');
    assert.equal(saved.family_name,personal.family_name);
    assert.ok(Number(saved.profile_revision)>Number(initial.profile_revision));
    assert.ok(Number(saved.private_revision)>Number(initial.private_revision));
    assert.deepEqual(await read(),saved);
  });
  await test('lost-response retry returns same values and versions without another write', async () => {
    assert.deepEqual(await save(initial,personal),saved);
  });
  await test('stale edit cannot overwrite either half of the profile', async () => {
    await denied(sql,args(initial,{...personal,display_name:'Stale alias',given_name:'Stale name'}),'40001');
    assert.deepEqual(await read(),saved);
  });
  await test('server validates empty/long/null names, visibility, date and revisions atomically', async () => {
    for (const change of [
      {display_name:' '},{display_name:'A'.repeat(101)},{given_name:null},{family_name:'B'.repeat(101)},
      {directory_visibility:'public'},{directory_visibility:null},{birth_date:'1899-12-31'},
      {birth_date:'9999-01-01'},{birth_date:'infinity'},
    ]) await denied(sql,args(saved,change),'22023');
    const missing=args(saved); missing[5]=null; await denied(sql,missing,'22023');
    assert.deepEqual(await read(),saved);
  });
  await test('client cannot choose another account, even with correct revisions', async () => {
    const wrong=args(saved,{given_name:'Forged'}); wrong[7]=peer;
    await denied(sql,wrong);
    await login(peer); await denied(sql,args(saved,{given_name:'Previous session'}));
    assert.equal((await read()).given_name,'');
  });
  await test('private visibility hides profile from same-parish member', async () => {
    assert.equal(await val('select count(*)::int from public.profiles where id=$1',[owner]),0);
    await denied('select * from app_private.profile_private where user_id=$1',[owner]);
  });
  await login(owner);
  saved=await save(saved,{directory_visibility:'parish'});
  await login(peer);
  await test('opt-in exposes display identity only to active same-parish members', async () => {
    const row=(await q('select * from public.profiles where id=$1',[owner])).rows[0];
    assert.equal(row.display_name,'Анна');
    for(const key of ['given_name','family_name','birth_date']) assert.ok(!(key in row));
    assert.equal((await read()).user_id,peer);
    await denied('select birth_date from public.profiles',[], '42703');
  });
  await test('foreign and pending members cannot read opted-in directory entry', async () => {
    for(const id of [outsider,pending]) {
      await login(id);
      assert.equal(await val('select count(*)::int from public.profiles where id=$1',[owner]),0);
    }
  });
  await test('parish and super administrators cannot read another private profile via app grants', async () => {
    for(const id of [admin,superuser]) {
      await login(id);
      await denied('select * from app_private.profile_private');
      assert.equal((await read()).user_id,id);
      assert.equal((await q('select * from public.my_private_profile()')).rows[0].family_name,'');
    }
  });
  await login(peer);
  await test('leaving parish immediately removes directory access without JWT renewal', async () => {
    await q('select public.leave_parish()');
    assert.equal(await val('select count(*)::int from public.profiles where id=$1',[owner]),0);
  });
  await login(owner);
  await test('public revision and identity cannot be forged or used to update another user', async () => {
    await denied('update public.profiles set revision=0 where id=$1',[owner]);
    await denied('update public.profiles set id=$1 where id=$2',[peer,owner]);
    assert.equal((await q("update public.profiles set display_name='forged' where id=$1 returning id",[peer])).rows.length,0);
  });
  await test('legacy direct display update invalidates stale combined save', async () => {
    await q("update public.profiles set display_name='Новое имя' where id=$1",[owner]);
    await denied(sql,args(saved,{given_name:'Lost update'}),'40001');
    saved=await read();
  });
  await test('legacy private RPC also invalidates stale combined save', async () => {
    await q("select public.update_private_profile('Из старого клиента','Фамилия',null)");
    await denied(sql,args(saved,{display_name:'Lost update'}),'40001');
    saved=await read();
  });
  await test('personal fields can be cleared without changing role or membership', async () => {
    const permissions=(await q('select * from public.my_permissions()')).rows;
    saved=await save(saved,{given_name:'',family_name:'',birth_date:null});
    assert.equal(saved.birth_date,null); assert.equal(saved.family_name,'');
    assert.deepEqual((await q('select * from public.my_permissions()')).rows,permissions);
    assert.equal(await val('select app_private.is_member($1)',[a]),true);
  });
  await db.exec('reset role');
  await test('second-table failure rolls back first-table write', async () => {
    await db.exec(`create function app_private.profile_test_fail() returns trigger language plpgsql as $$
      begin raise exception 'test failure' using errcode='23514'; end $$;
      create trigger profile_test_fail before update on app_private.profile_private
      for each row execute function app_private.profile_test_fail();`);
    await login(owner);
    await denied(sql,args(saved,{display_name:'Should roll back',given_name:'Fail'}),'23514');
    assert.deepEqual(await read(),saved);
    await db.exec('reset role; drop trigger profile_test_fail on app_private.profile_private; drop function app_private.profile_test_fail();');
  });
  await test('private data absent from realtime publication and audit metadata', async () => {
    assert.equal(await val("select count(*)::int from pg_publication_tables where pubname='supabase_realtime' and tablename in ('profiles','profile_private')"),0);
    assert.equal(await val("select count(*)::int from app_private.audit_log where metadata::text like '%Частная-Фамилия%'"),0);
  });
  await test('revoking profile.self blocks read and write immediately', async () => {
    await q("delete from app_private.role_permissions where permission_key='profile.self' and role_id=(select id from app_private.roles where key='user')");
    await login(owner); await denied('select * from public.my_profile()'); await denied(sql,args(saved));
  });
  console.log(`RESULT: ${checks} profile checks passed. PostgreSQL/PGlite; auth.uid mocked; no parallel connection test.`);
} catch(error) {
  console.error('FAIL',error.message,error.code ?? '',error.where ?? ''); process.exitCode=1;
} finally { await db.close(); }
