-- All fixtures and effects roll back; no real customer sale is changed.
begin;
do $$
declare b uuid; u uuid; p uuid; c uuid; sid uuid; replacement uuid; n numeric; payload jsonb; denied boolean:=false;
begin
 select user_id into u from public.memberships where role='admin' and active limit 1;
 if u is null then raise exception 'Test requires an existing user'; end if;
 perform set_config('request.jwt.claim.sub',u::text,true);
 insert into public.businesses(name) values('Temporary sale-management verification') returning id into b;
 insert into public.memberships(business_id,user_id,role,display_name) values(b,u,'admin','Verification');
 insert into public.business_settings(business_id) values(b);
 insert into public.products(business_id,code,name,stock,price,cost,price_bob,price_brl) values(b,'QA','Verification',10,100,0,100,50) returning id into p;
 insert into public.clients(business_id,code,name) values(b,'QA','Verification') returning id into c;
 insert into public.cash_sessions(business_id,terminal_id,opened_by,opened_by_name) values(b,'qa-sales',u,'Verification');
 payload:=jsonb_build_object('clientSaleId','qa-first-sale','clientId',c,'payment','Efectivo','paymentCurrency','BOB','paymentAmount',200,'receivedAmount',200,'items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2,'unit_price',100)));
 sid:=public.register_sale_v4(b,c,'Efectivo',payload->'items','BOB',200,200,null,'qa-first-sale','Venta','qa-sales');
 perform public.cancel_sale_v1(b,sid,'QA cancellation','qa-sales');
 perform public.cancel_sale_v1(b,sid,'QA repeated cancellation','qa-sales');
 select stock into n from public.products where id=p;assert n=10,'Cancel must restore stock once';
 select sum(case when kind='in' then amount_bob else -amount_bob end) into n from public.cash_movements where business_id=b;assert n=0,'Cash must reverse once';
 select purchases into n from public.clients where id=c;assert n=0,'Customer counter must reverse';
 sid:=public.register_sale_v4(b,c,'PIX',payload->'items','BRL',50,50,null,'qa-brl-sale','Venta','qa-sales');
 payload:=payload||jsonb_build_object('clientSaleId','qa-replacement','payment','QR','paymentCurrency','BRL','paymentAmount',75,'receivedAmount',75,'items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',3,'unit_price',100)));
 replacement:=public.replace_sale_v1(b,sid,'QA correction','qa-sales',payload);
 assert replacement=public.replace_sale_v1(b,sid,'QA retry','qa-sales',payload),'Correction retry must be idempotent';
 select stock into n from public.products where id=p;assert n=7,'Edit must restore old quantities and subtract new';
 select sum(case when kind='in' then amount_brl else -amount_brl end) into n from public.cash_movements where business_id=b;assert n=75,'BRL payment must stay separate';
 select count(*) into n from public.sales where business_id=b and status='completed';assert n=1,'Only corrected sale active';
 begin
  perform public.replace_sale_v1(b,replacement,'QA invalid correction','qa-sales',payload||jsonb_build_object('clientSaleId','qa-invalid','items',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',999,'unit_price',100))));
  raise exception 'Expected insufficient stock';
 exception when others then
  if sqlerrm='Expected insufficient stock' then raise; end if;
 end;
 assert (select status='completed' from public.sales where id=replacement),'Failed edit must leave original active';
 select stock into n from public.products where id=p;assert n=7,'Failed edit must roll back stock';
 sid:=public.register_sale_v4(b,c,'Cuenta cliente',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',100)),'BOB',0,0,null,'qa-account-sale','Venta','qa-sales');
 perform public.cancel_sale_v1(b,sid,'QA account reversal','qa-sales');
 select balance_bob into n from public.clients where id=c;assert n=0,'Account debt must reverse';
 sid:=public.register_sale_v4(b,null,'Efectivo',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit_price',100)),'BOB',100,100,null,'qa-order-sale','Pedido','qa-sales');
 perform public.cancel_sale_v1(b,sid,'QA order cancellation','qa-sales');
 select stock into n from public.products where id=p;assert n=7,'Order cancellation must not change stock';
 update public.memberships set role='employee' where business_id=b and user_id=u;
 begin perform public.cancel_sale_v1(b,replacement,'QA denied','qa-sales');exception when others then denied:=true;end;
 assert denied,'Employee must not cancel';
 update public.memberships set role='admin' where business_id=b and user_id=u;
 perform set_config('request.jwt.claim.sub','',true);denied:=false;
 begin perform public.cancel_sale_v1(b,replacement,'QA anonymous','qa-sales');exception when others then denied:=true;end;
 assert denied,'Anonymous must not cancel';
end $$;
rollback;
