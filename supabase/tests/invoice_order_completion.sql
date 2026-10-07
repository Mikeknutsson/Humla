-- Run as an authenticated KPI reader (request.jwt.claim.sub), on a prepared tenant.
-- All fixtures roll back. Tests exercise the public Hub RPC, not a copied formula.
begin;
do $$
declare tenant uuid; generation uuid; tag text:='invoice-test-'||gen_random_uuid(); r jsonb; x jsonb;
begin
 select tenant_id into tenant from public.hub_tenant_members where user_id=auth.uid() and status='active' and public.hub_has_permission(tenant_id,'kpi.read') limit 1;
 if tenant is null then raise exception 'Authenticated prepared KPI tenant required';end if;
 generation:=private.hub_kpi_active_report_generation_v1(tenant);
 insert into private.hub_kpi_prepared_display_facts(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_name,business_group,source,cost_center,original)
 select generation,tenant,2026,tag||'-'||n,article::date,'revenue',100,'transport',tag,'TEST','Test','Test','Workify',tag,
 jsonb_build_object('_humla_invoice',jsonb_build_object('order_number',tag||ord,'article_date',article,'invoice_date',invoice,'invoice_text',invoice,'customer_name',customer,'end_text',ending,'end_date',end_date))
 from (values
 (1,'A','2026-09-01','2026-09-08','2026-09-05','2026-09-05','Extern'),
 (2,'A','2026-09-05','2026-09-08','2026-09-05','2026-09-05','Extern'),
 (3,'A','2026-09-05','2026-09-08','2026-09-05','2026-09-05','Extern'), -- duplicate article line
 (4,'B','2026-09-30','2026-10-05','2026-10-02','2026-10-02','Extern'),
 (5,'B','2026-10-02','2026-10-05','2026-10-02','2026-10-02','Extern'), -- context outside selection
 (6,'C','2026-09-01','2026-09-08',null,null,'Elleholms Tomatodling AB'),
 (7,'C','2026-09-04','2026-09-08',null,null,'Elleholms Tomatodling AB'), -- fallback, still external
 (8,'D','2026-09-05','2026-09-10','2026-09-05','2026-09-05','elleholms maskin (STENA)'),
 (9,'E','2026-09-05','2026-09-05','2026-09-05','2026-09-05','Extern'), -- zero
 (10,'F','2026-09-05','2026-09-04','2026-09-05','2026-09-05','Extern'), -- negative
 (11,'G','2026-09-05','2026-09-08','2026-09-05','2026-09-05','Extern'),
 (12,'G','2026-09-05','2026-09-09','2026-09-05','2026-09-05','Extern'), -- invoice conflict
 (13,'H','2026-09-05','2026-09-08','bad-date',null,'Extern'), -- invalid end, no silent fallback
 (14,'I','2026-09-05',null,'2026-09-05','2026-09-05','Extern'), -- uninvoiced
 (15,'J','2026-10-05','2026-10-08','2026-10-05','2026-10-05','Extern'), -- excluded month
 (16,'K','2026-09-06','2026-09-08','2026-09-05','2026-09-05','Extern') -- end before last article
 ) v(n,ord,article,invoice,ending,end_date,customer);
 r:=public.hub_kpi_invoice_lead_time_v1(tenant,2026,array[9],jsonb_build_object('cost_center',tag),0);
 assert (r->>'average_days')::numeric=3.33 and (r->>'averaged_orders')::int=3,'External order mean';
 assert (r->>'internal_average_days')::numeric=5 and (r->>'internal_averaged_orders')::int=1,'Separate internal mean';
 assert (r->>'orders')::int=5 and (r->>'zero_orders')::int=1,'One row per order, zero excluded';
 assert (r->>'invalid_orders')::int=4 and (r->>'uninvoiced_orders')::int=1,'Invalid and uninvoiced excluded';
 assert (r->>'fallback_orders')::int=1,'Last article fallback';
 select value into x from jsonb_array_elements(r->'rows') where value->>'order_number'=tag||'B';
 assert x->>'completion_date'='2026-10-02' and (x->>'days_to_invoice')::int=3,'Cross-month completion context';
 r:=public.hub_kpi_invoice_lead_time_v1(tenant,2026,array[9],jsonb_build_object('cost_center',tag,'invoice_customer','internal'),0);
 assert (r->>'row_count')::int=1 and jsonb_array_length(r->'rows')=1 and (r#>>'{rows,0,is_internal}')::boolean,'Internal drilldown';
 r:=public.hub_kpi_invoice_lead_time_v1(tenant,2026,array[9],jsonb_build_object('cost_center',tag,'date_to','2026-09-01'),0);
 assert (r->>'average_days')::numeric=3.5 and (r->>'orders')::int=2,'Filters retain full order completion';
 raise notice 'Invoice order completion regression checks passed';
end $$;
rollback;
