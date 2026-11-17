begin;
do $verify$
declare u uuid; h uuid; a uuid; c uuid; tx uuid; copied uuid; tx2 uuid; n bigint;
begin
 select m.user_id,m.household_id into u,h from public.household_members m join public.accounts a on a.owner_user_id=m.user_id where a.household_id is null limit 1;
 if u is null then raise exception 'Sem conta para a verificação'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 set local role authenticated;
 insert into public.accounts(name,type,opening_on,opening_balance_cents) values('Verificação temporária CUME','cash','2026-11-15',10000) returning id into a;
 insert into public.categories(name,kind,household_id) values('Verificação '||gen_random_uuid()::text,'expense',h) returning id into c;
 insert into public.transactions(account_id,category_id,kind,amount_cents,occurred_on,status,description) values(a,c,'expense',1800,'2026-11-14','confirmed','Verificação histórica') returning id,category_id into tx,copied;
 if copied=c or not exists(select 1 from public.categories where id=copied and household_id is null and owner_user_id=u) then raise exception 'A categoria não foi copiada para o pessoal'; end if;
 if not exists(select 1 from public.transactions where id=tx and scope='personal' and household_id is null) then raise exception 'Âmbito foi alterado'; end if;
 insert into public.transactions(account_id,category_id,kind,amount_cents,occurred_on,status,description) values(a,c,'expense',500,'2026-11-15','confirmed','Verificação atual') returning id into tx2;
 if (select category_id from public.transactions where id=tx2)<>copied then raise exception 'Categoria duplicada'; end if;
 begin
  insert into public.transactions(account_id,category_id,kind,amount_cents,occurred_on,status,description) values(a,c,'income',500,'2026-11-15','confirmed','Tipo incorreto');
  raise exception 'TIPO_INCORRETO_ACEITO';
 exception when others then if sqlerrm<>'Categoria não autorizada' then raise; end if; end;
 reset role;
 if private.account_book_balance(a,'2026-11-16')<>9500 then raise exception 'Saldo atual contou o histórico novamente'; end if;
 set local role authenticated;
 update public.transactions set occurred_on='2026-11-15' where id=tx;
 reset role;
 if private.account_book_balance(a,'2026-11-16')<>7700 then raise exception 'Edição de data não atualizou o saldo'; end if;
 set local role authenticated;
 update public.transactions set occurred_on='2026-11-14',status='cancelled' where id=tx;
 reset role;
 if private.account_book_balance(a,'2026-11-16')<>9500 then raise exception 'Cancelamento alterou o saldo indevidamente'; end if;
 if not exists(select 1 from public.categories where id=c and household_id=h) then raise exception 'Categoria original alterada'; end if;
end $verify$;
rollback;
select 'PASS: categoria pessoal privada, reutilização, tipo, datas antigas, edição e saldo. Nenhum dado de teste foi salvo.' as verification;