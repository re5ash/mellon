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
const uuid = n => `b0000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const [superuser, admin, member, applicant, secondApplicant, editor] = [1,2,3,4,5,6].map(uuid);
const [a, b, fresh] = [101,102,103].map(uuid);
const post = uuid(201);
let editorAssignment;
async function test(name, fn) { await fn(); checks++; console.log('PASS '+name); }
async function login(id) {
  await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id ?? ''}',false);set role ${id ? 'authenticated' : 'anon'};`);
}
const denied = (sql, params = [], code = '42501') => assert.rejects(() => q(sql, params), e => e.code === code);
const saveParish = 'select public.admin_save_parish($1,$2,$3,$4,$5,$6,$7,$8,$9)';
const parishArgs = (id, create = true, version = null, published = true) =>
  [id, create, 'Новый город', 'Новый приход', 'Описание', 'Адрес', 'approval', published, version];
const savePost = 'select public.admin_save_post($1,$2,$3,$4,$5,$6,$7,$8)';
const postArgs = (id = post, parish = a, create = true, version = null, status = 'draft', visibility = 'parish') =>
  [id, parish, create, 'Заголовок', 'Текст', visibility, status, version];

try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
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
  for (const file of (await readdir(path.join(root, 'supabase/migrations'))).sort()) {
    await db.exec(await readFile(path.join(root, 'supabase/migrations', file), 'utf8'));
  }
  await db.exec(`insert into public.cities(id,name,country_code) values('${uuid(100)}','Город','RU');
    insert into public.parishes(id,city_id,slug,name,join_mode,is_published) values
      ('${a}','${uuid(100)}','admin-a','A','approval',true),
      ('${b}','${uuid(100)}','admin-b','B','approval',false);
    insert into auth.users(id) values ${[superuser,admin,member,applicant,secondApplicant,editor].map(id=>`('${id}')`).join(',')};
    update public.profiles set display_name='Заявитель',directory_visibility='private' where id in ('${applicant}','${secondApplicant}');
    insert into public.memberships(user_id,parish_id,status) values
      ('${admin}','${a}','active'),('${member}','${a}','active'),('${editor}','${a}','active'),
      ('${applicant}','${a}','pending'),('${secondApplicant}','${a}','pending');
    insert into app_private.role_assignments(user_id,role_id,parish_id)
      select '${admin}',id,'${a}' from app_private.roles where key='parish_admin';
    insert into app_private.role_assignments(user_id,role_id)
      select '${superuser}',id from app_private.roles where key='super_admin';`);

  await login(null);
  await test('guest cannot invoke any administration RPC', async () => {
    await denied('select * from public.admin_parishes()');
    await denied('select * from public.admin_pending_memberships($1)', [a]);
    await denied(saveParish, parishArgs(fresh));
    await denied(savePost, postArgs());
  });
  await login(member);
  await test('ordinary member sees no managed parishes and cannot write', async () => {
    assert.equal(await val('select count(*)::int from public.admin_parishes()'), 0);
    await denied(saveParish, parishArgs(fresh));
    await denied(savePost, postArgs());
    await denied('select * from public.admin_pending_memberships($1)', [a]);
  });
  await login(admin);
  await test('parish admin listing excludes foreign and hidden parishes', async () => {
    const rows = (await q('select * from public.admin_parishes()')).rows;
    assert.deepEqual(rows.map(row=>row.id), [a]);
    assert.deepEqual(rows[0].permissions.sort(), ['chats.create','chats.manage','events.create','events.delete','events.edit','events.manage','memberships.manage','parish.manage','posts.manage','roles.assign','youths.manage']);
    assert.equal(await val('select count(*)::int from public.admin_parishes(p_only=>$1)', [b]), 0);
  });
  await test('parish admin cannot create a parish or inspect foreign applicants', async () => {
    await denied(saveParish, parishArgs(fresh));
    await denied('select * from public.admin_pending_memberships($1)', [b]);
  });
  let requests;
  await test('reviewer gets applicant display names without a private profile directory', async () => {
    requests = (await q('select * from public.admin_pending_memberships($1)', [a])).rows;
    assert.equal(requests.length, 2);
    assert.deepEqual(Object.keys(requests[0]).sort(), ['display_name','id','requested_at','user_id']);
    assert.equal(requests[0].display_name, 'Заявитель');
    assert.equal(await val('select count(*)::int from public.profiles where id=$1', [applicant]), 0);
    await denied('select * from app_private.profile_private');
  });
  await test('request cursor handles identical timestamps without duplicate rows', async () => {
    const first = (await q('select * from public.admin_pending_memberships($1,p_limit=>1)', [a])).rows[0];
    const next = (await q('select * from public.admin_pending_memberships($1,$2,$3,1)', [a,first.requested_at,first.id])).rows;
    assert.equal(next.length, 1);
    assert.notEqual(next[0].id, first.id);
    await denied('select * from public.admin_pending_memberships($1,now(),null)', [a], '22023');
  });
  await test('parish admin edit preserves publication; cannot publish a parish', async () => {
    const version = await val('select updated_at from public.parishes where id=$1', [a]);
    await denied(saveParish, parishArgs(a, false, version, false));
    assert.equal(await val(saveParish, parishArgs(a, false, version)), a);
    await denied(saveParish, parishArgs(a, false, version), '40001');
  });
  await test('scoped author creates draft once; identity comes from authenticated session', async () => {
    assert.equal(await val(savePost, postArgs()), post);
    assert.equal(await val(savePost, postArgs()), post);
    const row = (await q('select author_id,status,visibility from public.posts where id=$1', [post])).rows[0];
    assert.deepEqual(row, {author_id:admin,status:'draft',visibility:'parish'});
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 1);
    await denied(savePost, postArgs(uuid(202), b));
  });
  await login(member);
  await test('unpublished draft hidden from active member', async () => {
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 0);
  });
  await login(admin);
  await test('publish protects against stale writes and validates fields on server', async () => {
    const version = await val('select updated_at from public.posts where id=$1', [post]);
    const invalid = postArgs(post, a, false, version); invalid[3]='';
    await denied(savePost, invalid, '22023');
    assert.equal(await val(savePost, postArgs(post, a, false, version, 'published')), post);
    await denied(savePost, postArgs(post, a, false, version, 'archived'), '40001');
    assert.notEqual(await val('select published_at from public.posts where id=$1', [post]), null);
  });
  await login(applicant);
  await test('pending applicant cannot read private publication', async () => {
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 0);
  });
  await login(admin);
  await test('approval removes request; re-review rejected; approved member gains access', async () => {
    const request = requests.find(row=>row.user_id===applicant);
    await q('select public.review_membership($1,$2)', [request.id,'active']);
    await denied('select public.review_membership($1,$2)', [request.id,'active'], '22023');
    assert.equal(await val('select count(*)::int from public.admin_pending_memberships($1)', [a]), 1);
    await login(applicant);
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 1);
  });
  await login(superuser);
  await test('super admin create retry does not duplicate city, parish or audit entry', async () => {
    assert.equal(await val(saveParish, parishArgs(fresh)), fresh);
    assert.equal(await val(saveParish, parishArgs(fresh)), fresh);
    assert.equal(await val("select count(*)::int from public.cities where name='Новый город'"), 1);
    assert.equal(await val("select count(*)::int from public.read_audit() where entity_id=$1 and action='parish.create'", [fresh]), 1);
    const nextParish = uuid(104);
    const args = parishArgs(nextParish); args[2]=' новый ГОРОД ';
    await q(saveParish, args);
    assert.equal(await val("select count(*)::int from public.cities where lower(name)='новый город'"), 1);
  });
  await test('parish listing cursor is bounded and does not repeat records', async () => {
    const first = (await q('select id from public.admin_parishes(p_limit=>2)')).rows;
    const next = (await q('select id from public.admin_parishes(p_after=>$1,p_limit=>2)', [first.at(-1).id])).rows;
    assert.equal(first.length, 2); assert.equal(next.length, 2);
    assert.equal(new Set([...first,...next].map(row=>row.id)).size, 4);
  });
  await test('another administrator cannot claim an existing create request', async () => {
    await denied(saveParish, parishArgs(a));
    await denied(savePost, postArgs());
  });
  await test('custom permission role enables publishing without membership review', async () => {
    await q("select public.define_role('news_editor','Редактор','parish',array['posts.manage'])");
    editorAssignment = await val('select public.grant_role($1,$2,$3)', [editor,'news_editor',a]);
    await login(editor);
    assert.deepEqual((await q('select permissions from public.admin_parishes()')).rows, [{permissions:['posts.manage']}]);
    await denied('select * from public.admin_pending_memberships($1)', [a]);
    const version = await val('select updated_at from public.posts where id=$1', [post]);
    await q(savePost, postArgs(post, a, false, version, 'published', 'public'));
    assert.equal(await val('select author_id from public.posts where id=$1', [post]), admin);
  });
  await login(null);
  await test('guest sees public publication only after explicit publication', async () => {
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 1);
  });
  await login(editor);
  await test('archive removes publication from public feed', async () => {
    const version = await val('select updated_at from public.posts where id=$1', [post]);
    await q(savePost, postArgs(post, a, false, version, 'archived', 'public'));
    await login(null);
    assert.equal(await val('select count(*)::int from public.posts where id=$1', [post]), 0);
  });
  await login(superuser);
  await test('revoked permission immediately blocks RPC and administrative listing', async () => {
    await q('select public.revoke_role($1)', [editorAssignment]);
    await login(editor);
    assert.equal(await val('select count(*)::int from public.admin_parishes()'), 0);
    await denied(savePost, postArgs(uuid(203)));
  });
  console.log(`RESULT: ${checks} administration checks passed. PostgreSQL/PGlite; auth.uid mocked; no parallel connection test.`);
} catch (error) {
  console.error('FAIL', error.message, error.code ?? '', error.where ?? '');
  process.exitCode = 1;
} finally {
  await db.close();
}
