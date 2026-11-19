grant delete on public.accounts to authenticated;
create policy accounts_delete on public.accounts for delete to authenticated using(owner_user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create or replace trigger audit_accounts after insert or update or delete on public.accounts for each row execute function private.audit_write();
