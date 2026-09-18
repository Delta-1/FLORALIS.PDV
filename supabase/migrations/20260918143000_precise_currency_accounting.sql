-- Registra a moeda e a cotação no mesmo commit da venda e do movimento de caixa.
-- BOB é a moeda contábil base; display_amount preserva o valor efetivamente exibido/cobrado.
alter table public.cash_movements
  add column if not exists currency_code text not null default 'BOB',
  add column if not exists exchange_rate numeric(18,6) not null default 1,
  add column if not exists display_amount numeric(14,2) not null default 0;

update public.cash_movements
   set display_amount=amount
 where display_amount=0 and amount>0;

alter table public.cash_movements drop constraint if exists cash_movements_currency_code_check;
alter table public.cash_movements add constraint cash_movements_currency_code_check
  check (currency_code in ('BOB','BRL','USD'));
alter table public.cash_movements drop constraint if exists cash_movements_exchange_rate_check;
alter table public.cash_movements add constraint cash_movements_exchange_rate_check
  check (exchange_rate>0);
alter table public.cash_movements drop constraint if exists cash_movements_display_amount_check;
alter table public.cash_movements add constraint cash_movements_display_amount_check
  check (display_amount>=0);

create or replace function public.register_sale_v2(
  p_business_id uuid,
  p_client_id uuid,
  p_payment_method text,
  p_items jsonb,
  p_currency_code text,
  p_exchange_rate numeric,
  p_display_total numeric,
  p_notes text default null,
  p_client_sale_id text default null,
  p_kind text default 'Venta'
)
returns uuid language plpgsql security definer set search_path=public as $$
declare
  s_id uuid; item jsonb; p products%rowtype; total_value numeric(14,2):=0;
  qty numeric(14,3); unit_value numeric(14,2); item_discount numeric(14,2);
  member memberships%rowtype; number_value text; customer_name text; sequence_name text; prefix text;
  block_no_stock boolean:=true; expected_display_total numeric(14,2);
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  if p_currency_code not in ('BOB','BRL','USD') or p_exchange_rate<=0 or p_display_total<0 then raise exception 'invalid currency data'; end if;
  select id into s_id from sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_client_id is not null and not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;

  select coalesce((app_config->'options'->>'blockNoStock')::boolean,true)
    into block_no_stock from business_settings where business_id=p_business_id;
  block_no_stock:=coalesce(block_no_stock,true);

  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    if qty<=0 or unit_value<0 then raise exception 'invalid item'; end if;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found then raise exception 'invalid product'; end if;
    if p_kind='Venta' and block_no_stock and p.stock<qty then raise exception 'insufficient stock for %',coalesce(p.name,'product'); end if;
    total_value=total_value+(qty*unit_value);
  end loop;

  expected_display_total=round(total_value*p_exchange_rate,2);
  if abs(expected_display_total-p_display_total)>0.01 then raise exception 'currency total mismatch'; end if;

  prefix=case p_kind when 'Pedido' then 'P' when 'Presupuesto' then 'O' else 'V' end;
  sequence_name=case p_kind when 'Pedido' then 'sale_p' when 'Presupuesto' then 'sale_o' else 'sale_v' end;
  number_value=prefix||lpad(public.next_business_sequence(p_business_id,sequence_name)::text,6,'0');
  select name into customer_name from clients where id=p_client_id and business_id=p_business_id;
  insert into sales(business_id,sale_number,client_sale_id,kind,client_id,client_name,seller_id,seller_name,payment_method,subtotal,discount,total,notes,currency_code,exchange_rate,display_total)
  values(p_business_id,number_value,p_client_sale_id,p_kind,p_client_id,coalesce(customer_name,'Consumidor final'),auth.uid(),member.display_name,p_payment_method,total_value,0,total_value,p_notes,p_currency_code,p_exchange_rate,p_display_total)
  returning id into s_id;

  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric; item_discount=coalesce((item->>'discount')::numeric,0);
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if p_kind='Venta' then update products set stock=stock-qty,updated_at=now() where id=p.id; end if;
    insert into sale_items(business_id,sale_id,product_id,product_code,product_name,quantity,unit_price,discount,total)
    values(p_business_id,s_id,p.id,p.code,p.name,qty,unit_value,item_discount,qty*unit_value);
  end loop;

  if p_kind='Venta' and p_client_id is not null then
    update clients set purchases=purchases+1,total_purchased=total_purchased+total_value,updated_at=now() where id=p_client_id and business_id=p_business_id;
    if p_payment_method='Cuenta cliente' then
      perform public.record_client_movement_v2(p_business_id,p_client_id,'debit',total_value,'Venta '||number_value,now(),p_payment_method,number_value,s_id);
    end if;
  end if;
  if p_kind='Venta' then
    update memberships set sales_count=sales_count+1,sales_total=sales_total+total_value,average_ticket=(sales_total+total_value)/(sales_count+1),updated_at=now() where business_id=p_business_id and user_id=auth.uid();
    if p_payment_method<>'Cuenta cliente' then
      insert into cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,exchange_rate,display_amount)
      values(p_business_id,'in','Venta '||number_value||' — '||p_payment_method,total_value,auth.uid(),member.display_name,s_id,p_currency_code,p_exchange_rate,p_display_total);
    end if;
  end if;
  return s_id;
end $$;

revoke all on function public.register_sale_v2(uuid,uuid,text,jsonb,text,numeric,numeric,text,text,text) from public,anon;
grant execute on function public.register_sale_v2(uuid,uuid,text,jsonb,text,numeric,numeric,text,text,text) to authenticated;

-- A moeda deixa de ser uma segunda atualização mutável após a venda.
revoke execute on function public.set_sale_currency(uuid,text,text,numeric,numeric) from authenticated;
