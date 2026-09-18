-- Impede clientes antigos de registrar vendas sem moeda/cotação atômicas.
revoke execute on function public.register_sale(uuid,uuid,text,jsonb,text,text,text) from authenticated;
