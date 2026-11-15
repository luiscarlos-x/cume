-- CUME / Entrega 1. Execute with the Supabase migration owner, never a browser key.
begin;
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;
create table public.profiles(id uuid primary key references auth.users(id), display_name text not null check(length(display_name) between 1 and 80), created_at timestamptz not null default now());
create table public.households(id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 1 and 80), created_by uuid not null references public.profiles, created_at timestamptz not null default now());
create table public.household_members(household_id uuid references public.households, user_id uuid references public.profiles, role text not null check(role in ('owner','member')), joined_at timestamptz not null default now(), primary key(household_id,user_id));
create table public.data_permissions(owner_user_id uuid references public.profiles, grantee_user_id uuid references public.profiles, household_id uuid references public.households, level text not null check(level in ('summary','details')), updated_at timestamptz not null default now(), primary key(owner_user_id,grantee_user_id,household_id), check(owner_user_id<>grantee_user_id));
create table public.accounts(id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references public.profiles, household_id uuid references public.households, name text not null check(length(trim(name)) between 1 and 80), type text not null check(type in ('bank','cash','wallet')), opening_balance_cents bigint not null default 0 check(abs(opening_balance_cents)<=1000000000000), opening_on date not null, currency text not null default 'BRL' check(currency='BRL'), created_at timestamptz not null default now());
create table public.categories(id uuid primary key default gen_random_uuid(), owner_user_id uuid not null default auth.uid() references public.profiles, household_id uuid references public.households, name text not null check(length(trim(name)) between 1 and 60), kind text not null check(kind in ('income','expense')), created_at timestamptz not null default now());
create table public.transactions(id uuid primary key default gen_random_uuid(), user_id uuid not null default auth.uid() references public.profiles, account_id uuid not null references public.accounts, category_id uuid not null references public.categories, household_id uuid references public.households, scope text not null default 'personal' check(scope in ('personal','household')), kind text not null check(kind in ('income','expense')), amount_cents bigint not null check(amount_cents>0 and amount_cents<=1000000000000), occurred_on date not null, status text not null check(status in ('confirmed','planned','cancelled')), description text not null check(length(trim(description)) between 1 and 200), created_at timestamptz not null default now(), updated_at timestamptz not null default now(), check((scope='personal' and household_id is null) or (scope='household' and household_id is not null)));
create table public.household_invites(id uuid primary key default gen_random_uuid(), household_id uuid not null references public.households, email text not null check(length(email)<=254 and position('@' in email)>1), token_hash text not null unique, created_by uuid not null references public.profiles, expires_at timestamptz not null default now()+interval '7 days', accepted_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now());
create table public.audit_events(id bigint generated always as identity primary key, actor_id uuid references public.profiles, entity text not null, entity_id text not null, action text not null, before_data jsonb, after_data jsonb, created_at timestamptz not null default now());
create index on public.household_members(user_id);
create index on public.transactions(user_id,occurred_on,status);
create index on public.transactions(household_id,occurred_on,status);
create index on public.transactions(account_id);
create index on public.accounts(owner_user_id);
create index on public.categories(owner_user_id);
create index on public.data_permissions(grantee_user_id);
create index on public.audit_events(actor_id);
create index on public.accounts(household_id);
create index on public.categories(household_id);
create index on public.transactions(category_id);
create index on public.data_permissions(household_id);
create index on public.household_invites(household_id);
create index on public.household_invites(created_by);
create index on public.households(created_by);


create function private.member_of(h uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.household_members where household_id=h and user_id=auth.uid()) $$;
create function private.owner_of(h uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.household_members where household_id=h and user_id=auth.uid() and role='owner') $$;
create function private.can_read_details(u uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.data_permissions p where p.owner_user_id=u and p.grantee_user_id=auth.uid() and p.level='details' and private.member_of(p.household_id) and exists(select 1 from public.household_members m where m.household_id=p.household_id and m.user_id=u)) $$;
create function private.same_house(u uuid) returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.household_members a join public.household_members b using(household_id) where a.user_id=auth.uid() and b.user_id=u) $$;

