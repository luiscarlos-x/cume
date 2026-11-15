begin;
create table public.budgets(
 id uuid primary key default gen_random_uuid(),owner_user_id uuid not null default auth.uid() references public.profiles,household_id uuid references public.households,category_id uuid not null references public.categories,month date not null check(extract(day from month)=1),limit_cents bigint not null check(limit_cents between 0 and 1000000000000),discretionary boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index budgets_personal_unique on public.budgets(owner_user_id,category_id,month) where household_id is null;
create unique index budgets_house_unique on public.budgets(household_id,category_id,month) where household_id is not null;
create index on public.budgets(category_id);
create table public.spending_plans(
 id uuid primary key default gen_random_uuid(),owner_user_id uuid not null default auth.uid() unique references public.profiles,horizon_on date not null,essential_remaining_cents bigint not null default 0 check(essential_remaining_cents between 0 and 1000000000000),buffer_cents bigint not null default 0 check(buffer_cents between 0 and 1000000000000),goal_cents bigint not null default 0 check(goal_cents between 0 and 1000000000000),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.transaction_splits(
 id uuid primary key default gen_random_uuid(),transaction_id uuid not null references public.transactions,user_id uuid not null references public.profiles,share_cents bigint not null check(share_cents between 0 and 1000000000000),method text not null check(method in ('equal','percent','fixed')),created_at timestamptz not null default now(),unique(transaction_id,user_id));
create index on public.transaction_splits(user_id);
create table public.settlements(
 id uuid primary key,transaction_id uuid not null references public.transactions,household_id uuid not null references public.households,debtor_id uuid not null references public.profiles,creditor_id uuid not null references public.profiles,amount_cents bigint not null check(amount_cents>0 and amount_cents<=1000000000000),paid_on date not null,status text not null default 'pending' check(status in ('pending','confirmed','cancelled')),created_by uuid not null references public.profiles,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(debtor_id<>creditor_id));
create index on public.settlements(transaction_id,debtor_id);
create index on public.settlements(household_id);
create index on public.settlements(debtor_id);
create index on public.settlements(creditor_id);
create index on public.settlements(created_by);
create table public.settlement_entries(
 id uuid primary key default gen_random_uuid(),settlement_id uuid not null references public.settlements,owner_user_id uuid not null references public.profiles,account_id uuid not null references public.accounts,direction text not null check(direction in ('in','out')),amount_cents bigint not null check(amount_cents>0 and amount_cents<=1000000000000),occurred_on date not null,active boolean not null default true,created_at timestamptz not null default now(),unique(settlement_id,direction));
create index on public.settlement_entries(owner_user_id);
create index on public.settlement_entries(account_id,occurred_on);
create table public.reconciliations(
 id uuid primary key,owner_user_id uuid not null references public.profiles,account_id uuid not null references public.accounts,statement_on date not null,reported_cents bigint not null check(abs(reported_cents)<=1000000000000),book_cents bigint not null,difference_cents bigint not null,adjusted boolean not null,note text not null check(length(trim(note)) between 1 and 240),created_at timestamptz not null default now(),check(difference_cents=reported_cents-book_cents));
create index on public.reconciliations(owner_user_id);
create index on public.reconciliations(account_id,statement_on);
create table public.account_adjustments(
 id uuid primary key default gen_random_uuid(),reconciliation_id uuid not null unique references public.reconciliations,owner_user_id uuid not null references public.profiles,account_id uuid not null references public.accounts,amount_cents bigint not null check(amount_cents<>0),occurred_on date not null,created_at timestamptz not null default now());
create index on public.account_adjustments(owner_user_id);
create index on public.account_adjustments(account_id,occurred_on);

alter table public.budgets enable row level security;
alter table public.spending_plans enable row level security;
alter table public.transaction_splits enable row level security;
alter table public.settlements enable row level security;
alter table public.settlement_entries enable row level security;
alter table public.reconciliations enable row level security;
alter table public.account_adjustments enable row level security;
create function private.shared_transaction(tid uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.transactions t where t.id=tid and t.scope='household' and private.member_of(t.household_id))$$;
create policy budgets_read on public.budgets for select to authenticated using((household_id is null and owner_user_id=(select auth.uid())) or (household_id is not null and private.member_of(household_id)));
create policy budgets_insert on public.budgets for insert to authenticated with check(owner_user_id=(select auth.uid()) and (household_id is null or private.owner_of(household_id)));
create policy budgets_update on public.budgets for update to authenticated using((household_id is null and owner_user_id=(select auth.uid())) or (household_id is not null and private.owner_of(household_id))) with check((household_id is null and owner_user_id=(select auth.uid())) or (household_id is not null and private.owner_of(household_id)));
create policy budgets_delete on public.budgets for delete to authenticated using((household_id is null and owner_user_id=(select auth.uid())) or (household_id is not null and private.owner_of(household_id)));
create policy plans_read on public.spending_plans for select to authenticated using(owner_user_id=(select auth.uid()));
create policy plans_insert on public.spending_plans for insert to authenticated with check(owner_user_id=(select auth.uid()));
create policy plans_update on public.spending_plans for update to authenticated using(owner_user_id=(select auth.uid())) with check(owner_user_id=(select auth.uid()));
create policy splits_read on public.transaction_splits for select to authenticated using(private.shared_transaction(transaction_id));
create policy settlements_read on public.settlements for select to authenticated using(private.member_of(household_id));
create policy entries_read on public.settlement_entries for select to authenticated using(owner_user_id=(select auth.uid()));
create policy reconciliations_read on public.reconciliations for select to authenticated using(exists(select 1 from public.accounts a where a.id=reconciliations.account_id));
create policy adjustments_read on public.account_adjustments for select to authenticated using(exists(select 1 from public.accounts a where a.id=account_adjustments.account_id));

create function private.validate_planning() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.categories;begin
 if tg_op='UPDATE' and (new.id<>old.id or new.owner_user_id<>old.owner_user_id or new.created_at<>old.created_at) then raise exception 'Identidade e dono imutáveis'; end if;
 if tg_table_name='budgets' then
  if tg_op='UPDATE' and (new.household_id is distinct from old.household_id or new.category_id<>old.category_id or new.month<>old.month) then raise exception 'Âmbito, categoria e mês imutáveis'; end if;
  select * into c from public.categories where id=new.category_id;
  if c.id is null or c.kind<>'expense' or not ((new.household_id is null and c.household_id is null and c.owner_user_id=auth.uid()) or (new.household_id is not null and c.household_id=new.household_id and private.owner_of(new.household_id))) then raise exception 'Categoria de orçamento não autorizada'; end if;
 else
  if new.horizon_on<(now() at time zone 'America/Fortaleza')::date or new.horizon_on>(now() at time zone 'America/Fortaleza')::date+366 then raise exception 'Escolha um horizonte entre hoje e 366 dias'; end if;
 end if;
 new.updated_at=now();return new;
end $$;
create trigger validate_budget before insert or update on public.budgets for each row execute function private.validate_planning();
create trigger validate_plan before insert or update on public.spending_plans for each row execute function private.validate_planning();
create function private.guard_money_change() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_table_name='transactions' then
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
create trigger guard_transaction_money before insert or update on public.transactions for each row execute function private.guard_money_change();
create trigger guard_account_money before update on public.accounts for each row execute function private.guard_money_change();
create trigger guard_category_money before update on public.categories for each row execute function private.guard_money_change();
create trigger audit_budgets after insert or update or delete on public.budgets for each row execute function private.audit_write();
create trigger audit_plans after insert or update on public.spending_plans for each row execute function private.audit_write();
create trigger audit_splits after insert or update or delete on public.transaction_splits for each row execute function private.audit_write();
create trigger audit_settlements after insert or update on public.settlements for each row execute function private.audit_write();
create trigger audit_reconciliations after insert on public.reconciliations for each row execute function private.audit_write();
create trigger audit_adjustments after insert on public.account_adjustments for each row execute function private.audit_write();

create function private.set_transaction_split(tx_id uuid,shares jsonb,split_method text) returns void language plpgsql security definer set search_path='' as $$
declare t public.transactions;a public.accounts;n int;total numeric;begin
 select * into t from public.transactions where id=tx_id for update;
 if auth.uid() is null or t.id is null or t.user_id<>auth.uid() or t.scope<>'household' or t.kind<>'expense' or t.status<>'confirmed' or not private.member_of(t.household_id) then raise exception 'Rateio não autorizado';end if;
 select * into a from public.accounts where id=t.account_id;
 if a.household_id is not null or a.owner_user_id<>auth.uid() then raise exception 'Rateie somente despesas pagas por conta pessoal';end if;
 if shares is null or jsonb_typeof(shares)<>'array' or split_method is null or split_method not in ('equal','percent','fixed') then raise exception 'Rateio inválido';end if;
 if exists(select 1 from public.settlements where transaction_id=tx_id and status<>'cancelled') then raise exception 'Rateio com reembolso ativo não pode mudar';end if;
 n=jsonb_array_length(shares);
 if n=0 then delete from public.transaction_splits where transaction_id=tx_id;return;end if;
 if n<2 or n<>(select count(distinct x->>'user_id') from jsonb_array_elements(shares) x) or not exists(select 1 from jsonb_array_elements(shares) x where (x->>'user_id')::uuid=t.user_id) then raise exception 'Inclua pagador e ao menos duas pessoas distintas';end if;
 if exists(select 1 from jsonb_array_elements(shares) x where x->>'share_cents' is null or x->>'share_cents' !~ '^[0-9]+$' or not exists(select 1 from public.household_members m where m.household_id=t.household_id and m.user_id=(x->>'user_id')::uuid)) then raise exception 'Cotas ou membros inválidos';end if;
 select sum((x->>'share_cents')::numeric) into total from jsonb_array_elements(shares) x;
 if total<>t.amount_cents then raise exception 'Cotas devem somar exatamente a despesa';end if;
 delete from public.transaction_splits where transaction_id=tx_id;
 insert into public.transaction_splits(transaction_id,user_id,share_cents,method) select tx_id,(x->>'user_id')::uuid,(x->>'share_cents')::bigint,split_method from jsonb_array_elements(shares) x;
end $$;
create function private.record_settlement(request_id uuid,tx_id uuid,pay_account uuid,amount bigint,payment_on date) returns uuid language plpgsql security definer set search_path='' as $$
declare t public.transactions;a public.accounts;s public.settlements;share bigint;used bigint;begin
 if auth.uid() is null or request_id is null then raise exception 'Autenticação necessária';end if;
 select * into t from public.transactions where id=tx_id for update;
 if t.id is null or t.scope<>'household' or t.status<>'confirmed' or t.kind<>'expense' or t.user_id=auth.uid() or not private.member_of(t.household_id) or not exists(select 1 from public.household_members where household_id=t.household_id and user_id=t.user_id) then raise exception 'Reembolso não autorizado';end if;
 select * into s from public.settlements where id=request_id;
 if s.id is not null then
  if s.debtor_id=auth.uid() and s.transaction_id=tx_id and s.amount_cents=amount and s.paid_on=payment_on and exists(select 1 from public.settlement_entries where settlement_id=s.id and direction='out' and account_id=pay_account) then return s.id;end if;raise exception 'Identificador já utilizado';
 end if;
 select share_cents into share from public.transaction_splits where transaction_id=tx_id and user_id=auth.uid();
 select coalesce(sum(amount_cents),0) into used from public.settlements where transaction_id=tx_id and debtor_id=auth.uid() and status<>'cancelled';
 if amount is null or amount<=0 or share is null or amount>share-used then raise exception 'Valor excede a cota em aberto';end if;
 select * into a from public.accounts where id=pay_account for update;
 if a.id is null or a.owner_user_id<>auth.uid() or a.household_id is not null then raise exception 'Use uma conta pessoal sua';end if;
 if payment_on is null or payment_on<t.occurred_on or payment_on<a.opening_on or payment_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data de pagamento inválida';end if;
 insert into public.settlements(id,transaction_id,household_id,debtor_id,creditor_id,amount_cents,paid_on,created_by) values(request_id,tx_id,t.household_id,auth.uid(),t.user_id,amount,payment_on,auth.uid());
 insert into public.settlement_entries(settlement_id,owner_user_id,account_id,direction,amount_cents,occurred_on) values(request_id,auth.uid(),pay_account,'out',amount,payment_on);
 return request_id;
end $$;
create function private.confirm_settlement(settlement_id uuid,receive_account uuid,received_on date) returns void language plpgsql security definer set search_path='' as $$
declare s public.settlements;a public.accounts;begin
 select * into s from public.settlements where id=settlement_id for update;
 if auth.uid() is null or s.id is null or s.creditor_id<>auth.uid() or not private.member_of(s.household_id) then raise exception 'Recebimento não autorizado';end if;
 if s.status='confirmed' then return;end if;if s.status<>'pending' then raise exception 'Reembolso indisponível';end if;
 select * into a from public.accounts where id=receive_account for update;
 if a.id is null or a.owner_user_id<>auth.uid() or a.household_id is not null then raise exception 'Use uma conta pessoal sua';end if;
 if received_on is null or received_on<s.paid_on or received_on<a.opening_on or received_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data de recebimento inválida';end if;
 insert into public.settlement_entries(settlement_id,owner_user_id,account_id,direction,amount_cents,occurred_on) values(s.id,auth.uid(),receive_account,'in',s.amount_cents,received_on);
 update public.settlements set status='confirmed',updated_at=now() where id=s.id;
end $$;
create function private.cancel_settlement(sid uuid) returns void language plpgsql security definer set search_path='' as $$
declare s public.settlements;begin
 select * into s from public.settlements where id=sid for update;
 if auth.uid() is null or s.id is null or s.debtor_id<>auth.uid() or not private.member_of(s.household_id) then raise exception 'Cancelamento não autorizado';end if;
 if s.status='cancelled' then return;end if;if s.status<>'pending' then raise exception 'Recebimento confirmado não pode ser cancelado unilateralmente';end if;
 perform a.id from public.accounts a join public.settlement_entries e on e.account_id=a.id where e.settlement_id=sid order by a.id for update of a;
 update public.settlement_entries set active=false where settlement_id=sid;
 update public.settlements set status='cancelled',updated_at=now() where id=sid;
end $$;
create function private.account_book_balance(aid uuid,at_date date) returns bigint language sql stable security definer set search_path='' as $$
 select a.opening_balance_cents+coalesce((select sum(case when t.kind='income' then t.amount_cents else -t.amount_cents end) from public.transactions t where t.account_id=a.id and t.status='confirmed' and t.occurred_on<=at_date),0)+coalesce((select sum(case when e.direction='in' then e.amount_cents else -e.amount_cents end) from public.settlement_entries e where e.account_id=a.id and e.active and e.occurred_on<=at_date),0)+coalesce((select sum(x.amount_cents) from public.account_adjustments x where x.account_id=a.id and x.occurred_on<=at_date),0) from public.accounts a where a.id=aid
$$;
create function private.reconcile_account(request_id uuid,aid uuid,at_date date,reported bigint,expected_book bigint,reason text,post_adjustment boolean) returns uuid language plpgsql security definer set search_path='' as $$
declare a public.accounts;book bigint;r public.reconciliations;begin
 if auth.uid() is null or request_id is null then raise exception 'Autenticação necessária';end if;
 select * into a from public.accounts where id=aid for update;
 if a.id is null or a.owner_user_id<>auth.uid() or (a.household_id is not null and not private.member_of(a.household_id)) then raise exception 'Reconciliação não autorizada';end if;
 select * into r from public.reconciliations where id=request_id;
 if r.id is not null then
  if r.owner_user_id=auth.uid() and r.account_id=aid and r.statement_on=at_date and r.reported_cents=reported and r.adjusted=post_adjustment and r.note=trim(reason) then return r.id;end if;raise exception 'Identificador já utilizado';
 end if;
 if at_date is null or at_date<a.opening_on or at_date>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data de conferência inválida';end if;
 book:=private.account_book_balance(aid,at_date);
 if expected_book is null or book<>expected_book then raise exception 'O saldo mudou. Atualize e confira novamente';end if;
 insert into public.reconciliations(id,owner_user_id,account_id,statement_on,reported_cents,book_cents,difference_cents,adjusted,note) values(request_id,auth.uid(),aid,at_date,reported,book,reported-book,post_adjustment,trim(reason));
 if post_adjustment and reported<>book then insert into public.account_adjustments(reconciliation_id,owner_user_id,account_id,amount_cents,occurred_on) values(request_id,auth.uid(),aid,reported-book,at_date);end if;
 return request_id;
end $$;
revoke all on public.budgets,public.spending_plans,public.transaction_splits,public.settlements,public.settlement_entries,public.reconciliations,public.account_adjustments from anon,authenticated;
grant select on public.budgets,public.spending_plans,public.transaction_splits,public.settlements,public.settlement_entries,public.reconciliations,public.account_adjustments to authenticated;
grant insert,update,delete on public.budgets to authenticated;
grant insert,update on public.spending_plans to authenticated;
revoke all on function private.shared_transaction(uuid),private.validate_planning(),private.guard_money_change(),private.set_transaction_split(uuid,jsonb,text),private.record_settlement(uuid,uuid,uuid,bigint,date),private.confirm_settlement(uuid,uuid,date),private.cancel_settlement(uuid),private.account_book_balance(uuid,date),private.reconcile_account(uuid,uuid,date,bigint,bigint,text,boolean) from public,anon,authenticated;
grant execute on function private.shared_transaction(uuid),private.set_transaction_split(uuid,jsonb,text),private.record_settlement(uuid,uuid,uuid,bigint,date),private.confirm_settlement(uuid,uuid,date),private.cancel_settlement(uuid),private.reconcile_account(uuid,uuid,date,bigint,bigint,text,boolean) to authenticated;
create function public.set_transaction_split(tx_id uuid,shares jsonb,split_method text) returns void language sql security invoker set search_path='' as $$select private.set_transaction_split(tx_id,shares,split_method)$$;
create function public.record_settlement(request_id uuid,tx_id uuid,pay_account uuid,amount bigint,payment_on date) returns uuid language sql security invoker set search_path='' as $$select private.record_settlement(request_id,tx_id,pay_account,amount,payment_on)$$;
create function public.confirm_settlement(settlement_id uuid,receive_account uuid,received_on date) returns void language sql security invoker set search_path='' as $$select private.confirm_settlement(settlement_id,receive_account,received_on)$$;
create function public.cancel_settlement(sid uuid) returns void language sql security invoker set search_path='' as $$select private.cancel_settlement(sid)$$;
create function public.reconcile_account(request_id uuid,aid uuid,at_date date,reported bigint,expected_book bigint,reason text,post_adjustment boolean) returns uuid language sql security invoker set search_path='' as $$select private.reconcile_account(request_id,aid,at_date,reported,expected_book,reason,post_adjustment)$$;
revoke all on function public.set_transaction_split(uuid,jsonb,text),public.record_settlement(uuid,uuid,uuid,bigint,date),public.confirm_settlement(uuid,uuid,date),public.cancel_settlement(uuid),public.reconcile_account(uuid,uuid,date,bigint,bigint,text,boolean) from public,anon;
grant execute on function public.set_transaction_split(uuid,jsonb,text),public.record_settlement(uuid,uuid,uuid,bigint,date),public.confirm_settlement(uuid,uuid,date),public.cancel_settlement(uuid),public.reconcile_account(uuid,uuid,date,bigint,bigint,text,boolean) to authenticated;
commit;
