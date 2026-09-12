-- Índices de suporte para relações e política explícita de negação da tabela interna de sequências.
create index if not exists client_ledger_client_fk_idx on public.client_ledger(client_id);
create index if not exists client_ledger_created_by_idx on public.client_ledger(created_by);
create index if not exists client_ledger_sale_idx on public.client_ledger(sale_id) where sale_id is not null;
create index if not exists generated_documents_created_by_idx on public.generated_documents(created_by);
create index if not exists sale_items_product_idx on public.sale_items(product_id);
create index if not exists sale_items_sale_fk_idx on public.sale_items(sale_id);
create index if not exists sales_client_idx on public.sales(client_id) where client_id is not null;
create index if not exists sales_seller_fk_idx on public.sales(seller_id);
create index if not exists cash_movements_employee_idx on public.cash_movements(employee_id) where employee_id is not null;
create index if not exists cash_movements_sale_idx on public.cash_movements(sale_id) where sale_id is not null;
create index if not exists audit_logs_user_idx on public.audit_logs(user_id) where user_id is not null;

drop policy if exists business_sequences_no_direct_access on public.business_sequences;
create policy business_sequences_no_direct_access on public.business_sequences
for all to authenticated using (false) with check (false);
