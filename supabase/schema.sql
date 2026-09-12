-- FLORALIS PDV — schema inicial para Supabase/PostgreSQL
-- Execute no SQL Editor de um projeto novo. Não use service_role no frontend.
create extension if not exists pgcrypto;

create type public.member_role as enum ('admin','employee');
create type public.ledger_kind as enum ('credit','debit');
create type public.cash_kind as enum ('in','out');

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  legal_name text,
  tax_id text,
  phone text,
  city text,
  currency text not null default 'Bs',
  created_at timestamptz not null default now()
);

create table public.memberships (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.member_role not null default 'employee',
  display_name text not null,
  email text,
  job_title text,
  phone text,
  document text,
  avatar_url text,
  supervisor boolean not null default false,
  permissions jsonb not null default '{"sales":true,"clients":true,"stock":false,"cash":false,"reports":false}'::jsonb,
  must_change_password boolean not null default true,
  active boolean not null default true,
  sales_count integer not null default 0,
  sales_total numeric(14,2) not null default 0,
  average_ticket numeric(14,2) not null default 0,
  goal_progress numeric(5,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_id,user_id)
);
create index memberships_user_idx on public.memberships(user_id,business_id);

create table public.products (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null, ean text, name text not null, category text not null default 'General', unit text not null default 'Unidad', notes text, image_url text,
  stock numeric(14,3) not null default 0, min_stock numeric(14,3) not null default 0,
  cost numeric(14,2) not null default 0, price numeric(14,2) not null default 0, wholesale_price numeric(14,2) not null default 0,
  active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(business_id,code)
);
create index products_business_search_idx on public.products(business_id,name,code);

create table public.clients (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  code text not null, name text not null, customer_type text not null default 'Minorista', phone text, document text, city text, notes text, avatar_url text, birthdate date,
  balance numeric(14,2) not null default 0, purchases integer not null default 0, total_purchased numeric(14,2) not null default 0,
  active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(business_id,code)
);
create index clients_business_search_idx on public.clients(business_id,name,document);

create table public.client_ledger (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  client_id uuid not null references public.clients(id) on delete cascade, kind public.ledger_kind not null,
  amount numeric(14,2) not null check(amount > 0), description text not null, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create index client_ledger_client_idx on public.client_ledger(business_id,client_id,created_at desc);

create table public.sales (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  sale_number text not null, client_sale_id text not null, kind text not null default 'Venta', client_id uuid references public.clients(id), client_name text,
  seller_id uuid not null references auth.users(id), seller_name text not null, payment_method text not null,
  subtotal numeric(14,2) not null, discount numeric(14,2) not null default 0, total numeric(14,2) not null,
  currency_code text not null default 'BOB' check (currency_code in ('BOB','BRL','USD')),
  exchange_rate numeric(18,6) not null default 1 check (exchange_rate > 0),
  display_total numeric(14,2) not null default 0 check (display_total >= 0),
  notes text, status text not null default 'completed', created_at timestamptz not null default now(), unique(business_id,sale_number), unique(business_id,client_sale_id)
);
create index sales_business_date_idx on public.sales(business_id,created_at desc);
create index sales_seller_idx on public.sales(business_id,seller_id,created_at desc);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.sales(id) on delete cascade, product_id uuid not null references public.products(id),
  product_name text not null, quantity numeric(14,3) not null check(quantity > 0), unit_price numeric(14,2) not null, total numeric(14,2) not null
);
create index sale_items_sale_idx on public.sale_items(business_id,sale_id);

create table public.cash_movements (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  kind public.cash_kind not null, description text not null, amount numeric(14,2) not null check(amount > 0),
  employee_id uuid references auth.users(id), employee_name text, sale_id uuid references public.sales(id), created_at timestamptz not null default now()
);
create index cash_business_date_idx on public.cash_movements(business_id,created_at desc);

