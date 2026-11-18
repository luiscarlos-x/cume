-- Only the author can delete a record, while still belonging to its household.
-- Foreign keys keep used categories and transactions with splits/settlements intact.
grant delete on public.transactions, public.categories to authenticated;
create policy transactions_delete on public.transactions for delete to authenticated
 using (user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy categories_delete on public.categories for delete to authenticated
 using (owner_user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));

-- Serialize deletion with reconciliation using the same account lock as other writes.
create or replace function private.guard_money_change() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='transactions' then
  if tg_op='DELETE' then
   perform id from public.accounts where id=old.account_id for update;
   return old;
  end if;
  if tg_op='UPDATE' then
   if exists(select 1 from public.transaction_splits where transaction_id=old.id) and (new.amount_cents<>old.amount_cents or new.account_id<>old.account_id or new.category_id<>old.category_id or new.kind<>old.kind or new.status<>old.status or new.occurred_on<>old.occurred_on) then raise exception 'Remova o rateio antes de alterar os valores'; end if;
   perform id from public.accounts where id in (old.account_id,new.account_id) order by id for update;
  else perform id from public.accounts where id=new.account_id for update;end if;
 elsif tg_table_name='accounts' then
  if (new.opening_on<>old.opening_on or new.opening_balance_cents<>old.opening_balance_cents) and (exists(select 1 from public.settlement_entries where account_id=old.id) or exists(select 1 from public.reconciliations where account_id=old.id)) then raise exception 'Saldo inicial bloqueado após movimentação ou conferência'; end if;
 elsif tg_table_name='categories' then
  if new.kind<>old.kind and exists(select 1 from public.budgets where category_id=old.id) then raise exception 'Categoria usada em orçamento';end if;
 end if;return new;
end $$;

create or replace trigger guard_transaction_money before insert or update or delete on public.transactions
 for each row execute function private.guard_money_change();

-- Preserve the audit trail, including the removed record's previous values.
create or replace trigger audit_transactions after insert or update or delete on public.transactions
 for each row execute function private.audit_write();
create or replace trigger audit_categories after insert or update or delete on public.categories
 for each row execute function private.audit_write();
