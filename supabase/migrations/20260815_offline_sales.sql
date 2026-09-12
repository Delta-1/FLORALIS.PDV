alter table public.sales add column if not exists client_sale_id text;
update public.sales set client_sale_id=id::text where client_sale_id is null;
alter table public.sales alter column client_sale_id set not null;
create unique index if not exists sales_business_client_sale_uidx on public.sales(business_id,client_sale_id);

drop function if exists public.register_sale(uuid,uuid,text,jsonb,text);

create or replace function public.register_sale(p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,p_notes text default null,p_client_sale_id text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare s_id uuid; item jsonb; p products%rowtype; total_value numeric(14,2):=0; qty numeric(14,3); unit_value numeric(14,2); member memberships%rowtype; number_value text; customer_name text;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  select id into s_id from sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_client_id is not null and not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;
  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found or p.stock<qty then raise exception 'insufficient stock for %',coalesce(p.name,'product'); end if;
    total_value=total_value+(qty*unit_value);
  end loop;
  number_value='V'||to_char(now(),'YYMMDDHH24MISSMS');
  select name into customer_name from clients where id=p_client_id and business_id=p_business_id;
  insert into sales(business_id,sale_number,client_sale_id,client_id,client_name,seller_id,seller_name,payment_method,subtotal,total,notes) values(p_business_id,number_value,p_client_sale_id,p_client_id,coalesce(customer_name,'Consumidor final'),auth.uid(),member.display_name,p_payment_method,total_value,total_value,p_notes) returning id into s_id;
  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    update products set stock=stock-qty,updated_at=now() where id=p.id;
    insert into sale_items(business_id,sale_id,product_id,product_name,quantity,unit_price,total) values(p_business_id,s_id,p.id,p.name,qty,unit_value,qty*unit_value);
  end loop;
  if p_client_id is not null then
    update clients set purchases=purchases+1,total_purchased=total_purchased+total_value,updated_at=now() where id=p_client_id and business_id=p_business_id;
    if p_payment_method='Cuenta cliente' then perform record_client_movement(p_business_id,p_client_id,'debit',total_value,'Venta '||number_value); end if;
  end if;
  update memberships set sales_count=sales_count+1,sales_total=sales_total+total_value,average_ticket=(sales_total+total_value)/(sales_count+1) where business_id=p_business_id and user_id=auth.uid();
  if p_payment_method<>'Cuenta cliente' then insert into cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id) values(p_business_id,'in','Venta '||number_value||' — '||p_payment_method,total_value,auth.uid(),member.display_name,s_id); end if;
  return s_id;
end $$;

revoke all on function public.register_sale(uuid,uuid,text,jsonb,text,text) from public;
grant execute on function public.register_sale(uuid,uuid,text,jsonb,text,text) to authenticated;
