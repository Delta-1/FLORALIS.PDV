-- Relatórios tabulares, numeração iniciada em zero, crediário rastreável e produto de treinamento.
-- A chave service_role continua restrita às Edge Functions; o frontend usa apenas a chave publicável.

alter table public.businesses add column if not exists email text;
alter table public.businesses add column if not exists address text;
alter table public.businesses add column if not exists postal_code text;

alter table public.client_ledger add column if not exists effective_at timestamptz;
alter table public.client_ledger add column if not exists payment_method text;
alter table public.client_ledger add column if not exists reference text;
alter table public.client_ledger add column if not exists sale_id uuid references public.sales(id) on delete set null;
update public.client_ledger set effective_at=created_at where effective_at is null;
alter table public.client_ledger alter column effective_at set default now();
alter table public.client_ledger alter column effective_at set not null;

alter table public.sale_items add column if not exists product_code text;
alter table public.sale_items add column if not exists discount numeric(14,2) not null default 0;

create table if not exists public.business_sequences (
  business_id uuid not null references public.businesses(id) on delete cascade,
  sequence_name text not null,
  last_value bigint not null default -1,
  updated_at timestamptz not null default now(),
  primary key (business_id,sequence_name)
);

create table if not exists public.generated_documents (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_document_id text not null,
  document_number text not null,
  document_type text not null,
  title text not null,
  source_type text,
  source_id text,
  period_start date,
  period_end date,
  snapshot jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(business_id,client_document_id),
  unique(business_id,document_number)
);
create index if not exists generated_documents_business_date_idx on public.generated_documents(business_id,created_at desc);

alter table public.business_sequences enable row level security;
alter table public.generated_documents enable row level security;

drop policy if exists generated_documents_select on public.generated_documents;
create policy generated_documents_select on public.generated_documents for select to authenticated using (public.is_member(business_id));

create or replace function public.next_business_sequence(p_business_id uuid,p_sequence_name text)
returns bigint language plpgsql security definer set search_path=public as $$
declare next_value bigint;
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  if p_sequence_name not in ('sale_v','sale_p','sale_o','document') then raise exception 'invalid sequence'; end if;
  insert into business_sequences(business_id,sequence_name,last_value)
  values(p_business_id,p_sequence_name,0)
  on conflict(business_id,sequence_name) do update
    set last_value=business_sequences.last_value+1,updated_at=now()
  returning last_value into next_value;
  return next_value;
end $$;

create or replace function public.record_client_movement_v2(
  p_business_id uuid,
  p_client_id uuid,
  p_kind public.ledger_kind,
  p_amount numeric,
  p_description text,
  p_effective_at timestamptz default null,
  p_payment_method text default null,
  p_reference text default null,
  p_sale_id uuid default null
)
returns uuid language plpgsql security definer set search_path=public as $$
declare movement_id uuid;
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  if p_amount <= 0 then raise exception 'invalid amount'; end if;
  if not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;
  if p_sale_id is not null and not exists(select 1 from sales where id=p_sale_id and business_id=p_business_id) then raise exception 'invalid sale'; end if;
  insert into client_ledger(business_id,client_id,kind,amount,description,effective_at,payment_method,reference,sale_id,created_by)
  values(p_business_id,p_client_id,p_kind,p_amount,trim(p_description),coalesce(p_effective_at,now()),p_payment_method,p_reference,p_sale_id,auth.uid())
  returning id into movement_id;
  update clients
     set balance=balance+case when p_kind='credit' then p_amount else -p_amount end,updated_at=now()
   where id=p_client_id and business_id=p_business_id;
  return movement_id;
end $$;

create or replace function public.save_generated_document(
  p_business_id uuid,
  p_client_document_id text,
  p_document_type text,
  p_title text,
  p_source_type text default null,
  p_source_id text default null,
  p_period_start date default null,
  p_period_end date default null,
  p_snapshot jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security definer set search_path=public as $$
declare result_row generated_documents%rowtype; number_value text;
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  if length(trim(coalesce(p_client_document_id,'')))<8 then raise exception 'invalid client document id'; end if;
  select * into result_row from generated_documents where business_id=p_business_id and client_document_id=p_client_document_id;
  if found then return jsonb_build_object('id',result_row.id,'documentNumber',result_row.document_number); end if;
  number_value='D'||lpad(public.next_business_sequence(p_business_id,'document')::text,6,'0');
  insert into generated_documents(business_id,client_document_id,document_number,document_type,title,source_type,source_id,period_start,period_end,snapshot,created_by)
  values(p_business_id,p_client_document_id,number_value,trim(p_document_type),trim(p_title),p_source_type,p_source_id,p_period_start,p_period_end,coalesce(p_snapshot,'{}'::jsonb),auth.uid())
  returning * into result_row;
  return jsonb_build_object('id',result_row.id,'documentNumber',result_row.document_number);
end $$;

create or replace function public.register_sale(p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta')
returns uuid language plpgsql security definer set search_path=public as $$
declare
  s_id uuid; item jsonb; p products%rowtype; total_value numeric(14,2):=0;
  qty numeric(14,3); unit_value numeric(14,2); item_discount numeric(14,2);
  member memberships%rowtype; number_value text; customer_name text; sequence_name text; prefix text;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  select id into s_id from sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_client_id is not null and not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;
  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    if qty<=0 or unit_value<0 then raise exception 'invalid item'; end if;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found or (p_kind='Venta' and p.stock<qty) then raise exception 'insufficient stock for %',coalesce(p.name,'product'); end if;
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

insert into public.products(business_id,code,name,category,unit,notes,stock,min_stock,cost,price,wholesale_price,active)
select id,'TEST-000000','Producto test','Tutorial','Unidad','Producto para practicar el flujo del PDV sin afectar los resultados reales.',100,0,0,100,100,true
from public.businesses
on conflict(business_id,code) do update set name=excluded.name,category=excluded.category,unit=excluded.unit,notes=excluded.notes,price=100,wholesale_price=100,active=true,updated_at=now();

revoke all on table public.business_sequences from public,anon,authenticated;
revoke all on function public.next_business_sequence(uuid,text) from public,anon,authenticated;
revoke all on function public.record_client_movement_v2(uuid,uuid,public.ledger_kind,numeric,text,timestamptz,text,text,uuid) from public,anon;
revoke all on function public.save_generated_document(uuid,text,text,text,text,text,date,date,jsonb) from public,anon;
revoke all on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) from public,anon;
grant execute on function public.record_client_movement_v2(uuid,uuid,public.ledger_kind,numeric,text,timestamptz,text,text,uuid) to authenticated;
grant execute on function public.save_generated_document(uuid,text,text,text,text,text,date,date,jsonb) to authenticated;
grant execute on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) to authenticated;
grant select on public.generated_documents to authenticated;
