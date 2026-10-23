-- Integrates the contributor's tablet PDV against the existing database.
-- Old sale items remain stock-tracked; new items snapshot the stock policy at sale time.
create schema if not exists private;
revoke all on schema private from public,anon;
grant usage on schema private to authenticated;
alter table public.products add column if not exists open_price boolean not null default false;
alter table public.products add column if not exists track_stock boolean not null default true;
alter table public.sale_items add column if not exists stock_tracked boolean not null default true;
update public.products set track_stock=false where open_price and track_stock;
insert into public.products(business_id,code,name,category,unit,notes,open_price,track_stock)
select id,'OTRO','Otro producto','Otros','Unidad','Producto con descripción y precio ingresados al vender.',true,false
from public.businesses on conflict(business_id,code) do nothing;

create or replace function private.register_sale_v5(
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
  if auth.uid() is null or not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_payment_method is null or p_payment_method not in ('Efectivo','Tarjeta','PIX','QR','Transferencia','Cuenta cliente') then raise exception 'invalid payment method'; end if;
  if p_payment_method='Cuenta cliente' and p_client_id is null then raise exception 'client required'; end if;
  if p_kind is null or p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  if p_currency_code is null or p_currency_code not in ('BOB','BRL') then raise exception 'invalid currency'; end if;
  select id into s_id from public.sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
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
     where business_id=p_business_id and terminal_id=p_terminal_id and status='open' limit 1 for update;
    if session_id is null then raise exception 'cash session is not open'; end if;
  end if;
  select coalesce((app_config->'options'->>'blockNoStock')::boolean,true) into block_no_stock
    from public.business_settings where business_id=p_business_id;
  block_no_stock:=coalesce(block_no_stock,true);
  for item in select value from jsonb_array_elements(p_items) as entry(value) order by value->>'product_id' loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    base_value=coalesce((item->>'base_price')::numeric,unit_value);
    if qty is null or unit_value is null or qty in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or unit_value in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or base_value in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or qty<=0 or unit_value<0 or base_value<unit_value then raise exception 'invalid item'; end if;
    select * into product_row from public.products
     where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found or not product_row.active then raise exception 'invalid product'; end if;
    if p_kind='Venta' and block_no_stock and not product_row.open_price and product_row.track_stock and product_row.stock<qty
      then raise exception 'insufficient stock for %',coalesce(product_row.name,'product'); end if;
    subtotal_value=subtotal_value+(qty*base_value);
    total_value=total_value+(qty*unit_value);
  end loop;
  discount_value=subtotal_value-total_value;
  if p_payment_method<>'Cuenta cliente' then
    payment_value=total_value;
    received_value=round(coalesce(p_received_amount,total_value),2);
    if received_value in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or received_value<0 then raise exception 'invalid payment amount'; end if;
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
    if p_kind='Venta' and not product_row.open_price and product_row.track_stock then update public.products set stock=stock-qty,updated_at=now() where id=product_row.id; end if;
    insert into public.sale_items(
      business_id,sale_id,product_id,product_code,product_name,quantity,unit_price,discount,total,
      currency_code,unit_cost_bob,unit_cost_brl,stock_tracked
    ) values(
      p_business_id,s_id,product_row.id,product_row.code,item_name,qty,unit_value,item_discount,qty*unit_value,
      p_currency_code,product_row.cost_bob,product_row.cost_brl,not product_row.open_price and product_row.track_stock
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

revoke all on function private.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) from public,anon;
grant execute on function private.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) to authenticated;

create or replace function public.register_sale_v5(
  p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,
  p_currency_code text,p_received_amount numeric default null,
  p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta',p_terminal_id text default null
) returns uuid language sql security invoker set search_path='' as $$
 select private.register_sale_v5(p_business_id,p_client_id,p_payment_method,p_items,p_currency_code,p_received_amount,p_notes,p_client_sale_id,p_kind,p_terminal_id)
$$;
revoke all on function public.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) from public,anon;
grant execute on function public.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text) to authenticated;

