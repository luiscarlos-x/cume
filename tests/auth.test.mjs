import test from 'node:test';
import assert from 'node:assert/strict';
import {createAuthStorage} from '../lib/auth-storage.ts';
import {changePassword} from '../lib/password.ts';

const storage=()=>{const values=new Map();return {getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)}};

test('remembered sessions survive a new browser tab',()=>{
  const local=storage(),tab=storage(),first=createAuthStorage(local,tab);
  first.setRemember(true);first.setItem('session','token');
  assert.equal(local.getItem('session'),'token');
  assert.equal(tab.getItem('session'),null);
  assert.equal(createAuthStorage(local,storage()).getItem('session'),'token');
});
test('unchecked login survives reload but is absent from a new tab',()=>{
  const local=storage(),tab=storage(),first=createAuthStorage(local,tab);
  first.setRemember(false);first.setItem('session','temporary');
  assert.equal(local.getItem('session'),null);
  assert.equal(createAuthStorage(local,tab).getItem('session'),'temporary');
  assert.equal(createAuthStorage(local,storage()).getItem('session'),null);
});
test('logout removes session from both storage locations',()=>{
  const local=storage(),tab=storage(),auth=createAuthStorage(local,tab);
  local.setItem('session','old');tab.setItem('session','new');
  auth.removeItem('session');
  assert.equal(local.getItem('session'),null);assert.equal(tab.getItem('session'),null);
});
test('blocked browser storage falls back to memory for the current page',()=>{
  const blocked={getItem(){throw new Error('blocked')},setItem(){throw new Error('blocked')},removeItem(){throw new Error('blocked')}};
  const auth=createAuthStorage(blocked,blocked);
  auth.setRemember(true);auth.setItem('session','token');
  assert.equal(auth.getItem('session'),'token');
  auth.removeItem('session');assert.equal(auth.getItem('session'),null);
});
test('password confirmation is checked before contacting auth',async()=>{
  let calls=0;
  const auth={signInWithPassword:async()=>{calls++;return {error:null}},updateUser:async()=>{calls++;return {error:null}}};
  await assert.rejects(()=>changePassword(auth,'person@example.com','current','new-password-123','different'),/confirmação/);
  await assert.rejects(()=>changePassword(auth,'person@example.com','current','short','short'),/12 caracteres/);
  assert.equal(calls,0);
});
test('wrong current password cannot update the password',async()=>{
  let updates=0;
  const auth={signInWithPassword:async()=>({error:{code:'invalid_credentials'}}),updateUser:async()=>{updates++;return {error:null}}};
  await assert.rejects(()=>changePassword(auth,'person@example.com','wrong','new-password-123','new-password-123'),/atual está incorreta/);
  assert.equal(updates,0);
});
test('password update follows reauthentication and preserves spaces',async()=>{
  const calls=[],password=' new-password-123 ';
  const auth={signInWithPassword:async value=>{calls.push(['verify',value]);return {error:null}},updateUser:async value=>{calls.push(['update',value]);return {error:null}}};
  await changePassword(auth,'person@example.com',' current ',password,password);
  assert.deepEqual(calls,[['verify',{email:'person@example.com',password:' current '}],['update',{password}]]);
});
