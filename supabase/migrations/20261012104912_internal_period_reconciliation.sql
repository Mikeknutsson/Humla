-- Reconcile the complete internal-period basis without changing booking/export eligibility.
create or replace function private.hub_internal_center_summary_engine_v2(p_rows jsonb)
returns jsonb language plpgsql stable set search_path='' set statement_timeout='45s' set work_mem='64MB' set jit='off'
as $function$
declare result jsonb;
begin
 with raw as materialized(
  select p,p->>'source_key' source_key,
   case when p->>'amount' is not null and p->>'amount' not in ('NaN','Infinity','-Infinity') then (p->>'amount')::numeric end amount,
   jsonb_build_array(p->'occurred_on',p->'order',p->'littra',p->'project',p->'vehicle',p->'source_center',p->'receiver_center',p->'category',p->'amount',p->'unit',p->'article',p->'description',p->'comment') signature
  from jsonb_array_elements(p_rows) p
 ), grouped as materialized(
  select source_key,count(*) copies,count(distinct signature) signatures,count(distinct p->'quantity') filter(where p->'quantity'<>'null'::jsonb) quantities,
   sum(amount) raw_amount,(array_agg(p order by (p->'quantity'<>'null'::jsonb) desc,(p->>'invoiced')::boolean desc,p->>'row_id'))[1] p,
   jsonb_agg(p order by p->>'row_id') variants
  from raw group by source_key
 ), unique_rows as materialized(
  select p||jsonb_build_object('report_copies',copies,'report_basis',case when (p->>'ready')::boolean and p->>'status' in ('new','exported','posted') then 'confirmed' else 'preliminary' end) p,
   (case when p->>'amount' is not null and p->>'amount' not in ('NaN','Infinity','-Infinity') then (p->>'amount')::numeric end) amount,
   raw_amount,copies
  from grouped where source_key is not null and signatures=1 and quantities<=1
 ), conflicts as materialized(select * from grouped where source_key is null or signatures<>1 or quantities>1),
 transfers as(
  select c.code,c.name,coalesce(sum(u.amount),0) amount,
   coalesce(sum(u.amount)filter(where u.p->>'report_basis'='confirmed'),0) confirmed,
   coalesce(jsonb_agg(u.p order by u.p->>'occurred_on',u.p->>'order',u.p->>'source_key')filter(where u.p is not null),'[]') rows
  from (values('30','Transport'),('20','Sortergården')) c(code,name)
  left join unique_rows u on u.p->>'receiver_center'='10' and u.p->>'source_center'=c.code and u.amount is not null
  group by c.code,c.name
 ), unassigned as materialized(select * from unique_rows where p->>'receiver_center'='10' and nullif(p->>'source_center','') is null),
 other as materialized(select * from unique_rows where not(coalesce(p->>'receiver_center','')='10' and (coalesce(p->>'source_center','') in ('20','30') or nullif(p->>'source_center','') is null))),
 totals as(select coalesce(sum(amount),0) amount,coalesce(sum(confirmed),0) confirmed from transfers),
 reconciliation as(
  select coalesce((select sum(amount) from raw),0) source_amount,
   coalesce((select sum(raw_amount-amount) from unique_rows where amount is not null),0) duplicate_amount,
   coalesce((select sum(raw_amount) from conflicts),0) conflict_amount,
   coalesce((select sum(amount) from unassigned),0) unassigned_amount,
   coalesce((select sum(amount) from other),0) other_amount
 )
 select jsonb_build_object(
  'transfers',(select jsonb_agg(jsonb_build_object('fromCenter','10','fromName','Entreprenad','toCenter',code,'toName',name,'amount',amount,'confirmedAmount',confirmed,'preliminaryAmount',amount-confirmed,'rows',rows) order by code desc) from transfers),
  'total',t.amount,'confirmedTotal',t.confirmed,'preliminaryTotal',t.amount-t.confirmed,
  'unassignedRows',(select count(*)from unassigned),'unassignedAmount',r.unassigned_amount,'unassignedItems',coalesce((select jsonb_agg(p order by p->>'source_key') from unassigned),'[]'),
  'otherRows',(select count(*)from other),'otherAmount',r.other_amount,'otherItems',coalesce((select jsonb_agg(p order by p->>'source_key')from other),'[]'),
  'duplicateRowsRemoved',(select coalesce(sum(copies-1),0) from unique_rows),'duplicateAmountRemoved',r.duplicate_amount,
  'conflictCount',(select count(*)from conflicts),'conflictRawAmount',r.conflict_amount,'conflicts',coalesce((select jsonb_agg(jsonb_build_object('sourceKey',source_key,'rawAmount',raw_amount,'variants',variants)order by source_key)from conflicts),'[]'),
  'sourceRows',(select count(*)from raw),'sourceAmount',r.source_amount,
  'invalidAmountRows',(select count(*)from raw where amount is null),
  'reconciles',r.source_amount=t.amount+r.unassigned_amount+r.other_amount+r.duplicate_amount+r.conflict_amount
 ) into result from totals t cross join reconciliation r;
 return result;
end $function$;
revoke execute on function private.hub_internal_center_summary_engine_v2(jsonb) from public,anon;
grant execute on function private.hub_internal_center_summary_engine_v2(jsonb) to authenticated,service_role;
create or replace function public.hub_kpi_internal_center_summary_v2(p_tenant_id uuid,p_from date,p_to date,p_months integer[] default null)
returns jsonb language plpgsql stable set search_path='' set statement_timeout='45s' set work_mem='64MB' set jit='off'
as $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 return private.hub_internal_center_summary_engine_v2(public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months)->'rows');
end $function$;
revoke execute on function public.hub_kpi_internal_center_summary_v2(uuid,date,date,integer[]) from public,anon;
grant execute on function public.hub_kpi_internal_center_summary_v2(uuid,date,date,integer[]) to authenticated,service_role;
notify pgrst,'reload schema';
