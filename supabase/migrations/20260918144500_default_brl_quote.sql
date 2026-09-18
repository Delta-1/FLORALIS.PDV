-- Padrão inicial ilustrado no PDV: R$ 1 = Bs 2.
-- O administrador pode alterar a cotação a qualquer momento na configuração do PDV.
alter table public.business_settings
  alter column app_config set default
  '{"baseCurrency":"BOB","exchangeRates":{"BOB":1,"BRL":0.5,"USD":0.14}}'::jsonb;
