-- Alinha a validação de estoque do RPC com a opção configurável do PDV.
-- Quando "blockNoStock" está desativado, a venda pode deixar estoque negativo;
-- a venda, seus itens e o débito do cliente continuam atômicos.
alter table public.products drop constraint if exists products_stock_check;

create or replace function public.register_sale(p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta')
returns uuid language plpgsql security definer set search_path=public as $$
declare
  s_id uuid; item jsonb; p products%rowtype; total_value numeric(14,2):=0;
  qty numeric(14,3); unit_value numeric(14,2); item_discount numeric(14,2);
  member memberships%rowtype; number_value text; customer_name text; sequence_name text; prefix text;
  block_no_stock boolean:=true;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  select id into s_id from sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_client_id is not null and not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;

  select coalesce((app_config->'options'->>'blockNoStock')::boolean,true)
    into block_no_stock
    from business_settings
   where business_id=p_business_id;
  block_no_stock:=coalesce(block_no_stock,true);

  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    if qty<=0 or unit_value<0 then raise exception 'invalid item'; end if;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found then raise exception 'invalid product'; end if;
    if p_kind='Venta' and block_no_stock and p.stock<qty then raise exception 'insufficient stock for %',coalesce(p.name,'product'); end if;
    total_value=total_value+(qty*unit_value);
  end loop;

  prefix=case p_kind when 'Pedido' then 'P' when 'Presupuesto' then 'O' else 'V' end;
  sequence_name=case p_kind when 'Pedido' then 'sale_p' when 'Presupuesto' then 'sale_o' else 'sale_v' end;
  number_value=prefix||lpad(public.next_business_sequence(p_business_id,sequence_name)::text,6,'0');
  select name into customer_name from clients where id=p_client_id and business_id=p_business_id;
  insert into sales(business_id,sale_number,client_sale_id,kind,client_id,client_name,seller_id,seller_name,payment_method,subtotal,discount,total,notes)
  values(p_business_id,number_value,p_client_sale_id,p_kind,p_client_id,coalesce(customer_name,'Consumidor final'),auth.uid(),member.display_name,p_payment_method,total_value,0,total_value,p_notes)
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
      insert into cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id)
      values(p_business_id,'in','Venta '||number_value||' — '||p_payment_method,total_value,auth.uid(),member.display_name,s_id);
    end if;
  end if;
  return s_id;
end $$;

revoke all on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) from public,anon;
grant execute on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) to authenticated;