create or replace function private.cancel_sale(p_business_id uuid,p_sale_id uuid,p_reason text,p_terminal_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.sales%rowtype; m public.memberships%rowtype; session_id uuid; item record; movement record; sale_currency text;
begin
 select * into m from public.memberships where business_id=p_business_id and user_id=auth.uid() and active and role='admin';
 if auth.uid() is null or m.user_id is null then raise exception 'Solo el administrador puede editar o cancelar ventas'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Escriba el motivo (mínimo 3 caracteres)'; end if;
 select * into s from public.sales where id=p_sale_id and business_id=p_business_id for update;
 if not found then raise exception 'Venta no encontrada'; end if;
 if s.status='cancelled' then return s.id; end if;
 if s.status<>'completed' then raise exception 'Estado de venta no compatible'; end if;
 select coalesce((select currency_code from public.sale_items where sale_id=s.id limit 1),'BOB') into sale_currency;
 if s.kind='Venta' then
  select id into session_id from public.cash_sessions where business_id=p_business_id and terminal_id=p_terminal_id and status='open' for update;
  if session_id is null then raise exception 'Abra la caja para registrar el estorno'; end if;
  for item in select product_id,quantity from public.sale_items where sale_id=s.id and business_id=p_business_id and stock_tracked order by product_id loop
   update public.products set stock=stock+item.quantity,updated_at=now() where id=item.product_id and business_id=p_business_id;
  end loop;
  if s.client_id is not null then
   update public.clients set purchases=greatest(0,purchases-1),total_purchased_bob=greatest(0,total_purchased_bob-case when sale_currency='BOB' then s.total else 0 end),total_purchased_brl=greatest(0,total_purchased_brl-case when sale_currency='BRL' then s.total else 0 end),total_purchased=greatest(0,total_purchased_bob-case when sale_currency='BOB' then s.total else 0 end),updated_at=now() where id=s.client_id and business_id=p_business_id;
   if s.payment_method='Cuenta cliente' and s.total>0 then
    perform public.record_client_movement_v3(p_business_id,s.client_id,'credit',s.total,sale_currency,'Cancelación '||s.sale_number||': '||p_reason,now(),s.payment_method,s.sale_number,s.id);
   end if;
  end if;
  -- Reverse the collected payment in its original currency in the currently open drawer.
  -- Account payments remain as customer credit; no fictitious cash refund is created.
  for movement in select currency_code,sum(case when kind='in' then amount else -amount end) as value from public.cash_movements where sale_id=s.id and business_id=p_business_id and s.payment_method<>'Cuenta cliente' group by currency_code loop
   if movement.value>0 then
    insert into public.cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id)
    values(p_business_id,'out','Cancelación '||s.sale_number||': '||p_reason||' — '||s.payment_method,movement.value,auth.uid(),m.display_name,s.id,movement.currency_code,1,movement.value,case when movement.currency_code='BOB' then movement.value else 0 end,case when movement.currency_code='BRL' then movement.value else 0 end,session_id,p_terminal_id);
   end if;
  end loop;
 end if;
 update public.sales set status='cancelled',cancellation_reason=trim(p_reason),cancelled_at=now(),cancelled_by=auth.uid() where id=s.id;
 insert into public.audit_logs(business_id,user_id,user_name,module,action,details,terminal_id)
 values(p_business_id,auth.uid(),m.display_name,'Ventas','Venta cancelada',jsonb_build_object('reason',p_reason,'sale',to_jsonb(s),'items',(select jsonb_agg(to_jsonb(i)) from public.sale_items i where sale_id=s.id))::text,p_terminal_id);
 return s.id;
end $$;
revoke all on function private.cancel_sale(uuid,uuid,text,text) from public,anon;
grant execute on function private.cancel_sale(uuid,uuid,text,text) to authenticated;

