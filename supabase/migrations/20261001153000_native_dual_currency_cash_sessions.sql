-- FLORALES 1.2: valores nativos por moeda e sessões de caixa persistentes.
-- A cotação deixa de participar de preços, vendas, caixa, crediário e relatórios.

alter table public.products
  add column if not exists price_bob numeric(14,2),
  add column if not exists price_brl numeric(14,2),
  add column if not exists wholesale_bob numeric(14,2),
  add column if not exists wholesale_brl numeric(14,2),
  add column if not exists cost_bob numeric(14,2),
  add column if not exists cost_brl numeric(14,2);

with business_rates as (
  select business_id,
         coalesce(nullif((app_config->'exchangeRates'->>'BRL')::numeric,0),0.5) legacy_brl_rate
    from public.business_settings
)
update public.products p
   set price_bob=coalesce(p.price_bob,p.price,0),
       price_brl=coalesce(p.price_brl,round(coalesce(p.price,0)*coalesce(r.legacy_brl_rate,0.5),2)),
       wholesale_bob=coalesce(p.wholesale_bob,p.wholesale_price,p.price,0),
       wholesale_brl=coalesce(p.wholesale_brl,round(coalesce(p.wholesale_price,p.price,0)*coalesce(r.legacy_brl_rate,0.5),2)),
       cost_bob=coalesce(p.cost_bob,p.cost,0),
       cost_brl=coalesce(p.cost_brl,round(coalesce(p.cost,0)*coalesce(r.legacy_brl_rate,0.5),2))
  from business_rates r
 where r.business_id=p.business_id;

update public.products
   set price_bob=coalesce(price_bob,price,0),
       price_brl=coalesce(price_brl,0),
       wholesale_bob=coalesce(wholesale_bob,wholesale_price,price,0),
       wholesale_brl=coalesce(wholesale_brl,price_brl,0),
       cost_bob=coalesce(cost_bob,cost,0),
       cost_brl=coalesce(cost_brl,0);

alter table public.products
  alter column price_bob set default 0,
  alter column price_bob set not null,
  alter column price_brl set default 0,
  alter column price_brl set not null,
  alter column wholesale_bob set default 0,
  alter column wholesale_bob set not null,
  alter column wholesale_brl set default 0,
  alter column wholesale_brl set not null,
  alter column cost_bob set default 0,
  alter column cost_bob set not null,
  alter column cost_brl set default 0,
  alter column cost_brl set not null;

alter table public.products drop constraint if exists products_native_prices_nonnegative;
alter table public.products add constraint products_native_prices_nonnegative check(
  price_bob>=0 and price_brl>=0 and wholesale_bob>=0 and wholesale_brl>=0 and cost_bob>=0 and cost_brl>=0
);

alter table public.sale_items
  add column if not exists currency_code text,
  add column if not exists unit_cost_bob numeric(14,2) not null default 0,
  add column if not exists unit_cost_brl numeric(14,2) not null default 0;

update public.sale_items si
   set currency_code=s.currency_code,
       unit_cost_bob=coalesce(p.cost_bob,p.cost,0),
       unit_cost_brl=coalesce(p.cost_brl,0)
  from public.sales s,public.products p
 where s.id=si.sale_id and p.id=si.product_id and si.currency_code is null;

-- As vendas BRL antigas guardavam o total BOB em total e o valor real em display_total.
-- A migração abaixo preserva o valor que o cliente efetivamente pagou e o transforma
-- no valor nativo da venda. Esta conversão acontece uma única vez no histórico legado.
with legacy_brl as (
  select id,case when total>0 then display_total/total else 1 end ratio
    from public.sales
   where currency_code='BRL' and display_total<>total
)
update public.sale_items si
   set unit_price=round(si.unit_price*l.ratio,2),
       total=round(si.total*l.ratio,2)
  from legacy_brl l
 where si.sale_id=l.id;

