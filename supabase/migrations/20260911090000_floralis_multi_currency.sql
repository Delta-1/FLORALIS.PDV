alter table public.sales
  add column if not exists currency_code text not null default 'BOB',
  add column if not exists exchange_rate numeric(18,6) not null default 1,
  add column if not exists display_total numeric(14,2) not null default 0;

alter table public.sales drop constraint if exists sales_currency_code_check;
alter table public.sales add constraint sales_currency_code_check check (currency_code in ('BOB','BRL','USD'));
alter table public.sales drop constraint if exists sales_exchange_rate_check;
alter table public.sales add constraint sales_exchange_rate_check check (exchange_rate > 0);
alter table public.sales drop constraint if exists sales_display_total_check;
alter table public.sales add constraint sales_display_total_check check (display_total >= 0);

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
