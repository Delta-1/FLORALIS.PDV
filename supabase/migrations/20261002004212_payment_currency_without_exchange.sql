alter table public.sales
  add column if not exists payment_currency_code text not null default 'BOB',
  add column if not exists payment_amount numeric(14,2) not null default 0,
  add column if not exists received_amount numeric(14,2) not null default 0,
  add column if not exists change_amount numeric(14,2) not null default 0;

alter table public.sales
  drop constraint if exists sales_payment_currency_code_check,
  drop constraint if exists sales_payment_amount_check,
  drop constraint if exists sales_received_amount_check,
  drop constraint if exists sales_change_amount_check,
  add constraint sales_payment_currency_code_check check (payment_currency_code in ('BOB','BRL')),
  add constraint sales_payment_amount_check check (payment_amount >= 0),
  add constraint sales_received_amount_check check (received_amount >= 0),
  add constraint sales_change_amount_check check (change_amount >= 0);

update public.sales
   set payment_currency_code=case when currency_code='BRL' then 'BRL' else 'BOB' end,
       payment_amount=case when payment_method='Cuenta cliente' then 0 else display_total end,
       received_amount=case when payment_method='Cuenta cliente' then 0 else display_total end,
       change_amount=0;

create index if not exists sales_business_payment_currency_idx
  on public.sales(business_id,payment_currency_code,created_at desc);

create or replace function public.register_sale_v4(
  p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,
  p_payment_currency_code text,p_payment_amount numeric,p_received_amount numeric default null,
  p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta',
  p_terminal_id text default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare s_id uuid; item jsonb; product_row public.products%rowtype; member public.memberships%rowtype;
        total_value numeric(14,2):=0; subtotal_value numeric(14,2):=0; discount_value numeric(14,2):=0;
        qty numeric(14,3); unit_value numeric(14,2); base_value numeric(14,2); item_discount numeric(14,2);
        number_value text; sequence_name text; prefix text; customer_name text; block_no_stock boolean:=true;
        session_id uuid; payment_value numeric(14,2); received_value numeric(14,2); change_value numeric(14,2):=0;
begin
  select * into member from public.memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  if p_payment_currency_code not in ('BOB','BRL') then raise exception 'invalid payment currency'; end if;
  select id into s_id from public.sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) as item(value) group by value->>'product_id' having count(*)>1)
    then raise exception 'duplicate product item'; end if;
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
  payment_value=case when p_payment_method='Cuenta cliente' then 0 else round(coalesce(p_payment_amount,0),2) end;
  received_value=case when p_payment_method='Cuenta cliente' then 0 else round(coalesce(p_received_amount,payment_value),2) end;
  if payment_value<0 or received_value<0 then raise exception 'invalid payment amount'; end if;
  if p_kind='Venta' and p_payment_method<>'Cuenta cliente' and payment_value<=0 then raise exception 'payment amount required'; end if;
  if p_payment_currency_code='BOB' and p_payment_method='Efectivo' and received_value+0.005<total_value
    then raise exception 'received amount is lower than sale total'; end if;
  if p_payment_currency_code='BOB' and p_payment_method='Efectivo' then
    payment_value=total_value; change_value=greatest(0,received_value-total_value);
  end if;
  prefix=case p_kind when 'Pedido' then 'P' when 'Presupuesto' then 'O' else 'V' end;
  sequence_name=case p_kind when 'Pedido' then 'sale_p' when 'Presupuesto' then 'sale_o' else 'sale_v' end;
  number_value=prefix||lpad(public.next_business_sequence(p_business_id,sequence_name)::text,6,'0');
  select name into customer_name from public.clients where id=p_client_id and business_id=p_business_id;
  insert into public.sales(
    business_id,sale_number,client_sale_id,kind,client_id,client_name,seller_id,seller_name,
    payment_method,subtotal,discount,total,notes,currency_code,exchange_rate,display_total,amount_bob,amount_brl,
    payment_currency_code,payment_amount,received_amount,change_amount
  ) values(
    p_business_id,number_value,p_client_sale_id,p_kind,p_client_id,coalesce(customer_name,'Consumidor final'),
    auth.uid(),member.display_name,p_payment_method,subtotal_value,discount_value,total_value,p_notes,
    p_payment_currency_code,1,payment_value,
    case when p_payment_currency_code='BOB' and p_payment_method<>'Cuenta cliente' then payment_value else 0 end,
    case when p_payment_currency_code='BRL' and p_payment_method<>'Cuenta cliente' then payment_value else 0 end,
    p_payment_currency_code,payment_value,received_value,change_value
  ) returning id into s_id;
  for item in select value from jsonb_array_elements(p_items) as entry(value) order by value->>'product_id' loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    base_value=coalesce((item->>'base_price')::numeric,unit_value); item_discount=greatest(0,base_value-unit_value);
    select * into product_row from public.products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if p_kind='Venta' then update public.products set stock=stock-qty,updated_at=now() where id=product_row.id; end if;
    insert into public.sale_items(
      business_id,sale_id,product_id,product_code,product_name,quantity,unit_price,discount,total,
      currency_code,unit_cost_bob,unit_cost_brl
    ) values(
      p_business_id,s_id,product_row.id,product_row.code,product_row.name,qty,unit_value,item_discount,qty*unit_value,
      'BOB',product_row.cost_bob,product_row.cost_brl
    );
  end loop;
  if p_kind='Venta' and p_client_id is not null then
    update public.clients set purchases=purchases+1,total_purchased_bob=total_purchased_bob+total_value,
      total_purchased=total_purchased_bob+total_value,updated_at=now()
      where id=p_client_id and business_id=p_business_id;
    if p_payment_method='Cuenta cliente' then
      perform public.record_client_movement_v3(p_business_id,p_client_id,'debit',total_value,'BOB',
        'Venta '||number_value,now(),p_payment_method,number_value,s_id);
    end if;
  end if;
  if p_kind='Venta' and p_payment_method<>'Cuenta cliente' then
    insert into public.cash_movements(
      business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,
      exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id
    ) values(
      p_business_id,'in','Venta '||number_value||' — '||p_payment_method,payment_value,auth.uid(),member.display_name,s_id,
      p_payment_currency_code,1,payment_value,
      case when p_payment_currency_code='BOB' then payment_value else 0 end,
      case when p_payment_currency_code='BRL' then payment_value else 0 end,session_id,p_terminal_id
    );
  end if;
  return s_id;
end $$;

revoke all on function public.register_sale_v4(uuid,uuid,text,jsonb,text,numeric,numeric,text,text,text,text) from public,anon;
grant execute on function public.register_sale_v4(uuid,uuid,text,jsonb,text,numeric,numeric,text,text,text,text) to authenticated;
