alter table public.business_settings
  alter column theme set default '{"mode":"light","palette":"floralis","accent":"#652276","scale":"medium","font":"inter","shell":"nex","language":"es"}'::jsonb,
  alter column pos_layout set default '{"dock":"sidebar","density":"comfortable","theme":"touch","mode":"light","palette":"floralis","borders":"strong","items":["client","wholesale","delivery","notes","payment"]}'::jsonb,
  alter column app_config set default '{"baseCurrency":"BOB","exchangeRates":{"BOB":1,"BRL":0.75,"USD":0.14}}'::jsonb;

update public.business_settings
set
  theme=coalesce(theme,'{}'::jsonb)||jsonb_build_object('palette','floralis','accent','#652276'),
  pos_layout=coalesce(pos_layout,'{}'::jsonb)||jsonb_build_object('palette','floralis'),
  app_config=coalesce(app_config,'{}'::jsonb)||jsonb_build_object(
    'baseCurrency',coalesce(app_config->>'baseCurrency','BOB'),
    'exchangeRates',coalesce(app_config->'exchangeRates','{"BOB":1,"BRL":0.75,"USD":0.14}'::jsonb)
  ),
  updated_at=now();
