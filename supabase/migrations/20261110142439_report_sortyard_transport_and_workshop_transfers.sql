CREATE OR REPLACE FUNCTION private.hub_internal_center_summary_engine_v2(p_rows jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET work_mem TO '64MB'
 SET jit TO 'off'
AS $function$
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
 centers(code,name) as (values ('10','Entreprenad'),('20','Sortergården'),('30','Transport'),('40','Verkstaden'),('50','Fastigheter'),('60','Skåne'),('90','Övrigt')),
 pairs as (
  select a.code from_code,a.name from_name,b.code to_code,b.name to_name
  from centers a cross join centers b
  where (a.code='10' and b.code in ('20','30'))
   or (a.code in ('20','30') and b.code in ('20','30') and a.code<>b.code)
   or (b.code='40' and a.code<>'40')
 ), transfers as (
  select c.*,coalesce(sum(u.amount),0) amount,
   coalesce(sum(u.amount)filter(where u.p->>'report_basis'='confirmed'),0) confirmed,
   coalesce(jsonb_agg(u.p order by u.p->>'occurred_on',u.p->>'order',u.p->>'source_key')filter(where u.p is not null),'[]') rows
  from pairs c left join unique_rows u on u.p->>'receiver_center'=c.from_code and u.p->>'source_center'=c.to_code and u.amount is not null
  group by c.from_code,c.from_name,c.to_code,c.to_name
 ), unassigned as materialized(
  select * from unique_rows where (p->>'receiver_center'='10' and nullif(p->>'source_center','') is null)
   or (p->>'source_center'='40' and nullif(p->>'receiver_center','') is null)
 ), other as materialized(
  select * from unique_rows u where not exists(select 1 from pairs c where u.p->>'receiver_center'=c.from_code and u.p->>'source_center'=c.to_code)
  and not exists(select 1 from unassigned a where a.p->>'source_key'=u.p->>'source_key')
 ),
 totals as(select coalesce(sum(amount),0) amount,coalesce(sum(confirmed),0) confirmed from transfers),
 reconciliation as(
  select coalesce((select sum(amount) from raw),0) source_amount,
   coalesce((select sum(raw_amount-amount) from unique_rows where amount is not null),0) duplicate_amount,
   coalesce((select sum(raw_amount) from conflicts),0) conflict_amount,
   coalesce((select sum(amount) from unassigned),0) unassigned_amount,
   coalesce((select sum(amount) from other),0) other_amount
 )
 select jsonb_build_object(
  'transfers',(select jsonb_agg(jsonb_build_object('fromCenter',from_code,'fromName',from_name,'toCenter',to_code,'toName',to_name,'amount',amount,'confirmedAmount',confirmed,'preliminaryAmount',amount-confirmed,'rows',rows) order by from_code,to_code desc) from transfers),
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

CREATE OR REPLACE FUNCTION public.hub_kpi_internal_center_summary_v2(p_tenant_id uuid, p_from date, p_to date, p_months integer[] DEFAULT NULL::integer[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET statement_timeout TO '45s'
 SET work_mem TO '64MB'
 SET jit TO 'off'
AS $function$
declare workify_rows jsonb; workshop_rows jsonb;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 workify_rows:=public.hub_kpi_internal_transfers_v1(p_tenant_id,p_from,p_to,p_months)->'rows';
 select coalesce(jsonb_agg(jsonb_build_object(
  'source_key','next-workshop:'||f.fact_id,'row_id',f.fact_id,'occurred_on',f.occurred_on,
  'order',f.original->>'AO/ÄTA','project',f.project,'source_center','40','receiver_center',c.center,
  'category','workshop','amount',f.amount,'article','4630','description',f.description,
  'ready',false,'invoiced',false,'status','review',
  'review_reason',case when c.center is null then 'Projektets kostnadsställe saknas eller är tvetydigt' else 'NEXT konto 4630 – underlag för avstämning' end
 )),'[]') into workshop_rows
 from private.hub_kpi_report_facts_v1 f
 join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 left join lateral (
  select case when count(distinct p.cost_center)=1 then min(p.cost_center) end center
  from public.kpi_project_classification_periods p
  where p.tenant_id=f.tenant_id and p.project_reference=f.project
   and p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 ) c on true
 where f.tenant_id=p_tenant_id and f.source='NEXT' and f.account='4630' and f.kind='cost'
   and f.amount<>0 and f.occurred_on between p_from and p_to
   and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))
   and (f.original->>'Kontobeskrivning' ilike '%verkstad%' or f.description ilike '%intern AO%')
   and c.center is distinct from '40';
 return private.hub_internal_center_summary_engine_v2(workify_rows||workshop_rows);
end $function$;