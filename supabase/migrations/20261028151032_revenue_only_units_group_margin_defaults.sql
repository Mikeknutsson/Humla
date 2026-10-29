create table private.hub_transport_group_targets_v1(tenant_id uuid not null,business_group text not null,margin_percent numeric not null check(margin_percent between -100 and 100),updated_by uuid not null,updated_at timestamptz not null default now(),reason text not null,primary key(tenant_id,business_group));
alter table private.hub_transport_group_targets_v1 enable row level security;
revoke all on private.hub_transport_group_targets_v1 from public,anon,authenticated;
comment on table private.hub_transport_group_targets_v1 is 'Group margin defaults; an explicit dated unit target takes precedence.';
CREATE OR REPLACE FUNCTION public.hub_transport_leader_scorecard_v4(p_tenant uuid, p_from date, p_to date, p_user uuid DEFAULT NULL::uuid, p_unit uuid DEFAULT NULL::uuid, p_page integer DEFAULT 0, p_months integer[] DEFAULT NULL::integer[], p_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare output jsonb;
begin
 if p_months is not null and (cardinality(p_months)=0 or not p_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]) then raise exception 'Invalid months';end if;
 if p_page is null or p_page<0 or p_page>10000 then raise exception 'Invalid page';end if;
 with scope_facts as materialized(select f.* from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user) f where (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 facts as materialized(select f.*,case when f.category='material' then 'material' when f.category in ('tipp','tipp_deponi') then 'tipp' when f.category='transport' then 'transport' else 'other' end section
 from scope_facts f where (p_unit is null or f.unit_id=p_unit) and (p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group) and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 enriched as materialized(select f.*,coalesce(t.margin_percent,g.margin_percent) margin_percent from facts f left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on) left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group),
 totals as(select unit_id,min(unit_name) unit_name,
 coalesce(nullif(business_group,''),'Ej klassificerat') business_group,
 grouping(unit_id,business_group) level,count(*) rows,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,
 count(*)filter(where kind='revenue' and amount<>0 and margin_percent is null) missing_targets,
 sum(amount*margin_percent/100)filter(where kind='revenue') target_result
 from enriched group by grouping sets ((unit_id),(business_group),())),
 metrics as(select *,revenue-cost result,case when revenue>0 then (revenue-cost)/revenue*100 end margin_percent,
 case when missing_targets=0 and revenue>0 and target_result is not null then target_result/revenue*100 end target_margin_percent,
 case when missing_targets=0 and target_result is not null then revenue-cost-target_result end deviation_amount,
 case when missing_targets=0 and revenue>0 and target_result is not null then ((revenue-cost)-target_result)/revenue*100 end deviation_pp from totals),
 units as(select * from metrics where level=1),
 breakdown as(select kind,category,sum(amount) amount,count(*) rows from facts group by kind,category),
 sections as(select section,coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows from facts group by section),
 analysis_finance as materialized(
 select unit_id,min(unit_name) unit_name,coalesce(nullif(business_group,''),'Ej klassificerat') business_group,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,
 coalesce(sum(amount)filter(where kind='cost' and category='personnel'),0) personnel,
 coalesce(sum(amount)filter(where kind='cost' and category='service_repair'),0) service_repair,
 coalesce(sum(amount)filter(where kind='cost' and category='fuel'),0) fuel,
 count(*)filter(where kind='cost' and category='personnel' and source<>'TransPA') other_personnel_rows
 from scope_facts where unit_id is not null group by unit_id,coalesce(nullif(business_group,''),'Ej klassificerat')
 ),
 time_ids as materialized(select distinct original->>'time_report_id' time_report_id from scope_facts
 where source='TransPA' and category='personnel' and original->>'time_report_id' is not null),
 -- Resolve time through the already published canonical unit link. Never divide a
 -- person's full report among vehicles by cost or by a guessed registration.
 time_links as materialized(
 select f.original->>'time_report_id' time_report_id,(array_agg(distinct f.unit_id))[1] unit_id,
 min(coalesce(nullif(f.business_group,''),'Ej klassificerat')) business_group,
 count(distinct f.unit_id)=1 and bool_and(f.unit_id is not null)
 and count(distinct coalesce(nullif(f.business_group,''),'Ej klassificerat'))=1 unambiguous
 from private.hub_kpi_prepared_display_facts f
 where f.tenant_id=p_tenant and f.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and f.source='TransPA' and f.category='personnel' and f.original->>'time_report_id' is not null group by f.original->>'time_report_id'
 ),
 analysis_time as(
 select a.unit_id,a.business_group,sum(t.work_hours) hours,
 count(*)filter(where not l.unambiguous or t.work_hours is null or t.work_hours<0) uncertain_reports
 from analysis_finance a join (select distinct unit_id,coalesce(nullif(business_group,''),'Ej klassificerat') business_group,original->>'time_report_id' time_report_id
 from scope_facts where source='TransPA' and category='personnel') s using(unit_id,business_group)
 join time_links l using(time_report_id)
 left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant
 and t.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and t.time_report_id=s.time_report_id and t.work_date between p_from and p_to
 group by a.unit_id,a.business_group
 ),
 analysis_inputs as(select a.*,case when a.other_personnel_rows=0 and t.uncertain_reports=0 and t.hours>0 then t.hours end worked_hours
 from analysis_finance a left join analysis_time t using(unit_id,business_group)),
 details as(select fact_id,occurred_on,kind,amount,category,unit_id,unit_name,project,vehicle,source,cost_center,
 original#>>'{_humla_invoice,order_number}' order_number,original#>>'{_humla_invoice,customer_name}' customer,
 original->'_humla_cost_rule' allocation_rule,original from facts order by occurred_on desc,fact_id limit 100 offset p_page*100)
 select jsonb_build_object('from',p_from,'to',p_to,
 'scope',case when p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then 'transport' else 'assigned' end,
 'summary',(select to_jsonb(m)||jsonb_build_object('revenue',case when rows>0 then revenue end,'cost',case when rows>0 then cost end,'result',case when rows>0 then result end,'unassigned_rows',(select count(*) from facts where unit_id is null)) from metrics m where level=3),
 'groups',(select coalesce(jsonb_agg(to_jsonb(m) order by business_group),'[]') from metrics m where level=2),
 'breakdown',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('share_of_revenue',case when m.revenue>0 then b.amount/m.revenue*100 end) order by b.kind,b.category),'[]') from breakdown b cross join metrics m where m.level=3),
 'units',(select coalesce(jsonb_agg(to_jsonb(u) order by unit_name nulls last),'[]')from units u),
 'sections',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('result',case when not exists(select 1 from sections c where c.section='other' and c.cost<>0) then revenue-cost end,'margin_percent',case when revenue<>0 and not exists(select 1 from sections c where c.section='other' and c.cost<>0) then (revenue-cost)/revenue*100 end)),'[]')from sections s),
 'transactions',case when p_unit is not null then(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from details d)else '[]'::jsonb end,
 'analysis_inputs',(select coalesce(jsonb_agg(to_jsonb(a) order by unit_id,business_group),'[]') from analysis_inputs a),
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant)) into output;
 return output;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_kpi_mapped_units_projection_v1(p_tenant uuid, p_report jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb:=p_report; mapped jsonb; hidden jsonb; section text;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 if jsonb_typeof(result->'economic_units')='array' then
  select coalesce(jsonb_agg(case when o.data->>'report_fallback'='unresolved' then e.value||jsonb_build_object('is_fallback',true,'worked_hours',null,'distance_mil',null,'utilization',null,'billing_percent',null,'revenue_per_hour',null,'cost_per_hour',null,'cost_per_mil',null,'revenue_per_mil',null,'fuel_cost_per_mil',null,'fuel_liters_per_mil',null)else e.value end order by e.ordinality) filter(where o.id is not null and coalesce((e.value->>'revenue')::numeric,0)>0),'[]'::jsonb),
   jsonb_build_object('count',count(*) filter(where o.id is null),
    'revenue',coalesce(sum((e.value->>'revenue')::numeric) filter(where o.id is null),0),
    'cost',coalesce(sum((e.value->>'cost')::numeric) filter(where o.id is null),0))
  into mapped,hidden
  from jsonb_array_elements(result->'economic_units') with ordinality e(value,ordinality)
  left join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and o.id::text=e.value->>'key';
  result:=result||jsonb_build_object('economic_units',mapped,'economic_unit_scope','mapped','unmapped_economic_units',hidden);
 end if;
 foreach section in array array['month','ytd','previous'] loop
  if jsonb_typeof(result->section)='object' then
   result:=jsonb_set(result,array[section],private.hub_kpi_mapped_units_projection_v1(p_tenant,result->section));
  end if;
 end loop;
 result:=result||jsonb_build_object('material_unit_id',(select material_unit_id from private.hub_kpi_material_separation_settings where tenant_id=p_tenant and enabled));
 result:=result||jsonb_build_object('excluded_projects',coalesce((select jsonb_agg(jsonb_build_object('project_id',project_id,'name',display_name,'reason',reason))from private.hub_kpi_project_exclusions where tenant_id=p_tenant and enabled),'[]'::jsonb));
return result;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_apply_monthly_overhead_v1(p_tenant uuid, p_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare before_base numeric;after_base numeric;result jsonb;asof_date date:=(clock_timestamp() at time zone 'Europe/Stockholm')::date;
begin
if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then raise exception 'Generation mismatch';end if;
perform pg_advisory_xact_lock(hashtextextended('cost-allocation:'||p_tenant::text,0));
select sum(amount) into before_base from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and not(original?'_humla_monthly_overhead');
delete from private.hub_kpi_prepared_display_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
delete from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
create temporary table monthly_overhead_output on commit drop as
with rules as materialized(
 select r.* from public.hub_cost_allocation_rules r where r.tenant_id=p_tenant and r.enabled and r.include_in_vehicle_result
 and r.source_scope->>'engine'='monthly_overhead_v1' and r.allocation_method='revenue_share'
 and r.monthly_amount>=0 and r.valid_from<=asof_date),
months as materialized(
 select r.*,m.dt::date month_start,
 greatest(m.dt::date,r.valid_from) first_day,
 least((m.dt+interval '1 month -1 day')::date,coalesce(r.valid_to,asof_date),asof_date) last_day,
 extract(day from m.dt+interval '1 month -1 day')::numeric month_days
 from rules r cross join lateral generate_series(date_trunc('month',r.valid_from),date_trunc('month',least(coalesce(r.valid_to,asof_date),asof_date)),interval '1 month')m(dt)),
revenue as materialized(
 select date_trunc('month',f.occurred_on)::date month_start,
 public.hub_resolve_canonical_object_v1(p_tenant,f.unit_id) unit_id,
 f.cost_center,max(f.unit_name) unit_name,max(f.business_group) business_group,max(f.vehicle) vehicle,
 greatest(sum(f.amount),0) weight
 from private.hub_kpi_prepared_facts f
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='revenue' and f.unit_id is not null and f.occurred_on<=asof_date
 and f.occurred_on>=(select min(valid_from) from rules)
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and f.cost_center in('20','30')
 group by 1,2,3 having sum(f.amount)>0),
recipients as materialized(
 select m.*,v.unit_id,v.cost_center,v.unit_name,v.business_group,v.vehicle,v.weight,
 sum(v.weight)over(partition by m.id,m.month_start) total_weight
 from months m join revenue v on v.month_start=m.month_start and m.target_scope->'cost_centers' ? v.cost_center
 where m.last_day>=m.first_day),
daily as(
 select r.*,d.dt::date occurred_on,round(r.monthly_amount*(r.last_day-r.first_day+1)/r.month_days,2) period_total,
 r.weight/r.total_weight/(r.last_day-r.first_day+1) share
 from recipients r cross join lateral generate_series(r.first_day::timestamp,r.last_day::timestamp,interval '1 day')d(dt)),
allocated as(
 select d.*,round(period_total*sum(share)over(partition by id,month_start order by occurred_on,unit_id,cost_center rows unbounded preceding),2)
 -round(period_total*coalesce(sum(share)over(partition by id,month_start order by occurred_on,unit_id,cost_center rows between unbounded preceding and 1 preceding),0),2) amount
 from daily d),
outputs as(
 select a.id rule_id,a.name,month_start,occurred_on,unit_id,cost_center,unit_name,business_group,vehicle,amount,monthly_amount,base_amount,po_percent,cost_category,
 jsonb_build_object('rule_id',id,'rule_name',name,'month',month_start,'monthly_amount',monthly_amount,'base_salary',base_amount,'po_percent',po_percent,
 'method','revenue_share','unit_month_revenue',weight,'scope_month_revenue',total_weight,'cost_group','overhead',
 'cost_type',case when common_cost_type='management' then 'management' else 'other' end,
 'status','allocated','basis','User-confirmed supplemental overhead estimate; monthly net positive revenue, allocated daily') meta from allocated a
 union all
 select m.id,m.name,m.month_start,d.dt::date,null::uuid,
 case when jsonb_array_length(m.target_scope->'cost_centers')=1 then m.target_scope#>>'{cost_centers,0}' else 'unclassified' end,
 'Overhead – saknar omsättningsunderlag','Ej fördelat',null::text,
 round(m.monthly_amount*(d.dt::date-m.first_day+1)/m.month_days,2)-round(m.monthly_amount*(d.dt::date-m.first_day)/m.month_days,2),
 m.monthly_amount,m.base_amount,m.po_percent,m.cost_category,
 jsonb_build_object('rule_id',m.id,'rule_name',m.name,'month',m.month_start,'monthly_amount',m.monthly_amount,
 'cost_group','overhead','cost_type',case when m.common_cost_type='management' then 'management' else 'other' end,'status','no_revenue_basis')
 from months m cross join lateral generate_series(m.first_day::timestamp,m.last_day::timestamp,interval '1 day')d(dt)
 where not exists(select 1 from recipients r where r.id=m.id and r.month_start=m.month_start))
select o.*,jsonb_build_object('_humla_monthly_overhead',meta,'Description',name) evidence from outputs o;

insert into private.hub_kpi_prepared_facts
(generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,description,original,cost_center,cost_center_name,classification_source,display_original)
select p_generation,p_tenant,extract(year from occurred_on)::int-case when extract(month from occurred_on)<9 then 1 else 0 end,
'overhead:'||rule_id||':'||occurred_on||':'||coalesce(unit_id::text,'unresolved')||':'||cost_center,
occurred_on,'cost',amount,cost_category,null,vehicle,unit_id,unit_name,business_group,'Overhead',name,evidence,cost_center,
case cost_center when '20' then 'Sortergården' when '30' then 'Transport' else 'Ej fördelat' end,
jsonb_build_object('source','monthly_overhead_v1','rule_id',rule_id),evidence
from pg_temp.monthly_overhead_output;
insert into private.hub_kpi_prepared_display_facts
select generation_id,tenant_id,fiscal_year,fact_id,occurred_on,kind,amount,category,project,vehicle,unit_id,unit_name,business_group,source,cost_center,display_original
from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and original?'_humla_monthly_overhead';
if exists(
 select 1 from (select rule_id,month_start,sum(amount) actual,max(monthly_amount) monthly_amount,count(distinct occurred_on) days from pg_temp.monthly_overhead_output group by 1,2)x
 where actual<>round(monthly_amount*days/extract(day from month_start+interval '1 month -1 day'),2))then raise exception 'Monthly overhead does not reconcile';end if;
select sum(amount) into after_base from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation and not(original?'_humla_monthly_overhead');
if before_base is distinct from after_base then raise exception 'Overhead changed source totals';end if;
select jsonb_build_object('rows',count(*),'cost',sum(amount),'unallocated_cost',coalesce(sum(amount)filter(where meta->>'status'<>'allocated'),0)) into result from pg_temp.monthly_overhead_output;
drop table pg_temp.monthly_overhead_output;
return result;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_cost_allocation_plan_v1(p_tenant uuid, p_generation uuid, p_preview boolean DEFAULT false)
 RETURNS TABLE(rule_id uuid, fact_id text, status text, recipients jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 return query
 with rules as materialized(select r.* from public.hub_cost_allocation_rules r where r.tenant_id=p_tenant and (r.enabled or p_preview) and r.include_in_vehicle_result and r.source_scope is not null),
 periods as materialized(
 select o.id,p.value payload,(p.value->>'valid_from')::date valid_from,(p.value->>'valid_to')::date valid_to,
 p.value->>'name' name,g.name grp,v.id main_id,v.data->>'vehicle_type' vehicle_type,
 p.value#>>'{main_vehicle,source_reference}' registration
 from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p
 left join public.hub_objects v on v.id::text=p.value#>>'{main_vehicle,object_id}' and v.tenant_id=p_tenant
 left join public.kpi_business_groups g on g.id::text=p.value->>'business_group_id' and g.tenant_id=p_tenant
 where o.tenant_id=p_tenant and o.object_type='EconomicUnit' and (p.value->>'enabled')::boolean),
 source_ids as materialized(
 select r.id rule_id,(private.hub_economic_member_v1(p_tenant,'project',x.ref)->>'object_id')::uuid object_id
 from rules r cross join lateral jsonb_array_elements_text(coalesce(r.source_scope->'project_references',jsonb_build_array(r.source_scope->>'project_reference')))x(ref) where x.ref is not null
 union
 select r.id,(m.value->>'object_id')::uuid from rules r join public.hub_objects o on o.tenant_id=p_tenant and o.object_type='EconomicUnit' and r.source_scope->'source_unit_names' ? (o.data->>'name')
 cross join lateral jsonb_array_elements(o.data->'periods')p cross join lateral jsonb_array_elements(p.value->'members')m where m.value->>'object_id' is not null),
 source_keys as materialized(select distinct s.rule_id,k.identity_type,k.identity_value from source_ids s join public.hub_identity_keys k on k.object_id=s.object_id and k.tenant_id=p_tenant and k.identity_type in('next_project_number','registration_number')),
 source_matches as materialized(
 select distinct f.fact_id,k.rule_id from private.hub_kpi_prepared_display_facts f join source_keys k on k.identity_type='next_project_number' and k.identity_value=f.project where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
 union
 select distinct f.fact_id,k.rule_id from private.hub_kpi_prepared_display_facts f join source_keys k on k.identity_type='registration_number' and k.identity_value=f.vehicle where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost'
 ),
 matched as materialized(
 select f.*,r.id rule_id,r.allocation_method,r.target_selection_mode,r.selected_object_ids,r.target_scope,r.source_scope,
 count(*)over(partition by f.fact_id) rule_count
 from source_matches sm join private.hub_kpi_prepared_facts f on f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=sm.fact_id join rules r on r.id=sm.rule_id and f.occurred_on>=r.valid_from and (r.valid_to is null or f.occurred_on<=r.valid_to)
 where f.tenant_id=p_tenant and f.generation_id=p_generation and f.kind='cost' and not (f.original ? '_humla_cost_rule')

 ), candidates as materialized(
 select f.fact_id,p.id,p.name,p.grp,p.registration
 from matched f join periods p on p.valid_from<=f.occurred_on and (p.valid_to is null or p.valid_to>=f.occurred_on)
 where f.rule_count=1 and f.cost_center=f.source_scope->>'cost_center'
 and not exists(select 1 from source_ids s where s.rule_id=f.rule_id and s.object_id=p.main_id)
 and not (coalesce(f.target_scope->'exclude_unit_names','[]') ? p.name)
 and (f.allocation_method<>'equal' or exists(
  select 1 from private.hub_kpi_prepared_facts rev
  where rev.tenant_id=p_tenant and rev.generation_id=p_generation and rev.kind='revenue'
  and public.hub_resolve_canonical_object_v1(p_tenant,rev.unit_id)=public.hub_resolve_canonical_object_v1(p_tenant,p.id)
  and not coalesce((rev.original->>'_humla_excluded_from_kpi')::boolean,false)
  and rev.cost_center=f.cost_center
  and rev.occurred_on>=date_trunc('month',f.occurred_on)::date
  and rev.occurred_on<(date_trunc('month',f.occurred_on)+interval '1 month')::date
  group by rev.cost_center having sum(rev.amount)>0
 ))
 and (
 (f.allocation_method='equal' and ((f.target_selection_mode='selected' and p.id=any(f.selected_object_ids))
 or (f.target_selection_mode='all' and f.target_scope->>'own_trucks_only'='true'
 and (p.vehicle_type='Lastbil' or exists(select 1 from rules confirmed where confirmed.target_scope->>'business_group' in ('Bygg & Anläggning','Kranbilar','Stena') and p.id=any(confirmed.selected_object_ids)))
 and exists(select 1 from public.kpi_project_classification_periods c where c.tenant_id=p_tenant and p.registration=any(c.registrations) and c.cost_center=f.target_scope->>'cost_center' and c.valid_from<=f.occurred_on and (c.valid_to is null or c.valid_to>=f.occurred_on)))))
 or (f.allocation_method='manual' and f.target_scope->>'require_confirmed_vehicle'='true' and exists(
 select 1 from jsonb_array_elements(p.payload->'members')m
 join public.hub_identity_keys k on k.object_id::text=m.value->>'object_id' and k.tenant_id=p_tenant
 where (k.identity_type='registration_number' and k.identity_value=coalesce(nullif(f.vehicle,''),nullif(f.original->>'Registreringsnummer',''),nullif(f.original->>'Regnr','')))
 or (k.identity_type='employee_number' and k.identity_value=coalesce(nullif(f.original->>'employee_id',''),nullif(f.original->>'Anställningsnummer','')))
 or (k.identity_type='next_project_number' and k.identity_value=f.original#>>'{_humla_assignment,project}' and k.identity_value<>f.project))))
 ), recipients as(select c.fact_id,jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'group',c.grp,'vehicle',c.registration) order by c.id) value,count(*) n from (select distinct * from candidates)c group by c.fact_id)
 select f.rule_id,f.fact_id,case when f.rule_count<>1 then 'overlapping_rules' when f.cost_center is distinct from f.source_scope->>'cost_center' then 'cost_center_review'
 when f.original#>>'{_humla_distribution,status}'='allocated' then 'already_distributed_review'
 when f.allocation_method='manual' and coalesce(r.n,0)<>1 then 'identity_review'
 when coalesce(r.n,0)=0 then 'no_eligible_units'
 when f.allocation_method not in('equal','manual') then 'unsupported_method' else 'allocated' end,
 coalesce(r.value,'[]') from matched f left join recipients r on r.fact_id=f.fact_id;
end $function$;;
