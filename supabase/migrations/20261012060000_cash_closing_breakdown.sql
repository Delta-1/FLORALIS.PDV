-- Desglose del cierre de caja por medio de pago y moneda, calculado en el servidor
-- con la sesión completa y guardado en cash_closings.breakdown.
-- Regla del medio (igual en app.js cashMovementMethod): "Venta ... — Medio" -> Medio;
-- "Pago Medio ..." (crediario) -> Medio; resto -> "Otros ingresos".

alter table public.cash_closings add column if not exists breakdown jsonb not null default '[]'::jsonb;

create or replace function public.cash_movement_method(p_description text) returns text
language sql immutable set search_path='' as $$
  select coalesce(
    substring(p_description from '^Venta .* — ([^—]+)$'),
    substring(p_description from '^Pago ([^ ]+)'),
    'Otros ingresos')
$$;

create or replace function public.close_cash_session_v1(p_business_id uuid, p_cash_session_id uuid, p_reason text DEFAULT 'manual'::text)
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
  select coalesce(jsonb_agg(jsonb_build_object('method',method,'currency',currency,'amount',amount) order by method,currency),'[]'::jsonb)
    into breakdown_value
    from (
      select public.cash_movement_method(description) as method,
             case when currency_code='BRL' then 'BRL' else 'BOB' end as currency,
             sum(case when currency_code='BRL' then amount_brl else amount_bob end) as amount
        from public.cash_movements
       where cash_session_id=session_row.id and kind='in'
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
