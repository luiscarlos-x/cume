begin;
create table public.goals(id uuid primary key, household_id uuid not null references public.households, created_by uuid not null references public.profiles, name text not null check(length(trim(name)) between 1 and 80), target_cents bigint not null check(target_cents between 1 and 1000000000000), deadline date, custody text not null check(length(trim(custody)) between 1 and 120), created_at timestamptz not null default now());
create table public.goal_contributions(id uuid primary key,goal_id uuid not null references public.goals,user_id uuid not null references public.profiles,amount_cents bigint not null check(amount_cents between 1 and 1000000000000),kind text not null check(kind in ('deposit','withdraw')),occurred_on date not null,note text not null check(length(trim(note)) between 1 and 200),status text not null default 'confirmed' check(status in ('confirmed','cancelled')),created_at timestamptz not null default now());
create table public.goal_cash_entries(id uuid primary key references public.goal_contributions,account_id uuid not null references public.accounts,owner_user_id uuid not null references public.profiles,amount_cents bigint not null,occurred_on date not null,active boolean not null default true,created_at timestamptz not null default now());
create table public.goal_commitments(id uuid primary key default gen_random_uuid(),goal_id uuid not null references public.goals,user_id uuid not null references public.profiles,monthly_cents bigint not null check(monthly_cents between 0 and 1000000000000),created_at timestamptz not null default now(),unique(goal_id,user_id));
create table public.goal_checks(id uuid primary key,goal_id uuid not null references public.goals,user_id uuid not null references public.profiles,book_cents bigint not null,reported_cents bigint not null check(reported_cents between 0 and 1000000000000),note text not null check(length(trim(note)) between 1 and 200),created_at timestamptz not null default now());
create index on public.goals(household_id);create index on public.goal_contributions(goal_id,user_id);create index on public.goal_cash_entries(account_id);create index on public.goal_cash_entries(owner_user_id);create index on public.goal_commitments(goal_id);create index on public.goal_checks(goal_id);
alter table public.goals enable row level security;alter table public.goal_contributions enable row level security;alter table public.goal_cash_entries enable row level security;alter table public.goal_commitments enable row level security;alter table public.goal_checks enable row level security;
create policy goal_read on public.goals for select to authenticated using(private.member_of(household_id));
create policy contribution_read on public.goal_contributions for select to authenticated using(exists(select 1 from public.goals g where g.id=goal_id));
create policy commitment_read on public.goal_commitments for select to authenticated using(exists(select 1 from public.goals g where g.id=goal_id));
create policy check_read on public.goal_checks for select to authenticated using(exists(select 1 from public.goals g where g.id=goal_id));
create policy cash_read on public.goal_cash_entries for select to authenticated using(owner_user_id=(select auth.uid()));
revoke all on public.goals,public.goal_contributions,public.goal_cash_entries,public.goal_commitments,public.goal_checks from anon,authenticated;
grant select on public.goals,public.goal_contributions,public.goal_cash_entries,public.goal_commitments,public.goal_checks to authenticated;
create or replace function private.account_book_balance(aid uuid,at_date date) returns bigint language sql stable security definer set search_path='' as $$
 select a.opening_balance_cents+coalesce((select sum(case when t.kind='income' then t.amount_cents else -t.amount_cents end) from public.transactions t where t.account_id=a.id and t.status='confirmed' and t.occurred_on<=at_date),0)+coalesce((select sum(case when e.direction='in' then e.amount_cents else -e.amount_cents end) from public.settlement_entries e where e.account_id=a.id and e.active and e.occurred_on<=at_date),0)+coalesce((select sum(x.amount_cents) from public.account_adjustments x where x.account_id=a.id and x.occurred_on<=at_date),0)+coalesce((select sum(x.amount_cents) from public.goal_cash_entries x where x.account_id=a.id and x.active and x.occurred_on<=at_date),0) from public.accounts a where a.id=aid
