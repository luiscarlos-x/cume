import type {SupabaseClient} from '@supabase/supabase-js';

export async function changePassword(
  auth: Pick<SupabaseClient['auth'], 'signInWithPassword' | 'updateUser'>,
  email: string,
  currentPassword: string,
  password: string,
  confirmation: string
) {
  if (!email || !currentPassword) throw new Error('Informe sua senha atual.');
  if (password.length < 12) throw new Error('Use pelo menos 12 caracteres na nova senha.');
  if (password !== confirmation) throw new Error('A confirmação não corresponde à nova senha.');
  if (password === currentPassword) throw new Error('Escolha uma senha diferente da atual.');
  const verified = await auth.signInWithPassword({email, password: currentPassword});
  if (verified.error) {
    if (verified.error.code === 'invalid_credentials') throw new Error('A senha atual está incorreta.');
    throw verified.error;
  }
  const result = await auth.updateUser({password});
  if (result.error) {
    if (result.error.code === 'weak_password') throw new Error('Escolha uma senha mais forte, com letras, números e símbolos.');
    if (result.error.code === 'same_password') throw new Error('Escolha uma senha diferente da atual.');
    throw result.error;
  }
}