update public.sales
   set subtotal=display_total,
       discount=round(discount*case when total>0 then display_total/total else 1 end,2),
       total=display_total,
       exchange_rate=1,
       amount_bob=0,
       amount_brl=display_total
 where currency_code='BRL' and display_total<>total;

update public.sales
   set display_total=total,
       exchange_rate=1,
       amount_bob=case when currency_code='BOB' then total else 0 end,
       amount_brl=case when currency_code='BRL' then total else 0 end
 where currency_code in ('BOB','BRL');

update public.cash_movements
   set amount=display_amount,
       exchange_rate=1,
       amount_bob=case when currency_code='BOB' then display_amount else 0 end,
       amount_brl=case when currency_code='BRL' then display_amount else 0 end
 where currency_code in ('BOB','BRL');

alter table public.client_ledger
  add column if not exists currency_code text not null default 'BOB',
  add column if not exists amount_bob numeric(14,2) not null default 0,
  add column if not exists amount_brl numeric(14,2) not null default 0;

update public.client_ledger
   set amount_bob=case when currency_code='BOB' then amount else 0 end,
       amount_brl=case when currency_code='BRL' then amount else 0 end;

alter table public.client_ledger drop constraint if exists client_ledger_currency_code_check;
alter table public.client_ledger add constraint client_ledger_currency_code_check check(currency_code in ('BOB','BRL'));
alter table public.sale_items drop constraint if exists sale_items_currency_code_check;
alter table public.sale_items add constraint sale_items_currency_code_check check(currency_code in ('BOB','BRL'));

alter table public.clients
  add column if not exists balance_bob numeric(14,2) not null default 0,
  add column if not exists balance_brl numeric(14,2) not null default 0,
  add column if not exists total_purchased_bob numeric(14,2) not null default 0,
  add column if not exists total_purchased_brl numeric(14,2) not null default 0;

update public.clients set balance_bob=balance where balance_bob=0 and balance<>0;

with totals as (
  select client_id,
         coalesce(sum(total) filter(where currency_code='BOB' and kind='Venta'),0) total_bob,
         coalesce(sum(total) filter(where currency_code='BRL' and kind='Venta'),0) total_brl
    from public.sales where client_id is not null group by client_id
)
update public.clients c
   set total_purchased_bob=t.total_bob,total_purchased_brl=t.total_brl
  from totals t where t.client_id=c.id;

alter table public.cash_movements
  add column if not exists cash_session_id uuid,
  add column if not exists terminal_id text;

create table if not exists public.cash_sessions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  terminal_id text not null,
  status text not null default 'open' check(status in ('open','closed')),
  opening_bob numeric(14,2) not null default 0 check(opening_bob>=0),
  opening_brl numeric(14,2) not null default 0 check(opening_brl>=0),
  opened_by uuid not null references auth.users(id),
  opened_by_name text not null,
  opened_at timestamptz not null default now(),
  closed_by uuid references auth.users(id),
  closed_by_name text,
  closed_at timestamptz,
  closing_id uuid,
  created_at timestamptz not null default now()
);

create unique index if not exists cash_sessions_one_open_terminal_idx
  on public.cash_sessions(business_id,terminal_id) where status='open';
create index if not exists cash_sessions_business_opened_idx
  on public.cash_sessions(business_id,opened_at desc);

create table if not exists public.cash_closings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  cash_session_id uuid not null unique references public.cash_sessions(id) on delete restrict,
  terminal_id text not null,
  reason text not null default 'manual' check(reason in ('manual','automatic')),
  opening_bob numeric(14,2) not null default 0,
  opening_brl numeric(14,2) not null default 0,
  entries_bob numeric(14,2) not null default 0,
  entries_brl numeric(14,2) not null default 0,
  exits_bob numeric(14,2) not null default 0,
  exits_brl numeric(14,2) not null default 0,
  expected_bob numeric(14,2) not null default 0,
  expected_brl numeric(14,2) not null default 0,
  opened_at timestamptz not null,
  closed_at timestamptz not null default now(),
  opened_by_name text not null,
  closed_by uuid not null references auth.users(id),
  closed_by_name text not null,
  created_at timestamptz not null default now()
);

