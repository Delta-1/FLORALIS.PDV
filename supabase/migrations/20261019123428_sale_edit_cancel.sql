-- Controlled operations only: historical sales and cash entries are never deleted.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
alter table public.sales add column if not exists cancellation_reason text,
 add column if not exists cancelled_at timestamptz,
 add column if not exists cancelled_by uuid references auth.users(id),
 add column if not exists replacement_sale_id uuid references public.sales(id);

create or replace function private.cancel_sale(p_business_id uuid,p_sale_id uuid,p_reason text,p_terminal_id text)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.sales%rowtype; m public.memberships%rowtype; session_id uuid; item record; movement record;
begin
 select * into m from public.memberships where business_id=p_business_id and user_id=auth.uid() and active and role='admin';
 if auth.uid() is null or m.user_id is null then raise exception 'Solo el administrador puede editar o cancelar ventas'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Escriba el motivo (mínimo 3 caracteres)'; end if;
 select * into s from public.sales where id=p_sale_id and business_id=p_business_id for update;
 if not found then raise exception 'Venta no encontrada'; end if;
 if s.status='cancelled' then return s.id; end if;
 if s.status<>'completed' then raise exception 'Estado de venta no compatible'; end if;
 if s.kind='Venta' then
  select id into session_id from public.cash_sessions where business_id=p_business_id and terminal_id=p_terminal_id and status='open' for update;
  if session_id is null then raise exception 'Abra la caja para registrar el estorno'; end if;
  for item in select product_id,quantity from public.sale_items where sale_id=s.id and business_id=p_business_id order by product_id loop
   update public.products set stock=stock+item.quantity,updated_at=now() where id=item.product_id and business_id=p_business_id;
  end loop;
  if s.client_id is not null then
   update public.clients set purchases=greatest(0,purchases-1),total_purchased_bob=greatest(0,total_purchased_bob-s.total),total_purchased=greatest(0,total_purchased_bob-s.total),updated_at=now() where id=s.client_id and business_id=p_business_id;
   if s.payment_method='Cuenta cliente' and s.total>0 then
    perform public.record_client_movement_v3(p_business_id,s.client_id,'credit',s.total,'BOB','Cancelación '||s.sale_number||': '||p_reason,now(),s.payment_method,s.sale_number,s.id);
   end if;
  end if;
  -- Reverse the collected payment in its original currency in the currently open drawer.
  -- Account payments remain as customer credit; no fictitious cash refund is created.
  for movement in select currency_code,sum(case when kind='in' then amount else -amount end) as value from public.cash_movements where sale_id=s.id and business_id=p_business_id and s.payment_method<>'Cuenta cliente' group by currency_code loop
   if movement.value>0 then
    insert into public.cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id,currency_code,exchange_rate,display_amount,amount_bob,amount_brl,cash_session_id,terminal_id)
    values(p_business_id,'out','Cancelación '||s.sale_number||': '||p_reason,movement.value,auth.uid(),m.display_name,s.id,movement.currency_code,1,movement.value,case when movement.currency_code='BOB' then movement.value else 0 end,case when movement.currency_code='BRL' then movement.value else 0 end,session_id,p_terminal_id);
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
 if coalesce(p_payload->>'payment','') not in ('Efectivo','PIX','QR','Transferencia','Cuenta cliente') and p_payload->>'payment' is distinct from s.payment_method then raise exception 'Pago inválido'; end if;
 if coalesce(p_payload->>'paymentCurrency','') not in ('BOB','BRL') then raise exception 'Moneda inválida'; end if;
 if nullif(p_payload->>'clientSaleId','') is null then raise exception 'Identificador requerido'; end if;
 if p_payload->>'payment'='Cuenta cliente' and nullif(p_payload->>'clientId','') is null then raise exception 'Seleccione el cliente'; end if;
 if exists(select 1 from jsonb_array_elements(p_payload->'items') i where nullif(i->>'product_id','') is null or nullif(i->>'quantity','') is null or nullif(i->>'unit_price','') is null or (i->>'quantity')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or (i->>'unit_price')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)) then raise exception 'Productos inválidos'; end if;
 if nullif(p_payload->>'paymentAmount','') is null or nullif(p_payload->>'receivedAmount','') is null or (p_payload->>'paymentAmount')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) or (p_payload->>'receivedAmount')::numeric in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric) then raise exception 'Importe inválido'; end if;
 perform private.cancel_sale(p_business_id,p_sale_id,p_reason,p_terminal_id);
 new_id:=public.register_sale_v4(p_business_id,nullif(p_payload->>'clientId','')::uuid,p_payload->>'payment',p_payload->'items',p_payload->>'paymentCurrency',(p_payload->>'paymentAmount')::numeric,(p_payload->>'receivedAmount')::numeric,p_payload->>'notes',p_payload->>'clientSaleId',s.kind,p_terminal_id);
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
