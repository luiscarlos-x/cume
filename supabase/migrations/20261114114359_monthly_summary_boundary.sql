begin;
create or replace function private.shared_summary(person_id uuid, house_id uuid, date_from date, date_to date) returns table(income_cents bigint,expense_cents bigint) language plpgsql stable security definer set search_path='' as $$
begin
 if date_from is null or date_to is null or date_from<>date_trunc('month',date_from)::date or date_to<>(date_trunc('month',date_from)+interval '1 month - 1 day')::date then raise exception 'O resumo exige um mês completo'; end if;
 if not private.member_of(house_id) or not exists(select 1 from public.household_members where household_id=house_id and user_id=person_id) or not exists(select 1 from public.data_permissions where owner_user_id=person_id and grantee_user_id=auth.uid() and household_id=house_id and level in ('summary','details')) then raise exception 'Resumo não autorizado'; end if;
 return query select coalesce(sum(amount_cents) filter(where kind='income'),0)::bigint,coalesce(sum(amount_cents) filter(where kind='expense'),0)::bigint from public.transactions where user_id=person_id and scope='personal' and status='confirmed' and occurred_on between date_from and date_to;
end $$;
commit;

