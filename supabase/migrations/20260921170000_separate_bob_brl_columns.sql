alter table public.sales
  add column if not exists amount_bob numeric(14,2) not null default 0,
  add column if not exists amount_brl numeric(14,2) not null default 0;

alter table public.cash_movements
  add column if not exists amount_bob numeric(14,2) not null default 0,
  add column if not exists amount_brl numeric(14,2) not null default 0;

update public.sales
set amount_bob = case when currency_code = 'BOB' then display_total else 0 end,
    amount_brl = case when currency_code = 'BRL' then display_total else 0 end;

update public.cash_movements
set amount_bob = case when currency_code = 'BOB' then display_amount else 0 end,
    amount_brl = case when currency_code = 'BRL' then display_amount else 0 end;

alter table public.sales
  drop constraint if exists sales_amount_bob_nonnegative,
  drop constraint if exists sales_amount_brl_nonnegative,
  drop constraint if exists sales_single_report_currency,
  add constraint sales_amount_bob_nonnegative check (amount_bob >= 0),
  add constraint sales_amount_brl_nonnegative check (amount_brl >= 0),
  add constraint sales_single_report_currency check (not (amount_bob > 0 and amount_brl > 0));

alter table public.cash_movements
  drop constraint if exists cash_movements_amount_bob_nonnegative,
  drop constraint if exists cash_movements_amount_brl_nonnegative,
  drop constraint if exists cash_movements_single_report_currency,
  add constraint cash_movements_amount_bob_nonnegative check (amount_bob >= 0),
  add constraint cash_movements_amount_brl_nonnegative check (amount_brl >= 0),
  add constraint cash_movements_single_report_currency check (not (amount_bob > 0 and amount_brl > 0));

create or replace function public.sync_sale_report_currency_columns()
returns trigger language plpgsql set search_path = public as $$
begin
  new.amount_bob := case when new.currency_code = 'BOB' then new.display_total else 0 end;
  new.amount_brl := case when new.currency_code = 'BRL' then new.display_total else 0 end;
  return new;
end $$;

drop trigger if exists sync_sale_report_currency_columns_trigger on public.sales;
create trigger sync_sale_report_currency_columns_trigger
before insert or update of currency_code, display_total on public.sales
for each row execute function public.sync_sale_report_currency_columns();

create or replace function public.sync_cash_report_currency_columns()
returns trigger language plpgsql set search_path = public as $$
begin
  new.amount_bob := case when new.currency_code = 'BOB' then new.display_amount else 0 end;
  new.amount_brl := case when new.currency_code = 'BRL' then new.display_amount else 0 end;
  return new;
end $$;

drop trigger if exists sync_cash_report_currency_columns_trigger on public.cash_movements;
create trigger sync_cash_report_currency_columns_trigger
before insert or update of currency_code, display_amount on public.cash_movements
for each row execute function public.sync_cash_report_currency_columns();

revoke all on function public.sync_sale_report_currency_columns() from public, anon, authenticated;
revoke all on function public.sync_cash_report_currency_columns() from public, anon, authenticated;
