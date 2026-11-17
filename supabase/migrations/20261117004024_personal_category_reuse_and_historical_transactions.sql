-- Earlier transactions belong to reports, but are already included in the opening balance.
CREATE OR REPLACE FUNCTION private.validate_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a public.accounts; c public.categories; personal_category uuid;
begin
 if tg_op='UPDATE' then
  if new.id<>old.id or new.created_at<>old.created_at then raise exception 'Identidade imutável'; end if;
  if tg_table_name in ('accounts','categories') then
   if new.owner_user_id<>old.owner_user_id or new.household_id is distinct from old.household_id then raise exception 'Dono e âmbito imutáveis'; end if;
  end if;
 end if;
 if tg_table_name='transactions' then
  if tg_op='UPDATE' and (new.user_id<>old.user_id or new.scope<>old.scope or new.household_id is distinct from old.household_id) then raise exception 'Autoria e âmbito imutáveis'; end if;
  select * into a from public.accounts where id=new.account_id;
  if a.id is null or not ((a.household_id is null and a.owner_user_id=auth.uid()) or (a.household_id is not null and a.household_id=new.household_id and private.member_of(a.household_id))) then raise exception 'Conta não autorizada'; end if;
  if new.status='confirmed' and new.occurred_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data futura: use previsto'; end if;
  select * into c from public.categories where id=new.category_id;
  -- Reuse a household label without sharing the personal transaction.
  if new.scope='personal' and c.household_id is not null and c.kind=new.kind and private.member_of(c.household_id) then
   perform pg_advisory_xact_lock(hashtextextended('personal-category:'||auth.uid()::text||':'||c.kind||':'||lower(trim(c.name)),0));
   select id into personal_category from public.categories where owner_user_id=auth.uid() and household_id is null and kind=c.kind and lower(trim(name))=lower(trim(c.name)) order by created_at,id limit 1;
   if personal_category is null then
    insert into public.categories(owner_user_id,household_id,name,kind) values(auth.uid(),null,c.name,c.kind) returning id into personal_category;
   end if;
   new.category_id:=personal_category;
   select * into c from public.categories where id=personal_category;
  end if;
  if c.id is null or c.kind<>new.kind or not ((new.scope='personal' and c.household_id is null and c.owner_user_id=auth.uid()) or (new.scope='household' and c.household_id=new.household_id and private.member_of(c.household_id))) then raise exception 'Categoria não autorizada'; end if;
  new.updated_at=now();
 elsif tg_table_name='accounts' then
  if new.opening_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Saldo inicial deve ter data atual ou passada'; end if;
  if tg_op='UPDATE' and (new.opening_on<>old.opening_on or new.opening_balance_cents<>old.opening_balance_cents) and exists(select 1 from public.transactions where account_id=old.id) then raise exception 'Saldo inicial bloqueado após lançamentos'; end if;
 elsif tg_table_name='categories' then
  if tg_op='UPDATE' and new.kind<>old.kind and exists(select 1 from public.transactions where category_id=old.id) then raise exception 'Tipo da categoria em uso'; end if;
 end if;
 return new;
end $function$
;
CREATE OR REPLACE FUNCTION private.account_book_balance(aid uuid, at_date date)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select a.opening_balance_cents+coalesce((select sum(case when t.kind='income' then t.amount_cents else -t.amount_cents end) from public.transactions t where t.account_id=a.id and t.status='confirmed' and t.occurred_on>=a.opening_on and t.occurred_on<=at_date),0)+coalesce((select sum(case when e.direction='in' then e.amount_cents else -e.amount_cents end) from public.settlement_entries e where e.account_id=a.id and e.active and e.occurred_on<=at_date),0)+coalesce((select sum(x.amount_cents) from public.account_adjustments x where x.account_id=a.id and x.occurred_on<=at_date),0)+coalesce((select sum(x.amount_cents) from public.goal_cash_entries x where x.account_id=a.id and x.active and x.occurred_on<=at_date),0) from public.accounts a where a.id=aid
$function$
;