alter table public.profiles enable row level security;
alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.data_permissions enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.household_invites enable row level security;
alter table public.audit_events enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()) or private.same_house(id));
create policy profiles_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy house_read on public.households for select to authenticated using(private.member_of(id));
create policy house_update on public.households for update to authenticated using(private.owner_of(id)) with check(private.owner_of(id));
create policy members_read on public.household_members for select to authenticated using(private.member_of(household_id));
create policy permissions_read on public.data_permissions for select to authenticated using((owner_user_id=(select auth.uid()) or grantee_user_id=(select auth.uid())) and private.member_of(household_id));
create policy permissions_insert on public.data_permissions for insert to authenticated with check(owner_user_id=(select auth.uid()) and private.member_of(household_id) and exists(select 1 from public.household_members m where m.household_id=data_permissions.household_id and m.user_id=grantee_user_id));
create policy permissions_update on public.data_permissions for update to authenticated using(owner_user_id=(select auth.uid()) and private.member_of(household_id)) with check(owner_user_id=(select auth.uid()) and private.member_of(household_id) and exists(select 1 from public.household_members m where m.household_id=data_permissions.household_id and m.user_id=grantee_user_id));
create policy permissions_delete on public.data_permissions for delete to authenticated using(owner_user_id=(select auth.uid()));
create policy accounts_read on public.accounts for select to authenticated using(owner_user_id=(select auth.uid()) or (household_id is not null and private.member_of(household_id)));
create policy accounts_insert on public.accounts for insert to authenticated with check(owner_user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy accounts_update on public.accounts for update to authenticated using(owner_user_id=(select auth.uid())) with check(owner_user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy categories_read on public.categories for select to authenticated using(owner_user_id=(select auth.uid()) or (household_id is not null and private.member_of(household_id)) or (household_id is null and private.can_read_details(owner_user_id)));
create policy categories_insert on public.categories for insert to authenticated with check(owner_user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy categories_update on public.categories for update to authenticated using(owner_user_id=(select auth.uid())) with check(owner_user_id=(select auth.uid()));
create policy transactions_read on public.transactions for select to authenticated using(user_id=(select auth.uid()) or (scope='household' and private.member_of(household_id)) or (scope='personal' and private.can_read_details(user_id)));
create policy transactions_insert on public.transactions for insert to authenticated with check(user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy transactions_update on public.transactions for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and (household_id is null or private.member_of(household_id)));
create policy invites_read on public.household_invites for select to authenticated using(private.owner_of(household_id));
create policy audit_read on public.audit_events for select to authenticated using(actor_id=(select auth.uid()));

create function private.new_profile() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,display_name) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),'Pessoa'),80)); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.new_profile();

create function private.validate_write() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.accounts; c public.categories;
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
  if new.occurred_on<a.opening_on then raise exception 'Data anterior ao saldo inicial'; end if;
  if new.status='confirmed' and new.occurred_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Data futura: use previsto'; end if;
  select * into c from public.categories where id=new.category_id;
  if c.id is null or c.kind<>new.kind or not ((new.scope='personal' and c.household_id is null and c.owner_user_id=auth.uid()) or (new.scope='household' and c.household_id=new.household_id and private.member_of(c.household_id))) then raise exception 'Categoria não autorizada'; end if;
  new.updated_at=now();
 elsif tg_table_name='accounts' then
  if new.opening_on>(now() at time zone 'America/Fortaleza')::date then raise exception 'Saldo inicial deve ter data atual ou passada'; end if;
  if tg_op='UPDATE' and (new.opening_on<>old.opening_on or new.opening_balance_cents<>old.opening_balance_cents) and exists(select 1 from public.transactions where account_id=old.id) then raise exception 'Saldo inicial bloqueado após lançamentos'; end if;
 elsif tg_table_name='categories' then
  if tg_op='UPDATE' and new.kind<>old.kind and exists(select 1 from public.transactions where category_id=old.id) then raise exception 'Tipo da categoria em uso'; end if;
 end if;
 return new;
end $$;
create trigger validate_transaction before insert or update on public.transactions for each row execute function private.validate_write();
create trigger validate_account before insert or update on public.accounts for each row execute function private.validate_write();
create trigger validate_category before update on public.categories for each row execute function private.validate_write();

create function private.audit_write() returns trigger language plpgsql security definer set search_path='' as $$
declare b jsonb; a jsonb; begin
 if tg_op<>'INSERT' then b=to_jsonb(old); end if;
 if tg_op<>'DELETE' then a=to_jsonb(new); end if;
 insert into public.audit_events(actor_id,entity,entity_id,action,before_data,after_data) values(auth.uid(),tg_table_name,coalesce(a->>'id',b->>'id',a->>'owner_user_id',b->>'owner_user_id'),tg_op,b,a);
 return coalesce(new,old);
end $$;
create trigger audit_transactions after insert or update on public.transactions for each row execute function private.audit_write();
create trigger audit_accounts after insert or update on public.accounts for each row execute function private.audit_write();
create trigger audit_categories after insert or update on public.categories for each row execute function private.audit_write();
create trigger audit_permissions after insert or update or delete on public.data_permissions for each row execute function private.audit_write();