create or replace function public.cancel_sale_v1(p_business_id uuid,p_sale_id uuid,p_reason text,p_terminal_id text)
returns uuid language sql security invoker set search_path='' as $$ select private.cancel_sale(p_business_id,p_sale_id,p_reason,p_terminal_id) $$;
revoke all on function public.cancel_sale_v1(uuid,uuid,text,text) from public,anon;
grant execute on function public.cancel_sale_v1(uuid,uuid,text,text) to authenticated;

create or replace function private.replace_sale(p_business_id uuid,p_sale_id uuid,p_reason text,p_terminal_id text,p_payload jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.sales%rowtype; new_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.memberships where business_id=p_business_id and user_id=auth.uid() and active and role='admin') then raise exception 'Solo el administrador puede editar ventas'; end if;
 select * into s from public.sales where id=p_sale_id and business_id=p_business_id for update;
 if not found then raise exception 'Venta no encontrada'; end if;
 if s.replacement_sale_id is not null and exists(select 1 from public.sales where id=s.replacement_sale_id and client_sale_id=p_payload->>'clientSaleId') then return s.replacement_sale_id; end if;
 if s.status<>'completed' then raise exception 'La venta ya está cancelada'; end if;
 if exists(select 1 from public.sales where business_id=p_business_id and client_sale_id=p_payload->>'clientSaleId') then raise exception 'Identificador de corrección ya utilizado'; end if;
 if p_payload is null or jsonb_typeof(p_payload->'items') is distinct from 'array' then raise exception 'Productos inválidos'; end if;
 if coalesce(p_payload->>'payment','') not in ('Efectivo','Tarjeta','PIX','QR','Transferencia','Cuenta cliente') and p_payload->>'payment' is distinct from s.payment_method then raise exception 'Pago inválido'; end if;
 if coalesce(p_payload->>'paymentCurrency','') not in ('BOB','BRL') then raise exception 'Moneda inválida'; end if;
 if nullif(p_payload->>'clientSaleId','') is null then raise exception 'Identificador requerido'; end if;
 if p_payload->>'payment'='Cuenta cliente' and nullif(p_payload->>'clientId','') is null then raise exception 'Seleccione el cliente'; end if;
 if exists(select 1 from jsonb_array_elements(p_payload->'items') i where nullif(i->>'product_id','') is null or nullif(i->>'quantity','') is null or nullif(i->>'unit_price','') is null or (i->>'quantity')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or (i->>'unit_price')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Productos inválidos'; end if;
 if nullif(p_payload->>'paymentAmount','') is null or nullif(p_payload->>'receivedAmount','') is null or (p_payload->>'paymentAmount')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or (p_payload->>'receivedAmount')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Importe inválido'; end if;
 perform private.cancel_sale(p_business_id,p_sale_id,p_reason,p_terminal_id);
 if coalesce(p_payload->>'currency','BOB')=p_payload->>'paymentCurrency' then
 new_id:=public.register_sale_v5(p_business_id,nullif(p_payload->>'clientId','')::uuid,p_payload->>'payment',p_payload->'items',coalesce(p_payload->>'currency','BOB'),(p_payload->>'receivedAmount')::numeric,p_payload->>'notes',p_payload->>'clientSaleId',s.kind,p_terminal_id);
 else
 -- Legacy sales have BOB item prices and a separately entered payment currency.
 if coalesce(p_payload->>'currency','BOB')<>'BOB' then raise exception 'La corrección debe conservar la moneda de la venta'; end if;
 new_id:=public.register_sale_v4(p_business_id,nullif(p_payload->>'clientId','')::uuid,p_payload->>'payment',p_payload->'items',p_payload->>'paymentCurrency',(p_payload->>'paymentAmount')::numeric,(p_payload->>'receivedAmount')::numeric,p_payload->>'notes',p_payload->>'clientSaleId',s.kind,p_terminal_id);
 end if;
 update public.sales set seller_id=s.seller_id,seller_name=s.seller_name where id=new_id;
 update public.sales set replacement_sale_id=new_id where id=s.id;
 return new_id;
end $$;
revoke all on function private.replace_sale(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function private.replace_sale(uuid,uuid,text,text,jsonb) to authenticated;
create or replace function public.replace_sale_v1(p_business_id uuid,p_sale_id uuid,p_reason text,p_terminal_id text,p_payload jsonb)
returns uuid language sql security invoker set search_path='' as $$ select private.replace_sale(p_business_id,p_sale_id,p_reason,p_terminal_id,p_payload) $$;
revoke all on function public.replace_sale_v1(uuid,uuid,text,text,jsonb) from public,anon;
grant execute on function public.replace_sale_v1(uuid,uuid,text,text,jsonb) to authenticated;

-- Desglose del cierre de caja por medio de pago y moneda, calculado en el servidor
-- con la sesión completa y guardado en cash_closings.breakdown.
-- Regla del medio (igual en app.js cashMovementMethod): "Venta ... — Medio" -> Medio;
-- "Pago Medio ..." (crediario) -> Medio; resto -> "Otros ingresos".

alter table public.cash_closings add column if not exists breakdown jsonb not null default '[]'::jsonb;

create or replace function public.cash_movement_method(p_description text) returns text
language sql immutable set search_path='' as $$
  select coalesce(
    substring(p_description from '^(?:Venta|Cancelación) .* — ([^—]+)$'),
    substring(p_description from '^Pago ([^ ]+)'),
    'Otros ingresos')
$$;

create or replace function private.close_cash_session_v1(p_business_id uuid, p_cash_session_id uuid, p_reason text DEFAULT 'manual'::text)
 returns public.cash_closings
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare member public.memberships%rowtype; session_row public.cash_sessions%rowtype;
        result public.cash_closings%rowtype; in_bob numeric(14,2); in_brl numeric(14,2);
        out_bob numeric(14,2); out_brl numeric(14,2); breakdown_value jsonb;
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
  select coalesce(jsonb_agg(jsonb_build_object('method',method,'currency',currency,'amount',amount,'outflow',outflow) order by method,currency),'[]'::jsonb)
    into breakdown_value
    from (
      select public.cash_movement_method(description) as method,
             case when currency_code='BRL' then 'BRL' else 'BOB' end as currency,
             coalesce(sum(case when currency_code='BRL' then amount_brl else amount_bob end) filter(where kind='in'),0) as amount,
             coalesce(sum(case when currency_code='BRL' then amount_brl else amount_bob end) filter(where kind='out'),0) as outflow
        from public.cash_movements
       where cash_session_id=session_row.id
       group by 1,2
    ) grouped;
  insert into public.cash_closings(
    business_id,cash_session_id,terminal_id,reason,opening_bob,opening_brl,
    entries_bob,entries_brl,exits_bob,exits_brl,expected_bob,expected_brl,
    opened_at,opened_by_name,closed_by,closed_by_name,breakdown
  ) values(
    p_business_id,session_row.id,session_row.terminal_id,
    case when p_reason='automatic' then 'automatic' else 'manual' end,
    session_row.opening_bob,session_row.opening_brl,in_bob,in_brl,out_bob,out_brl,
    session_row.opening_bob+in_bob-out_bob,session_row.opening_brl+in_brl-out_brl,
    session_row.opened_at,session_row.opened_by_name,auth.uid(),member.display_name,breakdown_value
  ) returning * into result;
  update public.cash_sessions set status='closed',closed_by=auth.uid(),closed_by_name=member.display_name,
    closed_at=result.closed_at,closing_id=result.id where id=session_row.id;
  return result;
end $function$;

revoke all on function private.close_cash_session_v1(uuid,uuid,text) from public,anon;
grant execute on function private.close_cash_session_v1(uuid,uuid,text) to authenticated;
create or replace function public.close_cash_session_v1(p_business_id uuid,p_cash_session_id uuid,p_reason text default 'manual')
returns public.cash_closings language sql security invoker set search_path='' as $$
 select private.close_cash_session_v1(p_business_id,p_cash_session_id,p_reason)
$$;
revoke all on function public.close_cash_session_v1(uuid,uuid,text) from public,anon;
grant execute on function public.close_cash_session_v1(uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';
