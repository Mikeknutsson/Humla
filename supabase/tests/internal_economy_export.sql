begin;
do $$
declare rows jsonb;base jsonb;result jsonb;total numeric;
begin
 base:='{"category":"transport","amount":100,"quantity":2,"source_key":"t","receiver_center":"10","source_center":"30","report_basis":"confirmed","bundle":false,"bundle_unresolved":false}';
 rows:=jsonb_build_array(base,
  base||'{"source_key":"tip","category":"tipp_deponi"}',
  base||'{"source_key":"credit","category":"tipp_deponi","amount":-100,"quantity":-2}',
  base||'{"source_key":"mat","category":"material","purchase":{"amount":60,"rate":30,"quantity":2,"status":"receipt_price_list"}}',
  base||'{"source_key":"bundle","amount":160,"bundle":true,"bundle_transport":100,"purchase":{"amount":60,"rate":30,"quantity":2,"status":"average_estimate"}}',
  base||'{"source_key":"missing","category":"material","purchase":{}}',
  base||'{"source_key":"named_tip","category":"unclassified","description":"Tippavgift IFA-Schakt"}',
  base||'{"source_key":"soil","description":"Matjord 0-8"}');
 result:=private.hub_internal_economy_rows_v1(rows);
 if(select count(*)from jsonb_array_elements(result))<>9 then raise exception 'Bundle components missing or duplicated';end if;
 if(select(r->>'amount')::numeric from jsonb_array_elements(result)r where r->>'source_key'='t')<>100 then raise exception 'Transport must stay at full price';end if;
 if(select(r->>'amount')::numeric from jsonb_array_elements(result)r where r->>'source_key'='tip')<>100 then raise exception 'Tipping must stay at full price';end if;
 if(select(r->>'amount')::numeric from jsonb_array_elements(result)r where r->>'source_key'='named_tip')<>100 then raise exception 'Explicit tipping name not classified';end if;
 if(select(r->>'amount')::numeric from jsonb_array_elements(result)r where r->>'source_key'='credit')<>-100 then raise exception 'Credit sign changed';end if;
 if exists(select 1 from jsonb_array_elements(result)r where (r->>'discount_rate')::numeric<>0 or (r->>'discount_amount')::numeric<>0)then raise exception 'No discount permitted';end if;
 if(select(r->>'amount')::numeric from jsonb_array_elements(result)r where r->>'source_key'='mat')<>60 then raise exception 'Material must use self cost without extra discount';end if;
 select sum((r->>'amount')::numeric)into total from jsonb_array_elements(result)r where r->>'source_key'='bundle';
 if total<>160 then raise exception 'Bundled transport lost or discounted';end if;
 if exists(select 1 from jsonb_array_elements(result)r where r->>'source_key'='missing'and r->>'amount'is not null)then raise exception 'Missing material cost must not become zero';end if;
 if not exists(select 1 from jsonb_array_elements(result)r where r->>'source_key'='soil'and(r->>'amount')::numeric=100 and r->>'category'='material'and r->>'price_status'='internal_price_full'and(r->>'estimated')::boolean=false)then raise exception 'Matjord must retain full approved price';end if;
 if has_function_privilege('anon','public.hub_kpi_internal_economy_export_v1(uuid,date,date,integer[])','EXECUTE')then raise exception 'Anonymous export access';end if;
end$$;
select 'PASS material self cost, full transport and tipping, credit, bundle conservation and missing evidence'as result;
rollback;