create index if not exists cash_closings_business_closed_idx
  on public.cash_closings(business_id,closed_at desc);
create index if not exists cash_movements_session_created_idx
  on public.cash_movements(cash_session_id,created_at) where cash_session_id is not null;
create index if not exists client_ledger_client_currency_effective_idx
  on public.client_ledger(client_id,currency_code,effective_at desc);

alter table public.cash_movements drop constraint if exists cash_movements_cash_session_id_fkey;
alter table public.cash_movements add constraint cash_movements_cash_session_id_fkey
  foreign key(cash_session_id) references public.cash_sessions(id) on delete set null;

alter table public.cash_sessions enable row level security;
alter table public.cash_closings enable row level security;

drop policy if exists cash_sessions_select on public.cash_sessions;
create policy cash_sessions_select on public.cash_sessions for select to authenticated
  using(public.is_member(business_id));
drop policy if exists cash_closings_select on public.cash_closings;
create policy cash_closings_select on public.cash_closings for select to authenticated
  using(public.is_member(business_id));

grant select on public.cash_sessions,public.cash_closings to authenticated;

create or replace function public.open_cash_session_v1(
  p_business_id uuid,p_terminal_id text,p_opening_bob numeric default 0,p_opening_brl numeric default 0
) returns public.cash_sessions
language plpgsql security definer set search_path='' as $$
declare member public.memberships%rowtype; result public.cash_sessions%rowtype;
begin
  select * into member from public.memberships
   where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if coalesce(trim(p_terminal_id),'')='' then raise exception 'invalid terminal'; end if;
  if coalesce(p_opening_bob,0)<0 or coalesce(p_opening_brl,0)<0 then raise exception 'invalid opening amount'; end if;
  select * into result from public.cash_sessions
   where business_id=p_business_id and terminal_id=p_terminal_id and status='open' limit 1;
  if found then return result; end if;
  insert into public.cash_sessions(business_id,terminal_id,opening_bob,opening_brl,opened_by,opened_by_name)
  values(p_business_id,p_terminal_id,coalesce(p_opening_bob,0),coalesce(p_opening_brl,0),auth.uid(),member.display_name)
  returning * into result;
  return result;
end $$;

create or replace function public.close_cash_session_v1(
  p_business_id uuid,p_cash_session_id uuid,p_reason text default 'manual'
) returns public.cash_closings
language plpgsql security definer set search_path='' as $$
declare member public.memberships%rowtype; session_row public.cash_sessions%rowtype;
        result public.cash_closings%rowtype; in_bob numeric(14,2); in_brl numeric(14,2);
        out_bob numeric(14,2); out_brl numeric(14,2);
begin
  select * into member from public.memberships
   where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  select * into session_row from public.cash_sessions
   where id=p_cash_session_id and business_id=p_business_id for update;
  if not found or session_row.status<>'open' then raise exception 'cash session is not open'; end if;
  select coalesce(sum(amount_bob) filter(where kind='in'),0),
         coalesce(sum(amount_brl) filter(where kind='in'),0),
         coalesce(sum(amount_bob) filter(where kind='out'),0),
         coalesce(sum(amount_brl) filter(where kind='out'),0)
    into in_bob,in_brl,out_bob,out_brl
    from public.cash_movements where cash_session_id=session_row.id;
  insert into public.cash_closings(
    business_id,cash_session_id,terminal_id,reason,opening_bob,opening_brl,
    entries_bob,entries_brl,exits_bob,exits_brl,expected_bob,expected_brl,
    opened_at,opened_by_name,closed_by,closed_by_name
  ) values(
    p_business_id,session_row.id,session_row.terminal_id,
    case when p_reason='automatic' then 'automatic' else 'manual' end,
    session_row.opening_bob,session_row.opening_brl,in_bob,in_brl,out_bob,out_brl,
    session_row.opening_bob+in_bob-out_bob,session_row.opening_brl+in_brl-out_brl,
    session_row.opened_at,session_row.opened_by_name,auth.uid(),member.display_name
  ) returning * into result;
  update public.cash_sessions set status='closed',closed_by=auth.uid(),closed_by_name=member.display_name,
    closed_at=result.closed_at,closing_id=result.id where id=session_row.id;
  return result;