$$;
create function private.goal_command(action text,p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare gid uuid:=(p->>'goal_id')::uuid;rid uuid:=(p->>'id')::uuid;g public.goals;a public.accounts;c public.goal_contributions;v bigint;balance bigint;d date;u uuid:=auth.uid();begin
 if u is null then raise exception 'Autenticação necessária';end if;
 if action='create' then
 if not private.member_of((p->>'household_id')::uuid) or rid is null then raise exception 'Casa não autorizada';end if;
 insert into public.goals(id,household_id,created_by,name,target_cents,deadline,custody) values(rid,(p->>'household_id')::uuid,u,trim(p->>'name'),(p->>'target_cents')::bigint,nullif(p->>'deadline','')::date,trim(p->>'custody'));return rid;
 end if;
 select * into g from public.goals where id=gid for update;
 if g.id is null or not private.member_of(g.household_id) then raise exception 'Meta não autorizada';end if;
 if action='edit' then
 if g.created_by<>u then raise exception 'Somente o criador edita a meta';end if;
 update public.goals set name=trim(p->>'name'),target_cents=(p->>'target_cents')::bigint,deadline=nullif(p->>'deadline','')::date,custody=trim(p->>'custody') where id=gid;return gid;
 elsif action='commit' then
 insert into public.goal_commitments(goal_id,user_id,monthly_cents) values(gid,u,(p->>'monthly_cents')::bigint) on conflict(goal_id,user_id) do update set monthly_cents=excluded.monthly_cents;return gid;
 elsif action='move' then
 if rid is null then raise exception 'Identificador necessário';end if;
 select * into c from public.goal_contributions where id=rid;
 if c.id is not null then
 if c.goal_id=gid and c.user_id=u and c.kind=p->>'kind' and c.amount_cents=(p->>'amount_cents')::bigint and c.occurred_on=(p->>'occurred_on')::date and c.note=trim(p->>'note') and exists(select 1 from public.goal_cash_entries where id=rid and account_id=(p->>'account_id')::uuid) then return rid;end if;raise exception 'Identificador já utilizado';end if;
 v:=(p->>'amount_cents')::bigint;d:=(p->>'occurred_on')::date;
 select * into a from public.accounts where id=(p->>'account_id')::uuid for update;
 if a.id is null or a.owner_user_id<>u or a.household_id is not null then raise exception 'Use uma conta pessoal sua';end if;
 if d is null or d<a.opening_on or d>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data inválida';end if;
 if v is null or v<=0 or v>1000000000000 then raise exception 'Valor inválido';end if;
 if p->>'kind'='deposit' and v>private.account_book_balance(a.id,d) then raise exception 'Saldo insuficiente na conta';end if;
 insert into public.goal_contributions(id,goal_id,user_id,amount_cents,kind,occurred_on,note) values(rid,gid,u,v,p->>'kind',d,trim(p->>'note'));
 insert into public.goal_cash_entries(id,account_id,owner_user_id,amount_cents,occurred_on) values(rid,a.id,u,case when p->>'kind'='deposit' then -v else v end,d);
 elsif action='cancel' then
 select * into c from public.goal_contributions where id=rid and goal_id=gid;
 if c.id is null or c.user_id<>u then raise exception 'Só o autor pode desfazer';end if;
 perform 1 from public.accounts where id=(select account_id from public.goal_cash_entries where id=rid) for update;
 update public.goal_contributions set status='cancelled' where id=rid;update public.goal_cash_entries set active=false where id=rid;
 elsif action='check' then
 select coalesce(sum(case when kind='deposit' then amount_cents else -amount_cents end),0) into balance from public.goal_contributions where goal_id=gid and status='confirmed';
 if balance<>(p->>'expected_cents')::bigint or p->>'expected_cents' is null then raise exception 'O saldo mudou. Atualize e confira novamente';end if;
 insert into public.goal_checks(id,goal_id,user_id,book_cents,reported_cents,note) values(rid,gid,u,balance,(p->>'reported_cents')::bigint,trim(p->>'note'));return rid;
 else raise exception 'Ação inválida';end if;
 if exists(select 1 from (select sum(sum(case when kind='deposit' then amount_cents else -amount_cents end)) over(order by occurred_on) n from public.goal_contributions where goal_id=gid and user_id=u and status='confirmed' group by occurred_on) z where n<0) then raise exception 'Resgate excede sua reserva ou desfazer deixaria saldo negativo';end if;
 return rid;
end $$;
revoke all on function private.goal_command(text,jsonb) from public,anon,authenticated;
grant execute on function private.goal_command(text,jsonb) to authenticated;
create function public.goal_command(action text,p jsonb) returns uuid language sql security invoker set search_path='' as $$select private.goal_command(action,p)$$;
revoke all on function public.goal_command(text,jsonb) from public,anon;grant execute on function public.goal_command(text,jsonb) to authenticated;
create function private.guard_goal_account() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.opening_balance_cents,new.opening_on,new.owner_user_id,new.household_id) is distinct from (old.opening_balance_cents,old.opening_on,old.owner_user_id,old.household_id) and exists(select 1 from public.goal_cash_entries where account_id=old.id) then raise exception 'Conta vinculada à meta: use a reconciliação para ajustar saldo';end if;return new;end $$;
revoke all on function private.guard_goal_account() from public,anon,authenticated;
create trigger guard_goal_account before update on public.accounts for each row execute function private.guard_goal_account();
create trigger audit_goals after insert or update on public.goals for each row execute function private.audit_write();
create trigger audit_goal_contributions after insert or update on public.goal_contributions for each row execute function private.audit_write();
create trigger audit_goal_commitments after insert or update on public.goal_commitments for each row execute function private.audit_write();
create trigger audit_goal_checks after insert on public.goal_checks for each row execute function private.audit_write();
commit;
