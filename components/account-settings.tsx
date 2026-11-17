'use client';
import {useState, type FormEvent} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
import {LockKeyhole, Check} from 'lucide-react';
import {changePassword} from '../lib/password';

export default function AccountSettings({db,email,demo,onSaved}:{
  db:SupabaseClient|null; email:string; demo:boolean; onSaved:()=>void;
}) {
  const [busy,setBusy]=useState(false), [error,setError]=useState('');
  async function save(event:FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if(busy)return;
    const form=event.currentTarget, fields=new FormData(form);
    setError('');setBusy(true);
    try {
      if(demo||!db)throw new Error('Entre na sua conta para alterar a senha.');
      await changePassword(db.auth,email,String(fields.get('currentPassword')||''),String(fields.get('password')||''),String(fields.get('confirmation')||''));
      form.reset();
      onSaved();
    } catch(cause) {
      setError(cause instanceof Error?cause.message:'Não foi possível alterar a senha. Tente novamente.');
    } finally {setBusy(false)}
  }
  return <section className="panel account-security">
    <div className="account-security-heading"><LockKeyhole size={24}/><div><h2>Alterar senha</h2><p>{demo?'Conta de demonstração':email}</p></div></div>
    {demo?<p className="info-banner">Entre na sua conta para alterar a senha. A demonstração não possui uma senha real.</p>:<form onSubmit={save}>
      <input type="hidden" name="username" autoComplete="username" value={email}/>
      <label>Senha atual<input name="currentPassword" type="password" autoComplete="current-password" required disabled={busy}/></label>
      <label>Nova senha<input name="password" type="password" autoComplete="new-password" minLength={12} aria-describedby="password-help" required disabled={busy}/></label>
      <label>Confirmar nova senha<input name="confirmation" type="password" autoComplete="new-password" minLength={12} required disabled={busy}/></label>
      <p id="password-help" className="form-note">Use pelo menos 12 caracteres. Você continuará conectado após a alteração.</p>
      {error&&<div className="error" role="alert">{error}</div>}
      <button className="primary" type="submit" disabled={busy}>{busy?'Alterando…':'Salvar nova senha'}<Check size={16}/></button>
    </form>}
  </section>;
}