end $$;

create or replace function public.record_cash_movement_v2(
  p_business_id uuid,p_cash_session_id uuid,p_kind public.cash_kind,p_description text,
  p_amount numeric,p_currency_code text
) returns uuid
language plpgsql security definer set search_path='' as $$
declare member public.memberships%rowtype; session_row public.cash_sessions%rowtype; movement_id uuid;
begin
  select * into member from public.memberships
   where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_currency_code not in ('BOB','BRL') or coalesce(p_amount,0)<=0
    then raise exception 'invalid monetary data'; end if;
  if coalesce(trim(p_description),'')='' then raise exception 'description is required'; end if;
  select * into session_row from public.cash_sessions
   where id=p_cash_session_id and business_id=p_business_id and status='open' for update;
  if not found then raise exception 'cash session is not open'; end if;
  insert into public.cash_movements(
    business_id,kind,description,amount,employee_id,employee_name,currency_code,
    exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id
  ) values(
    p_business_id,p_kind,p_description,p_amount,auth.uid(),member.display_name,p_currency_code,
    1,p_amount,case when p_currency_code='BOB' then p_amount else 0 end,
    case when p_currency_code='BRL' then p_amount else 0 end,session_row.id,session_row.terminal_id
  ) returning id into movement_id;
  return movement_id;
end $$;

