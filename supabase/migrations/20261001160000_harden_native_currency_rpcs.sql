-- Índices recomendados pelo advisor e remoção dos RPCs legados com conversão.

create index if not exists cash_sessions_opened_by_idx on public.cash_sessions(opened_by);
create index if not exists cash_sessions_closed_by_idx on public.cash_sessions(closed_by) where closed_by is not null;
create index if not exists cash_closings_closed_by_idx on public.cash_closings(closed_by);

-- As versões antigas aceitavam taxa de câmbio. O aplicativo 1.2 utiliza somente as versões nativas.
revoke all on function public.register_sale_v2(uuid,uuid,text,jsonb,text,numeric,numeric,text,text,text) from authenticated;
revoke all on function public.record_client_movement_v2(uuid,uuid,public.ledger_kind,numeric,text,timestamptz,text,text,uuid) from authenticated;

