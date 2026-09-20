import assert from 'node:assert/strict';
import {readFile, readdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const {PGlite} = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const db = new PGlite();
const id = n => `e0000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const signup = (n, metadata = {}) => db.query('insert into auth.users(id, raw_user_meta_data) values($1,$2)', [id(n), metadata]);
const profile = async n => (await db.query('select * from app_private.profile_private where user_id=$1', [id(n)])).rows[0];
try {
 await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
 create table auth.users(id uuid primary key,raw_user_meta_data jsonb not null default '{}',email text);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;
 create publication supabase_realtime;create schema storage;
 create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
 create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets,name text,unique(bucket_id,name));
 alter table storage.objects enable row level security;grant usage on schema storage to authenticated;grant select,insert,delete on storage.objects to authenticated;`);
 for(const f of (await readdir(path.join(root,'supabase/migrations'))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(path.join(root,'supabase/migrations',f),'utf8'));

 const personal = {given_name: ' Анна ', family_name: ' Иванова ', birth_date: '2000-04-15'};
 await signup(1, {club_registration: personal, roles: ['super_admin'], parish_id: id(100), is_active: true});
 assert.equal((await profile(1)).given_name, 'Анна');
 assert.equal((await profile(1)).family_name, 'Иванова');
 assert.equal((await profile(1)).birth_date.toISOString().slice(0,10), '2000-04-15');
 assert.equal((await db.query('select display_name from public.profiles where id=$1',[id(1)])).rows[0].display_name, 'Анна Иванова');
 assert.equal((await db.query('select count(*)::int as n from app_private.role_assignments where user_id=$1',[id(1)])).rows[0].n, 0);
 assert.equal((await db.query('select count(*)::int as n from public.memberships where user_id=$1',[id(1)])).rows[0].n, 0);
 console.log('PASS private registration fields persist without granting membership or roles');
 await signup(2);
 assert.equal((await profile(2)).given_name, '');
 assert.equal((await profile(2)).birth_date, null);
 console.log('PASS existing email-only signup remains supported');
 for (const [n, data] of [[3, {...personal, birth_date:'2000-02-31'}], [4, {...personal, given_name:''}], [5,{...personal, birth_date:'9999-01-01'}], [6,{...personal, family_name:['x']}], [7, null]]) {
   await assert.rejects(() => signup(n, {club_registration: data}), error => error.code === '22023');
   assert.equal(await profile(n), undefined);
 }
 console.log('PASS malformed profile and dates reject atomically');
 await db.exec(await readFile(path.join(root,'supabase/migrations/202609120013_club_registration.sql'), 'utf8'));
 assert.equal((await profile(1)).given_name, 'Анна');
 await db.query('update auth.users set raw_user_meta_data=$1 where id=$2',[{club_registration:{...personal,given_name:'Перезапись'}},id(1)]);
 assert.equal((await profile(1)).given_name, 'Анна');
 console.log('PASS repeat installation and later auth metadata changes do not overwrite profiles');
} finally { await db.close(); }