create or replace function public.record_client_movement_v3(
  p_business_id uuid,p_client_id uuid,p_kind public.ledger_kind,p_amount numeric,
  p_currency_code text,p_description text,p_effective_at timestamptz default null,
  p_payment_method text default null,p_reference text default null,p_sale_id uuid default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare movement_id uuid;
begin
  if not exists(select 1 from public.memberships where business_id=p_business_id and user_id=auth.uid() and active)
    then raise exception 'access denied'; end if;
  if p_currency_code not in ('BOB','BRL') or p_amount<=0 then raise exception 'invalid monetary data'; end if;
  if not exists(select 1 from public.clients where id=p_client_id and business_id=p_business_id)
    then raise exception 'invalid client'; end if;
  insert into public.client_ledger(
    business_id,client_id,kind,amount,currency_code,amount_bob,amount_brl,description,
    effective_at,payment_method,reference,sale_id,created_by
  ) values(
    p_business_id,p_client_id,p_kind,p_amount,p_currency_code,
    case when p_currency_code='BOB' then p_amount else 0 end,
    case when p_currency_code='BRL' then p_amount else 0 end,
    p_description,coalesce(p_effective_at,now()),p_payment_method,p_reference,p_sale_id,auth.uid()
  ) returning id into movement_id;
  update public.clients set
    balance_bob=balance_bob+case when p_currency_code='BOB' then case when p_kind='credit' then p_amount else -p_amount end else 0 end,
    balance_brl=balance_brl+case when p_currency_code='BRL' then case when p_kind='credit' then p_amount else -p_amount end else 0 end,
    balance=balance_bob+case when p_currency_code='BOB' then case when p_kind='credit' then p_amount else -p_amount end else 0 end,
    updated_at=now()
   where id=p_client_id and business_id=p_business_id;
  return movement_id;
end $$;

create or replace function public.register_client_payment_v1(
  p_business_id uuid,p_client_id uuid,p_amount numeric,p_currency_code text,
  p_description text,p_payment_method text,p_reference text,p_cash_session_id uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare ledger_id uuid; cash_id uuid; client_name text;
begin
  if p_payment_method is null or trim(p_payment_method)='' then raise exception 'payment method is required'; end if;
  select name into client_name from public.clients where id=p_client_id and business_id=p_business_id;
  if not found then raise exception 'invalid client'; end if;
  ledger_id:=public.record_client_movement_v3(
    p_business_id,p_client_id,'credit',p_amount,p_currency_code,p_description,now(),
    p_payment_method,p_reference,null
  );
  cash_id:=public.record_cash_movement_v2(
    p_business_id,p_cash_session_id,'in','Pago de '||client_name||' — '||p_payment_method,
    p_amount,p_currency_code
  );
  return jsonb_build_object('ledger_id',ledger_id,'cash_id',cash_id);
end $$;

create or replace function public.register_sale_v3(
  p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,
  p_currency_code text,p_notes text default null,p_client_sale_id text default null,
  p_kind text default 'Venta',p_terminal_id text default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare s_id uuid; item jsonb; product_row public.products%rowtype; member public.memberships%rowtype;
        total_value numeric(14,2):=0; subtotal_value numeric(14,2):=0; discount_value numeric(14,2):=0;
        qty numeric(14,3); unit_value numeric(14,2); base_value numeric(14,2); item_discount numeric(14,2);
        number_value text; sequence_name text; prefix text; customer_name text; block_no_stock boolean:=true;
        session_id uuid;
begin
  select * into member from public.memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  if p_currency_code not in ('BOB','BRL') then raise exception 'invalid currency'; end if;
  select id into s_id from public.sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if exists(
    select 1 from jsonb_array_elements(p_items) as item(value)
     group by value->>'product_id' having count(*)>1
  ) then raise exception 'duplicate product item'; end if;
  if p_client_id is not null and not exists(select 1 from public.clients where id=p_client_id and business_id=p_business_id)
    then raise exception 'invalid client'; end if;
  if p_kind='Venta' then
    select id into session_id from public.cash_sessions
     where business_id=p_business_id and terminal_id=p_terminal_id and status='open' limit 1;
    if session_id is null then raise exception 'cash session is not open'; end if;
  end if;
  select coalesce((app_config->'options'->>'blockNoStock')::boolean,true) into block_no_stock
    from public.business_settings where business_id=p_business_id;
  block_no_stock:=coalesce(block_no_stock,true);
  for item in select value from jsonb_array_elements(p_items) as entry(value) order by value->>'product_id' loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    base_value=coalesce((item->>'base_price')::numeric,unit_value);
    if qty<=0 or unit_value<0 or base_value<unit_value then raise exception 'invalid item'; end if;
    select * into product_row from public.products
     where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found then raise exception 'invalid product'; end if;
    if p_kind='Venta' and block_no_stock and product_row.stock<qty
      then raise exception 'insufficient stock for %',coalesce(product_row.name,'product'); end if;
    subtotal_value=subtotal_value+(qty*base_value);
    total_value=total_value+(qty*unit_value);
  end loop;
  discount_value=subtotal_value-total_value;
  prefix=case p_kind when 'Pedido' then 'P' when 'Presupuesto' then 'O' else 'V' end;
  sequence_name=case p_kind when 'Pedido' then 'sale_p' when 'Presupuesto' then 'sale_o' else 'sale_v' end;
  number_value=prefix||lpad(public.next_business_sequence(p_business_id,sequence_name)::text,6,'0');
  select name into customer_name from public.clients where id=p_client_id and business_id=p_business_id;
  insert into public.sales(
    business_id,sale_number,client_sale_id,kind,client_id,client_name,seller_id,seller_name,
    payment_method,subtotal,discount,total,notes,currency_code,exchange_rate,display_total,amount_bob,amount_brl
  ) values(
    p_business_id,number_value,p_client_sale_id,p_kind,p_client_id,coalesce(customer_name,'Consumidor final'),
    auth.uid(),member.display_name,p_payment_method,subtotal_value,discount_value,total_value,p_notes,
    p_currency_code,1,total_value,
    case when p_currency_code='BOB' then total_value else 0 end,
    case when p_currency_code='BRL' then total_value else 0 end
  ) returning id into s_id;
  for item in select value from jsonb_array_elements(p_items) as entry(value) order by value->>'product_id' loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    base_value=coalesce((item->>'base_price')::numeric,unit_value);
    item_discount=greatest(0,base_value-unit_value);
    select * into product_row from public.products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if p_kind='Venta' then update public.products set stock=stock-qty,updated_at=now() where id=product_row.id; end if;
    insert into public.sale_items(
      business_id,sale_id,product_id,product_code,product_name,quantity,unit_price,discount,total,
      currency_code,unit_cost_bob,unit_cost_brl
    ) values(
      p_business_id,s_id,product_row.id,product_row.code,product_row.name,qty,unit_value,item_discount,qty*unit_value,
      p_currency_code,product_row.cost_bob,product_row.cost_brl
    );
  end loop;
  if p_kind='Venta' and p_client_id is not null then
    update public.clients set purchases=purchases+1,
      total_purchased_bob=total_purchased_bob+case when p_currency_code='BOB' then total_value else 0 end,
      total_purchased_brl=total_purchased_brl+case when p_currency_code='BRL' then total_value else 0 end,
      total_purchased=total_purchased_bob+case when p_currency_code='BOB' then total_value else 0 end,
      updated_at=now() where id=p_client_id and business_id=p_business_id;
    if p_payment_method='Cuenta cliente' then
      perform public.record_client_movement_v3(p_business_id,p_client_id,'debit',total_value,p_currency_code,
        'Venta '||number_value,now(),p_payment_method,number_value,s_id);
    end if;
  end if;
  if p_kind='Venta' then
    if p_payment_method<>'Cuenta cliente' then
      insert into public.cash_movements(
        business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,
        exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id
      ) values(
        p_business_id,'in','Venta '||number_value||' — '||p_payment_method,total_value,auth.uid(),member.display_name,s_id,
        p_currency_code,1,total_value,
        case when p_currency_code='BOB' then total_value else 0 end,
        case when p_currency_code='BRL' then total_value else 0 end,session_id,p_terminal_id
      );
    end if;
  end if;
  return s_id;
end $$;

revoke all on function public.open_cash_session_v1(uuid,text,numeric,numeric) from public,anon;
revoke all on function public.close_cash_session_v1(uuid,uuid,text) from public,anon;
revoke all on function public.record_cash_movement_v2(uuid,uuid,public.cash_kind,text,numeric,text) from public,anon;
revoke all on function public.record_client_movement_v3(uuid,uuid,public.ledger_kind,numeric,text,text,timestamptz,text,text,uuid) from public,anon;
revoke all on function public.register_client_payment_v1(uuid,uuid,numeric,text,text,text,text,uuid) from public,anon;
revoke all on function public.register_sale_v3(uuid,uuid,text,jsonb,text,text,text,text,text) from public,anon;
grant execute on function public.open_cash_session_v1(uuid,text,numeric,numeric) to authenticated;
grant execute on function public.close_cash_session_v1(uuid,uuid,text) to authenticated;
grant execute on function public.record_cash_movement_v2(uuid,uuid,public.cash_kind,text,numeric,text) to authenticated;
grant execute on function public.record_client_movement_v3(uuid,uuid,public.ledger_kind,numeric,text,text,timestamptz,text,text,uuid) to authenticated;
grant execute on function public.register_client_payment_v1(uuid,uuid,numeric,text,text,text,text,uuid) to authenticated;
grant execute on function public.register_sale_v3(uuid,uuid,text,jsonb,text,text,text,text,text) to authenticated;

-- A cotação antiga pode permanecer apenas como referência visual opcional.
update public.business_settings
   set app_config=(app_config-'exchangeRates')||jsonb_build_object('exchangeReference',null,'dualCurrencyNativePricing',true);