create function public.create_household(house_name text) returns uuid language plpgsql security definer set search_path='' as $$ declare h uuid; begin
 if auth.uid() is null then raise exception 'Autenticação necessária'; end if;
 insert into public.households(name,created_by) values(trim(house_name),auth.uid()) returning id into h;
 insert into public.household_members(household_id,user_id,role) values(h,auth.uid(),'owner'); return h;
end $$;
create function public.create_invite(house_id uuid, invite_email text) returns text language plpgsql security definer set search_path='' as $$ declare token text; begin
 if not private.owner_of(house_id) then raise exception 'Somente administrador'; end if;
 token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 insert into public.household_invites(household_id,email,token_hash,created_by) values(house_id,lower(trim(invite_email)),encode(sha256(convert_to(token,'UTF8')),'hex'),auth.uid());
 return token;
end $$;
create function public.accept_invite(invite_token text) returns uuid language plpgsql security definer set search_path='' as $$ declare i public.household_invites; mail text; begin
 select lower(email) into mail from auth.users where id=auth.uid() and email_confirmed_at is not null;
 select * into i from public.household_invites where token_hash=encode(sha256(convert_to(invite_token,'UTF8')),'hex') for update;
 if mail is null or i.id is null or i.email<>mail or i.expires_at<=now() or i.accepted_at is not null or i.revoked_at is not null then raise exception 'Convite inválido, expirado ou destinado a outro e-mail'; end if;
 insert into public.household_members(household_id,user_id,role) values(i.household_id,auth.uid(),'member') on conflict do nothing;
 update public.household_invites set accepted_at=now() where id=i.id; return i.household_id;
end $$;
create function public.revoke_invite(invite_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 update public.household_invites set revoked_at=now() where id=invite_id and private.owner_of(household_id) and accepted_at is null;
 if not found then raise exception 'Convite indisponível'; end if;
end $$;
create function public.remove_member(house_id uuid, member_id uuid) returns void language plpgsql security definer set search_path='' as $$ begin
 if not private.owner_of(house_id) and auth.uid()<>member_id then raise exception 'Sem permissão'; end if;
 if exists(select 1 from public.household_members where household_id=house_id and user_id=member_id and role='owner') then raise exception 'Administrador não pode ser removido'; end if;
 delete from public.data_permissions where household_id=house_id and (owner_user_id=member_id or grantee_user_id=member_id);
 delete from public.household_members where household_id=house_id and user_id=member_id;
end $$;
create function public.shared_summary(person_id uuid, house_id uuid, date_from date, date_to date) returns table(income_cents bigint,expense_cents bigint) language plpgsql stable security definer set search_path='' as $$ begin
 if date_from>date_to or not private.member_of(house_id) or not exists(select 1 from public.household_members where household_id=house_id and user_id=person_id) or not exists(select 1 from public.data_permissions where owner_user_id=person_id and grantee_user_id=auth.uid() and household_id=house_id and level in ('summary','details')) then raise exception 'Resumo não autorizado'; end if;
 return query select coalesce(sum(amount_cents) filter(where kind='income'),0)::bigint,coalesce(sum(amount_cents) filter(where kind='expense'),0)::bigint from public.transactions where user_id=person_id and scope='personal' and status='confirmed' and occurred_on between date_from and date_to;
end $$;

-- Minimum grants. No direct membership/invitation mutation, no physical deletion of money records.
revoke all on all tables in schema public from anon,authenticated;
grant select on public.profiles,public.households,public.household_members,public.data_permissions,public.accounts,public.categories,public.transactions,public.audit_events to authenticated;
grant select(id,household_id,email,created_by,expires_at,accepted_at,revoked_at,created_at) on public.household_invites to authenticated;
grant update(display_name) on public.profiles to authenticated;
grant update(name) on public.households to authenticated;
grant insert,update on public.accounts,public.categories,public.transactions to authenticated;
grant insert,update,delete on public.data_permissions to authenticated;
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.member_of(uuid),private.owner_of(uuid),private.same_house(uuid),private.can_read_details(uuid) to authenticated;
revoke all on function public.create_household(text),public.create_invite(uuid,text),public.accept_invite(text),public.revoke_invite(uuid),public.remove_member(uuid,uuid),public.shared_summary(uuid,uuid,date,date) from public,anon;
grant execute on function public.create_household(text),public.create_invite(uuid,text),public.accept_invite(text),public.revoke_invite(uuid),public.remove_member(uuid,uuid),public.shared_summary(uuid,uuid,date,date) to authenticated;
commit;