create table public.business_settings (
  business_id uuid primary key references public.businesses(id) on delete cascade,
  theme jsonb not null default '{"mode":"light","palette":"floralis","accent":"#652276","scale":"medium","font":"inter","shell":"nex","language":"es"}',
  pos_layout jsonb not null default '{"dock":"sidebar","density":"comfortable","theme":"touch","mode":"light","palette":"floralis","borders":"strong","items":["client","wholesale","delivery","notes","payment"]}',
  app_config jsonb not null default '{"baseCurrency":"BOB","exchangeRates":{"BOB":1,"BRL":0.75,"USD":0.14}}'::jsonb,
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null, user_name text not null, user_email text, user_role text,
  module text not null, action text not null, details text, level text not null default 'info',
  terminal_id text, channel text, user_agent text, created_at timestamptz not null default now()
);
create index audit_logs_business_date_idx on public.audit_logs(business_id,created_at desc);
create index audit_logs_user_date_idx on public.audit_logs(business_id,user_id,created_at desc);

create table public.connected_devices (
  id uuid primary key default gen_random_uuid(), business_id uuid not null references public.businesses(id) on delete cascade,
  terminal_id text not null, user_id uuid not null references auth.users(id) on delete cascade,
  user_name text not null, user_email text,
  device_type text not null default 'desktop' check (device_type in ('desktop','mobile','tablet','unknown')),
  platform text not null default 'PC' check (platform in ('PC','Android','iOS','Unknown')),
  browser text, user_agent text, channel text not null default 'ERP' check (channel in ('ERP','PDV')),
  first_seen timestamptz not null default now(), last_seen timestamptz not null default now(),
  last_login timestamptz not null default now(), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (business_id,terminal_id)
);
create index connected_devices_business_seen_idx on public.connected_devices(business_id,last_seen desc);

create or replace function public.is_member(p_business_id uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from memberships where business_id=p_business_id and user_id=(select auth.uid()) and active);
$$;
create or replace function public.is_admin(p_business_id uuid) returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from memberships where business_id=p_business_id and user_id=(select auth.uid()) and role='admin' and active);
$$;

