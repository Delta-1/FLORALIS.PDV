-- All fixtures are temporary and rolled back.
begin;
do $$
declare b uuid; u uuid; p uuid; pfree uuid; c uuid; s uuid; r uuid; drawer uuid; n numeric; closing public.cash_closings%rowtype; denied boolean;
begin
 select user_id into u from public.memberships where role='admin' and active limit 1;
 perform set_config('request.jwt.claim.sub',u::text,true);
 insert into public.businesses(name) values('Temporary PR integration check') returning id into b;
 insert into public.memberships(business_id,user_id,role,display_name) values(b,u,'admin','Verification');
 insert into public.business_settings(business_id) values(b);
 insert into public.products(business_id,code,name,stock,price,price_bob,price_brl) values(b,'QA-NATIVE','Verification',10,100,100,50) returning id into p;
 insert into public.products(business_id,code,name,stock,price,price_bob,price_brl,open_price,track_stock) values(b,'QA-FREE','Verification untracked',0,0,0,0,true,false) returning id into pfree;
 insert into public.clients(business_id,code,name) values(b,'QA','Verification') returning id into c;
 select id into drawer from public.open_cash_session_v1(b,'qa-native',10,20);
 s:=public.register_sale_v5(b,c,'Efectivo',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2,'unit_price',50)),'BRL',120,null,'qa-native-first','Venta','qa-native');
 assert (select total=100 and payment_amount=100 and change_amount=20 and amount_bob=0 and amount_brl=100 from public.sales where id=s),'BRL total/cash/change';
 assert (select stock=8 from public.products where id=p),'Stock decrement';
 perform public.cancel_sale_v1(b,s,'QA native cancellation','qa-native');
 perform public.cancel_sale_v1(b,s,'QA native cancellation retry','qa-native');
 assert (select stock=10 from public.products where id=p),'Cancellation restores stock once';
 assert (select total_purchased_brl=0 and total_purchased_bob=0 from public.clients where id=c),'Cancellation restores correct customer currency';
 s:=public.register_sale_v5(b,c,'Cuenta cliente',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',50)),'BRL',0,null,'qa-native-account','Venta','qa-native');
 assert (select balance_brl=-50 and balance_bob=0 from public.clients where id=c),'BRL account debt';
 perform public.cancel_sale_v1(b,s,'QA account cancellation','qa-native');
 assert (select balance_brl=0 and balance_bob=0 from public.clients where id=c),'BRL debt cancellation';
 s:=public.register_sale_v5(b,null,'Efectivo',jsonb_build_array(jsonb_build_object('product_id',pfree,'quantity',1,'unit_price',30,'description','Custom arrangement')),'BOB',30,null,'qa-native-open-price','Venta','qa-native');
 update public.products set track_stock=true,open_price=false where id=pfree;
 perform public.cancel_sale_v1(b,s,'QA free product cancellation','qa-native');
 assert (select stock=0 from public.products where id=pfree),'Snapshot prevents phantom stock after tracking changed';
 s:=public.register_sale_v5(b,c,'Efectivo',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',50)),'BRL',50,null,'qa-native-to-replace','Venta','qa-native');
 r:=public.replace_sale_v1(b,s,'QA BRL correction','qa-native',jsonb_build_object('currency','BRL','paymentCurrency','BRL','payment','Efectivo','clientId',c,'clientSaleId','qa-native-replacement','paymentAmount',150,'receivedAmount',150,'items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',3,'unit_price',50))));
 assert (select total=150 and currency_code='BRL' from public.sales where id=r),'Replacement preserves BRL prices';
 assert (select stock=7 from public.products where id=p),'Replacement stock';
 assert (select total_purchased_brl=150 and total_purchased_bob=0 from public.clients where id=c),'Replacement client totals';
 begin
  perform public.register_sale_v5(b,null,'PIX',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',100)),'BOB',100,null,'qa-native-invalid-pix','Venta','qa-native');
  raise exception 'Expected rejection';
 exception when others then if sqlerrm='Expected rejection' then raise; end if; end;
 begin
  perform public.register_sale_v5(b,null,'Efectivo',jsonb_build_array(jsonb_build_object('product_id',p,'quantity','NaN','unit_price',100)),'BOB',100,null,'qa-native-invalid-nan','Venta','qa-native');
  raise exception 'Expected rejection';
 exception when others then if sqlerrm='Expected rejection' then raise; end if; end;
 -- A noncash payment must never affect expected cash notes in the drawer.
 s:=public.register_sale_v5(b,null,'Tarjeta',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',50)),'BRL',50,null,'qa-native-card','Venta','qa-native');
 perform public.cancel_sale_v1(b,s,'QA card cancellation','qa-native');
 closing:=public.close_cash_session_v1(b,drawer,'manual');
 assert closing.expected_bob=10 and closing.expected_brl=170,'Closing aggregates full signed cash movements';
 assert exists(select 1 from jsonb_array_elements(closing.breakdown) row where row->>'method'='Tarjeta' and (row->>'amount')::numeric=50 and (row->>'outflow')::numeric=50),'Closing preserves card outflow separately';
 assert not has_function_privilege('anon','public.register_sale_v5(uuid,uuid,text,jsonb,text,numeric,text,text,text,text)','execute'),'Anon denied';
 update public.memberships set role='employee' where business_id=b and user_id=u; denied:=false;
 begin perform public.cancel_sale_v1(b,r,'QA employee denied','qa-native'); exception when others then denied:=true; end;
 assert denied,'Employee cancellation denied';
end $$;

rollback;
