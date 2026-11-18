import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID as uuid} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';

test('Deletion permissions, balances, references and audit trail',async t=>{
 const db=new PGlite();
 try {
  await db.exec(`create role anon nologin;create role authenticated nologin;create schema auth;
   create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb);
   create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
   grant usage on schema auth to anon,authenticated;grant execute on function auth.uid() to anon,authenticated;`);
  for(const file of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+file,import.meta.url),'utf8'));
  const q=async(sql,params=[])=> (await db.query(sql,params)).rows;
  const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await db.exec(id?'set role authenticated':'set role anon')};
  const A=uuid(),B=uuid();
  await q("insert into auth.users values($1,'a@cume.invalid',now(),'{}'),($2,'b@cume.invalid',now(),'{}')",[A,B]);
  await as(A);
  const house=(await q("select public.create_household('Casa') id"))[0].id;
  const token=(await q("select public.create_invite($1,'b@cume.invalid') token",[house]))[0].token;
  const account=(await q("insert into public.accounts(name,type,opening_on,opening_balance_cents) values('Banco','bank','2020-01-01',10000) returning id"))[0].id;
  const category=(await q("insert into public.categories(name,kind) values('Categoria pessoal','expense') returning id"))[0].id;
  const sharedCategory=(await q("insert into public.categories(name,kind,household_id) values('Casa','expense',$1) returning id",[house]))[0].id;
  const tx=(await q("insert into public.transactions(account_id,category_id,kind,amount_cents,occurred_on,status,description) values($1,$2,'expense',1200,'2020-02-01','confirmed','Teste') returning id",[account,category]))[0].id;
  const sharedTx=(await q("insert into public.transactions(account_id,category_id,household_id,scope,kind,amount_cents,occurred_on,status,description) values($1,$2,$3,'household','expense',1000,'2020-02-01','confirmed','Casa') returning id",[account,sharedCategory,house]))[0].id;
  await as(B);await q('select public.accept_invite($1)',[token]);
  const bAccount=(await q("insert into public.accounts(name,type,opening_on) values('Banco B','bank','2020-01-01') returning id"))[0].id;
  await as(A);await q("insert into public.data_permissions values($1,$2,$3,'details',now())",[A,B,house]);

  await t.test('shared visibility never grants deletion',async()=>{
   await as(B);
   for(const [table,id] of [['transactions',tx],['transactions',sharedTx],['categories',category],['categories',sharedCategory]]){
    assert.equal((await q('select id from public.'+table+' where id=$1',[id])).length,1);
    assert.equal((await q('delete from public.'+table+' where id=$1 returning id',[id])).length,0);
   }
  });
  await t.test('used categories are protected by transaction and budget references',async()=>{
   await as(A);
   await assert.rejects(q('delete from public.categories where id=$1',[category]),e=>e.code==='23503');
   const budgetCategory=(await q("insert into public.categories(name,kind) values('Orçamento','expense') returning id"))[0].id;
   await q("insert into public.budgets(category_id,month,limit_cents) values($1,'2020-02-01',1000)",[budgetCategory]);
   await assert.rejects(q('delete from public.categories where id=$1',[budgetCategory]),e=>e.code==='23503');
  });
  await t.test('own deletion changes the balance and preserves the deleted values in audit',async()=>{
   const balance=async()=>Number((await q("select opening_balance_cents-coalesce((select sum(amount_cents) from public.transactions where account_id=$1 and status='confirmed'),0) as balance from public.accounts where id=$1",[account]))[0].balance);
   const before=await balance();
   assert.equal((await q('delete from public.transactions where id=$1 returning id',[tx])).length,1);
   assert.equal(await balance(),before+1200);
   const audit=(await q("select before_data,after_data from public.audit_events where entity_id=$1 and action='DELETE'",[tx]))[0];
   assert.equal(audit.before_data.amount_cents,1200);assert.equal(audit.after_data,null);
   assert.equal((await q('delete from public.categories where id=$1 returning id',[category])).length,1);
   assert.equal((await q("select id from public.audit_events where entity_id=$1 and action='DELETE'",[category])).length,1);
  });
  await t.test('split and settlement references prevent deleting a shared expense',async()=>{
   await q("select public.set_transaction_split($1,$2,'equal')",[sharedTx,JSON.stringify([{user_id:A,share_cents:500},{user_id:B,share_cents:500}])]);
   await assert.rejects(q('delete from public.transactions where id=$1',[sharedTx]),e=>e.code==='23503');
   await as(B);await q("select public.record_settlement($1,$2,$3,500,'2020-02-01')",[uuid(),sharedTx,bAccount]);
   await as(A);await assert.rejects(q('delete from public.transactions where id=$1',[sharedTx]),e=>e.code==='23503');
  });
  await t.test('a former member cannot delete records of the old household',async()=>{
   await as(B);
   const ownCategory=(await q("insert into public.categories(name,kind,household_id) values('B Casa','expense',$1) returning id",[house]))[0].id;
   const ownTx=(await q("insert into public.transactions(account_id,category_id,household_id,scope,kind,amount_cents,occurred_on,status,description) values($1,$2,$3,'household','expense',100,'2020-02-01','confirmed','B Casa') returning id",[bAccount,sharedCategory,house]))[0].id;
   await as(A);await q('select public.remove_member($1,$2)',[house,B]);await as(B);
   assert.equal((await q('delete from public.categories where id=$1 returning id',[ownCategory])).length,0);
   assert.equal((await q('delete from public.transactions where id=$1 returning id',[ownTx])).length,0);
  });
  await t.test('anonymous deletion is denied',async()=>{
   await as(null);
   for(const table of ['transactions','categories'])await assert.rejects(q('delete from public.'+table),/permission denied/);
  });
 } finally {await db.close()}
});