create or replace function public.complete_password_change(p_business_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  update memberships
     set must_change_password=false,updated_at=now()
   where business_id=p_business_id and user_id=auth.uid() and active;
  return found;
end $$;

alter table public.businesses enable row level security; alter table public.memberships enable row level security;
alter table public.products enable row level security; alter table public.clients enable row level security;
alter table public.client_ledger enable row level security; alter table public.sales enable row level security;
alter table public.sale_items enable row level security; alter table public.cash_movements enable row level security;
alter table public.business_settings enable row level security;
alter table public.audit_logs enable row level security;
alter table public.connected_devices enable row level security;

create policy businesses_select on public.businesses for select to authenticated using (public.is_member(id));
create policy businesses_admin_update on public.businesses for update to authenticated using (public.is_admin(id)) with check (public.is_admin(id));
create policy memberships_select on public.memberships for select to authenticated using (public.is_member(business_id));
create policy memberships_admin_write on public.memberships for all to authenticated using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy products_select on public.products for select to authenticated using (public.is_member(business_id));
create policy products_admin_write on public.products for all to authenticated using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy clients_select on public.clients for select to authenticated using (public.is_member(business_id));
create policy clients_insert on public.clients for insert to authenticated with check (public.is_member(business_id));
create policy clients_admin_update on public.clients for update to authenticated using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy ledger_select on public.client_ledger for select to authenticated using (public.is_member(business_id));
create policy sales_select on public.sales for select to authenticated using (public.is_member(business_id));
create policy sale_items_select on public.sale_items for select to authenticated using (public.is_member(business_id));
create policy cash_select on public.cash_movements for select to authenticated using (public.is_member(business_id));
create policy cash_insert on public.cash_movements for insert to authenticated with check (public.is_member(business_id));
create policy settings_select on public.business_settings for select to authenticated using (public.is_member(business_id));
create policy settings_admin_write on public.business_settings for all to authenticated using (public.is_admin(business_id)) with check (public.is_admin(business_id));
create policy connected_devices_admin_select on public.connected_devices for select to authenticated using (public.is_admin(business_id));
create policy audit_logs_admin_select on public.audit_logs for select to authenticated using (public.is_admin(business_id));

create or replace function public.record_client_movement(p_business_id uuid,p_client_id uuid,p_kind public.ledger_kind,p_amount numeric,p_description text)
returns uuid language plpgsql security definer set search_path=public as $$
declare movement_id uuid;
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  if p_amount <= 0 then raise exception 'invalid amount'; end if;
  if not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;
  insert into client_ledger(business_id,client_id,kind,amount,description,created_by) values(p_business_id,p_client_id,p_kind,p_amount,p_description,auth.uid()) returning id into movement_id;
  update clients set balance=balance+case when p_kind='credit' then p_amount else -p_amount end,updated_at=now() where id=p_client_id and business_id=p_business_id;
  return movement_id;
end $$;

create or replace function public.register_sale(p_business_id uuid,p_client_id uuid,p_payment_method text,p_items jsonb,p_notes text default null,p_client_sale_id text default null,p_kind text default 'Venta')
returns uuid language plpgsql security definer set search_path=public as $$
declare s_id uuid; item jsonb; p products%rowtype; total_value numeric(14,2):=0; qty numeric(14,3); unit_value numeric(14,2); member memberships%rowtype; number_value text; customer_name text;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if p_client_sale_id is null or length(trim(p_client_sale_id))<8 then raise exception 'invalid client sale id'; end if;
  if p_kind not in ('Venta','Pedido','Presupuesto') then raise exception 'invalid sale kind'; end if;
  select id into s_id from sales where business_id=p_business_id and client_sale_id=p_client_sale_id;
  if found then return s_id; end if;
  if jsonb_array_length(p_items)=0 then raise exception 'empty sale'; end if;
  if p_client_id is not null and not exists(select 1 from clients where id=p_client_id and business_id=p_business_id) then raise exception 'invalid client'; end if;
  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if not found or (p_kind='Venta' and p.stock<qty) then raise exception 'insufficient stock for %',coalesce(p.name,'product'); end if;
    total_value=total_value+(qty*unit_value);
  end loop;
  number_value=case p_kind when 'Pedido' then 'P' when 'Presupuesto' then 'O' else 'V' end||to_char(now(),'YYMMDDHH24MISSMS');
  select name into customer_name from clients where id=p_client_id and business_id=p_business_id;
  insert into sales(business_id,sale_number,client_sale_id,kind,client_id,client_name,seller_id,seller_name,payment_method,subtotal,total,notes) values(p_business_id,number_value,p_client_sale_id,p_kind,p_client_id,coalesce(customer_name,'Consumidor final'),auth.uid(),member.display_name,p_payment_method,total_value,total_value,p_notes) returning id into s_id;
  for item in select * from jsonb_array_elements(p_items) loop
    qty=(item->>'quantity')::numeric; unit_value=(item->>'unit_price')::numeric;
    select * into p from products where id=(item->>'product_id')::uuid and business_id=p_business_id for update;
    if p_kind='Venta' then update products set stock=stock-qty,updated_at=now() where id=p.id; end if;
    insert into sale_items(business_id,sale_id,product_id,product_name,quantity,unit_price,total) values(p_business_id,s_id,p.id,p.name,qty,unit_value,qty*unit_value);
  end loop;
  if p_kind='Venta' and p_client_id is not null then
    update clients set purchases=purchases+1,total_purchased=total_purchased+total_value,updated_at=now() where id=p_client_id and business_id=p_business_id;
    if p_payment_method='Cuenta cliente' then perform record_client_movement(p_business_id,p_client_id,'debit',total_value,'Venta '||number_value); end if;
  end if;
  if p_kind='Venta' then
    update memberships set sales_count=sales_count+1,sales_total=sales_total+total_value,average_ticket=(sales_total+total_value)/(sales_count+1) where business_id=p_business_id and user_id=auth.uid();
    if p_payment_method<>'Cuenta cliente' then insert into cash_movements(business_id,kind,description,amount,employee_id,employee_name,sale_id) values(p_business_id,'in','Venta '||number_value||' — '||p_payment_method,total_value,auth.uid(),member.display_name,s_id); end if;
  end if;
  return s_id;
end $$;

revoke all on function public.record_client_movement(uuid,uuid,public.ledger_kind,numeric,text) from public;
grant execute on function public.record_client_movement(uuid,uuid,public.ledger_kind,numeric,text) to authenticated;
revoke all on function public.complete_password_change(uuid) from public;
grant execute on function public.complete_password_change(uuid) to authenticated;
create or replace function public.record_audit_event(p_business_id uuid,p_module text,p_action text,p_details text default null,p_level text default 'info',p_terminal_id text default null,p_channel text default null,p_user_agent text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare log_id uuid; member memberships%rowtype;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if length(trim(coalesce(p_action,'')))=0 then raise exception 'invalid action'; end if;
  insert into audit_logs(business_id,user_id,user_name,user_email,user_role,module,action,details,level,terminal_id,channel,user_agent)
  values(p_business_id,auth.uid(),member.display_name,member.email,member.role::text,coalesce(nullif(trim(p_module),''),'Sistema'),trim(p_action),p_details,coalesce(nullif(trim(p_level),''),'info'),p_terminal_id,p_channel,p_user_agent)
  returning id into log_id;
  return log_id;
end $$;

revoke all on function public.record_audit_event(uuid,text,text,text,text,text,text,text) from public;
grant execute on function public.record_audit_event(uuid,text,text,text,text,text,text,text) to authenticated;
create or replace function public.register_connected_device(p_business_id uuid,p_terminal_id text,p_device_type text,p_platform text,p_browser text default null,p_user_agent text default null,p_channel text default 'ERP',p_is_login boolean default false)
returns public.connected_devices language plpgsql security definer set search_path=public as $$
declare member memberships%rowtype; registered connected_devices%rowtype;
begin
  select * into member from memberships where business_id=p_business_id and user_id=auth.uid() and active;
  if not found then raise exception 'access denied'; end if;
  if nullif(trim(p_terminal_id),'') is null then raise exception 'invalid terminal'; end if;
  insert into connected_devices(business_id,terminal_id,user_id,user_name,user_email,device_type,platform,browser,user_agent,channel,last_seen,last_login,updated_at)
  values(p_business_id,left(trim(p_terminal_id),80),auth.uid(),member.display_name,member.email,
    case when p_device_type in ('desktop','mobile','tablet','unknown') then p_device_type else 'unknown' end,
    case when p_platform in ('PC','Android','iOS','Unknown') then p_platform else 'Unknown' end,
    nullif(left(trim(coalesce(p_browser,'')),80),''),nullif(left(coalesce(p_user_agent,''),500),''),
    case when p_channel='PDV' then 'PDV' else 'ERP' end,now(),now(),now())
  on conflict(business_id,terminal_id) do update set user_id=excluded.user_id,user_name=excluded.user_name,user_email=excluded.user_email,
    device_type=excluded.device_type,platform=excluded.platform,browser=excluded.browser,user_agent=excluded.user_agent,channel=excluded.channel,
    last_seen=now(),last_login=case when p_is_login then now() else connected_devices.last_login end,updated_at=now()
  returning * into registered;
  return registered;
end $$;
revoke all on function public.register_connected_device(uuid,text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.register_connected_device(uuid,text,text,text,text,text,text,boolean) to authenticated;
revoke all on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) from public;
grant execute on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) to authenticated;

create or replace function public.set_sale_currency(p_business_id uuid,p_client_sale_id text,p_currency_code text,p_exchange_rate numeric,p_display_total numeric)
returns boolean language plpgsql security definer set search_path=public as $$
begin
  if not public.is_member(p_business_id) then raise exception 'access denied'; end if;
  if p_currency_code not in ('BOB','BRL','USD') or p_exchange_rate<=0 or p_display_total<0 then raise exception 'invalid currency data'; end if;
  update sales set currency_code=p_currency_code,exchange_rate=p_exchange_rate,display_total=p_display_total
   where business_id=p_business_id and client_sale_id=p_client_sale_id and seller_id=auth.uid();
  return found;
end $$;
revoke all on function public.set_sale_currency(uuid,text,text,numeric,numeric) from public,anon;
grant execute on function public.set_sale_currency(uuid,text,text,numeric,numeric) to authenticated;

grant usage on schema public to authenticated;
grant select on public.businesses,public.memberships,public.products,public.clients,public.client_ledger,public.sales,public.sale_items,public.cash_movements,public.business_settings,public.audit_logs,public.connected_devices to authenticated;
grant insert on public.clients,public.cash_movements to authenticated;
grant insert,update,delete on public.products,public.memberships,public.business_settings to authenticated;
grant update on public.businesses,public.clients to authenticated;
