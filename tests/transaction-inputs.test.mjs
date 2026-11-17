import {test} from 'node:test';
import assert from 'node:assert/strict';
import {transactionCategories,balance} from '../lib/finance.ts';
test('categorias pessoais incluem rótulos da casa sem expor categorias privadas alheias',()=>{
 const categories=[
 {id:'p',name:'Educação',kind:'expense',owner_user_id:'a',household_id:null},
 {id:'s',name:'Comida',kind:'expense',owner_user_id:'b',household_id:'h'},
 {id:'r',name:'Receita',kind:'income',owner_user_id:'a',household_id:'h'},
 {id:'x',name:'Privada',kind:'expense',owner_user_id:'b',household_id:null}];
 const members=[{user_id:'a',household_id:'h'}];
 assert.deepEqual(transactionCategories(categories,members,'a','expense','personal','h').map(c=>c.id),['p','s']);
 assert.deepEqual(transactionCategories(categories,[],'a','expense','personal','h').map(c=>c.id),['p']);
 assert.deepEqual(transactionCategories(categories,members,'a','expense','household','h').map(c=>c.id),['s']);
 categories.push({id:'copy',name:'Comida',kind:'expense',owner_user_id:'a',household_id:null});
 assert.deepEqual(transactionCategories(categories,members,'a','expense','personal','h').map(c=>c.id),['p','copy']);
});
test('saldo inicial não desconta duas vezes uma despesa histórica',()=>{
 const a={id:'a',opening_balance_cents:10000,opening_on:'2026-11-15'};
 const ts=[{account_id:'a',kind:'expense',status:'confirmed',amount_cents:1800,occurred_on:'2026-11-14'},{account_id:'a',kind:'expense',status:'confirmed',amount_cents:500,occurred_on:'2026-11-15'}];
 assert.equal(balance(a,ts),9500);
 ts[0].occurred_on='2026-11-15';assert.equal(balance(a,ts),7700);
});
