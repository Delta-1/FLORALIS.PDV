-- Productos "sin precio" (precio al vender, sin control de stock), producto "Otro producto"
-- por empresa, y reglas de moneda por medio de pago: PIX solo BRL, QR solo BOB.

alter table public.products add column if not exists open_price boolean not null default false;

insert into public.products(business_id,code,name,category,unit,notes,open_price)
select id,'OTRO','Otro producto','Otros','Unidad','Producto genérico: descripción y precio se ingresan al vender.',true
  from public.businesses
on conflict (business_id,code) do update set open_price=true;

create or replace function public.register_sale_v5(
  p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,
  p_currency_code text,p_received_amount numeric default null,
  p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta',
  p_terminal_id text default null
) returns uuid
language plpgsql security definer set search_path='' as $$
declare s_id uuid; item jsonb; product_row public.products%rowtype; member public.memberships%rowtype;
        total_value numeric(14,2):=0; subtotal_value numeric(14,2):=0; discount_value numeric(14,2):=0;
        qty numeric(14,3); unit_value numeric(14,2); base_value numeric(14,2); item_discount numeric(14,2);
        number_value text; sequence_name text; prefix text; customer_name text; block_no_stock boolean:=true;
        session_id uuid; payment_value numeric(14,2):=0; received_value numeric(14,2):=0; change_value numeric(14,2):=0;
        item_name text;
begin
  select * into member from public.memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  if p_currency_code not in ('BOB','BRL') then raise exception 'invalid currency'; end if;
  select id into s_id from public.sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_payment_method='PIX' and p_currency_code<>'BRL' then raise exception 'PIX only accepts BRL'; end if;
  if p_payment_method='QR' and p_currency_code<>'BOB' then raise exception 'QR only accepts BOB'; end if;
  if exists(
    select 1 from jsonb_array_elements(p_items) as entry(value)
      join public.products pr on pr.id=(entry.value->>'product_id')::uuid and pr.business_id=p_business_id
     where not pr.open_price group by pr.id having count(*)>1
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
    if p_kind='Venta' and block_no_stock and not product_row.open_price and product_row.stock<qty
      then raise exception 'insufficient stock for %',coalesce(product_row.name,'product'); end if;
    subtotal_value=subtotal_value+(qty*base_value);
    total_value=total_value+(qty*unit_value);
  end loop;
  discount_value=subtotal_value-total_value;
  if p_payment_method<>'Cuenta cliente' then
    payment_value=total_value;
    received_value=round(coalesce(p_received_amount,total_value),2);
    if received_value<0 then raise exception 'invalid payment amount'; end if;
    if p_payment_method='Efectivo' then
      if received_value+0.005<total_value then raise exception 'received amount is lower than sale total'; end if;
      change_value=greatest(0,received_value-total_value);
    else
      received_value=total_value;
    end if;
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
    p_currency_code,1,total_value,
    case when p_currency_code='BOB' and p_payment_method<>'Cuenta cliente' then payment_value else 0 end,
    case when p_currency_code='BRL' and p_payment_method<>'Cuenta cliente' then payment_value else 0 end,
    p_currency_code,payment_value,received_value,change_value
  ) returning id into s_id;
  for item in select value from jsonb_array_elements(p_items) as entry(value) order by value->>'product_id' loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    base_value=coalesce((item->>'base_price')::numeric,unit_value); item_discount=greatest(0,base_value-unit_value);
    select * into product_row from public.products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    item_name=coalesce(nullif(left(trim(item->>'description'),200),''),product_row.name);
    if p_kind='Venta' and not product_row.open_price then update public.products set stock=stock-qty,updated_at=now() where id=product_row.id; end if;
    insert into public.sale_items(
      business_id,sale_id,product_id,product_code,product_name,quantity,unit_price,discount,total,
      currency_code,unit_cost_bob,unit_cost_brl
    ) values(
      p_business_id,s_id,product_row.id,product_row.code,item_name,qty,unit_value,item_discount,qty*unit_value,
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
  if p_kind='Venta' and p_payment_method<>'Cuenta cliente' then
    insert into public.cash_movements(
      business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,
      exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id
    ) values(
      p_business_id,'in','Venta '||number_value||' — '||p_payment_method,payment_value,auth.uid(),member.display_name,s_id,
      p_currency_code,1,payment_value,
      case when p_currency_code='BOB' then payment_value else 0 end,
      case when p_currency_code='BRL' then payment_value else 0 end,session_id,p_terminal_id
    );
  end if;
  return s_id;
end $$;

revoke all on function public.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) from public,anon;
grant execute on function public.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) to authenticated;
