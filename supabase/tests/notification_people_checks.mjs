import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';

export async function checkNotificationPeople({db,root,login,check,sup,leader,clubAdmin,moderator,member,a,b}) {
 const q=(sql,args=[])=>db.query(sql,args);
 const val=async(sql,args=[])=>Object.values((await q(sql,args)).rows[0])[0];
 const id=n=>`f1000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
 const [pending,unassigned1,unassigned2,later,foreign,unconfirmed]=[1,2,3,4,5,6].map(id);
 const person=n=>val('select public.notification_applicant($1)',[n]);
 const notices=()=>q("select * from public.notifications where kind in ('youth_request','review_routing') order by created_at,id");
 const request=async u=>{await db.exec('reset role');return val('select review_request_id from app_private.account_access where user_id=$1',[u]);};
 const signup=async(u,confirmed=true,youth=null)=>{
  await db.exec('reset role');
  await q('insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)values($1,$2,$3,$4)',[
   u,`${u}@example.test`,confirmed?new Date().toISOString():null,
   {club_registration:{given_name:'Анна',family_name:'Волкова',birth_date:'2001-02-03',...(youth?{youth_id:youth,receipt_key:id(Number(u.slice(-4))+100)}:{})}},
  ]);
  await q("update app_private.profile_private set phone='+79991234567' where user_id=$1",[u]);
 };
 await db.exec('reset role');
 await q('update public.youth_groups set is_archived=false where id=$1',[b]);
 await q('update app_private.registration_intake set youth_id=$1',[a]);
 await signup(pending);
 const pendingRequest=await request(pending);
 await db.exec('reset role');
 // An old notice from before the subject-link migration, and two unrouted people.
 await q("insert into public.notifications(user_id,kind,title,body,target_path)values($1,'youth_request','Новая заявка в молодёжный клуб','Участник ожидает рассмотрения заявки.',$2)",[sup,`/youth-requests/${a}`]);
 await db.exec('update app_private.registration_intake set youth_id=null');
 await signup(unassigned1);await signup(unassigned2);
 const beforeRoles=(await q('select * from app_private.role_assignments order by id')).rows;
 const beforeMembers=(await q('select * from public.youth_memberships order by youth_id,user_id')).rows;
 const beforeCatalog=(await q('select * from app_private.roles order by id')).rows;
 const sql=await readFile(path.join(root,'supabase/updates/notification_people.sql'),'utf8');
 await check('notification people migration is repeatable, preserves all roles/memberships and repairs old notices',async()=>{
  await db.exec(sql);const count=await val('select count(*)::int from public.notifications');await db.exec(sql);
  assert.equal(await val('select count(*)::int from public.notifications'),count);
  assert.deepEqual((await q('select * from app_private.role_assignments order by id')).rows,beforeRoles);
  assert.deepEqual((await q('select * from public.youth_memberships order by youth_id,user_id')).rows,beforeMembers);
  assert.deepEqual((await q('select * from app_private.roles order by id')).rows,beforeCatalog);
  assert.equal(await val("select count(*)::int from public.notifications where kind in ('review_routing','youth_request') and subject_user_id is null"),0);
  assert((await q("select * from public.notifications where kind='review_legacy' and read_at is not null")).rows.length>0);
 });
 let notice,otherNotice;
 await check('superadmin sees separate people with exact private fields even before a club is configured',async()=>{
  await login(sup);const rows=(await notices()).rows;
  for(const u of [unassigned1,unassigned2]) {
   const own=rows.filter(n=>n.subject_user_id===u);assert.equal(own.length,1);
   const info=await person(own[0].id);
   assert.equal(info.user_id,u);assert.equal(info.given_name,'Анна');assert.equal(info.family_name,'Волкова');
   assert.equal(info.email,`${u}@example.test`);assert.equal(info.phone,'+79991234567');assert.equal(info.birth_date,'2001-02-03');
   assert(info.registered_at);assert.equal(info.youth_id,null);assert.equal(info.review_status,'pending');assert.equal(info.can_manage_roles,true);
   assert.equal((await val('select public.role_manager_person_v2($1)',[u])).user_id,u);
   assert(!own[0].body.includes(info.email));assert(!own[0].body.includes(info.phone));
  }
  notice=rows.find(n=>n.subject_user_id===pending).id;
  assert.equal((await person(notice)).request_id,pendingRequest);
 });
 await check('club admin opens exactly their pending applicant in Roles while review cannot be bypassed',async()=>{
  await login(clubAdmin);const row=(await notices()).rows.find(n=>n.subject_user_id===pending);assert(row);
  otherNotice=row.id;const info=await person(row.id);assert.equal(info.youth_id,a);assert.equal(info.can_manage_roles,true);
  const roleDetails=await val('select public.role_manager_person_v2($1)',[pending]);assert.equal(roleDetails.user_id,pending);assert.equal(roleDetails.can_global,false);
  await assert.rejects(()=>q('select public.save_person_roles_v2($1,null,$2,$3,$4,$5)',[pending,[{id:a,role:'user'}],roleDetails.revision,id(900),clubAdmin]),e=>e.message.includes('review_required'));
  const legacyDetails=await val('select public.role_manager_person($1)',[pending]);
  await assert.rejects(()=>q('select public.save_person_roles($1,null,$2,$3,$4,$5)',[pending,[{id:a,role:'user'}],legacyDetails.revision,id(901),clubAdmin]),e=>e.message.includes('review_required'));
  await assert.rejects(()=>q('select public.role_manager_person_v2($1)',[unassigned1]),e=>e.code==='42501');
 });
 await check('owned notification id is mandatory; member, guest, unrelated admin and anon cannot read personal fields',async()=>{
  for(const u of [clubAdmin,leader,moderator,member,pending]) {await login(u);assert.equal(await person(notice),null);}
  await login(null);await assert.rejects(()=>person(notice),e=>e.code==='42501');
  await login(sup);assert.equal(await person(id(99999)),null);
  await signup(foreign,true,b);const req=await request(foreign);await login(clubAdmin);
  assert.equal((await notices()).rows.filter(n=>n.youth_request_id===req).length,0);
  await assert.rejects(()=>q('select public.role_manager_person_v2($1)',[foreign]),e=>e.code==='42501');
 });
 await check('new confirmed registration produces one person notice; token metadata never grants rights',async()=>{
  await db.exec('reset role');await q('update app_private.registration_intake set youth_id=$1',[a]);
  await signup(later);const req=await request(later);
  await q('select app_private.route_review($1)',[later]);await q('select app_private.route_review($1)',[later]);
  for(const u of [sup,leader,clubAdmin]) {await login(u);const rows=(await notices()).rows.filter(n=>n.subject_user_id===later);assert.equal(rows.length,1);assert.equal(rows[0].youth_request_id,req);assert.equal((await person(rows[0].id)).user_id,later);}
  await signup(unconfirmed,false,a);const unconfirmedReq=await request(unconfirmed);assert(unconfirmedReq);
  assert.equal(await val('select count(*)::int from public.notifications where youth_request_id=$1',[unconfirmedReq]),0);
  await q('update auth.users set email_confirmed_at=now() where id=$1',[unconfirmed]);
  await login(sup);assert.equal((await notices()).rows.filter(n=>n.subject_user_id===unconfirmed).length,1);
 });
 await check('choosing the intake club replaces routing placeholders, without duplicate person cards',async()=>{
  await login(sup);await q('select public.set_registration_intake($1,$2)',[a,sup]);
  const rows=(await notices()).rows;
  for(const u of [unassigned1,unassigned2]) {
   const matches=rows.filter(n=>n.subject_user_id===u);assert.equal(matches.length,1);assert.equal(matches[0].kind,'youth_request');
   const info=await person(matches[0].id);assert.equal(info.youth_id,a);assert(info.request_id);
  }
 });
 await check('read marking does not change roles; decision refreshes status without exposing other clubs',async()=>{
  await login(sup);await q('select public.mark_notification_read($1)',[notice]);assert.equal((await person(notice)).review_status,'pending');
  await login(clubAdmin);await q('select public.review_youth_join_request($1,$2,$3)',[pendingRequest,'accepted',clubAdmin]);
  const info=await person(otherNotice);assert.equal(info.request_status,'accepted');assert.equal(info.review_status,'verified');
  assert.equal((await val('select public.role_manager_person_v2($1)',[pending])).user_id,pending);
  await db.exec('reset role');const rolesAfter=(await q('select * from app_private.role_assignments where user_id=$1',[pending])).rows;assert.equal(rolesAfter.length,0);
  assert.equal(await val('select count(*)::int from public.youth_memberships where user_id=$1 and youth_id=$2 and is_member',[pending,b]),0);
  await login(clubAdmin);const approved=await val('select public.role_manager_person_v2($1)',[pending]);
  await q('select public.save_person_roles_v2($1,null,$2,$3,$4,$5)',[pending,[{id:a,role:'youth_moderator'}],approved.revision,id(902),clubAdmin]);
  const after=await val('select public.role_manager_person_v2($1)',[pending]);
  assert.equal(after.clubs.find(c=>c.id===a).role,'youth_moderator');assert.equal(after.global_role,approved.global_role);
  assert.equal(after.clubs.find(c=>c.id===b).role,approved.clubs.find(c=>c.id===b).role);

 });
 await check('revoking the club admin denies stale notification details and role navigation',async()=>{
  await db.exec('reset role');await q('delete from app_private.role_assignments where user_id=$1 and youth_id=$2',[clubAdmin,a]);
  await login(clubAdmin);assert.equal(await person(otherNotice),null);
  await assert.rejects(()=>q('select public.role_manager_person_v2($1)',[later]),e=>e.code==='42501');
 });
}
