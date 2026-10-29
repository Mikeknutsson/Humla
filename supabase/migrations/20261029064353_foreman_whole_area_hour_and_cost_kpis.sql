create or replace function private.hub_foreman_area_kpis_v1(p_report jsonb,p_time_scope_ok boolean default true)
returns jsonb language sql immutable set search_path='' as $fn$
with units as(select * from jsonb_to_recordset(coalesce(p_report->'units','[]')) as u(unit_id uuid,revenue numeric,cost numeric)),
hours as(select a.unit_id,case when count(*)=1 and min(a.worked_hours)>0 then min(a.worked_hours) end hours
from jsonb_to_recordset(coalesce(p_report->'analysis_inputs','[]')) as a(unit_id uuid,worked_hours numeric) group by a.unit_id),
coverage as(select count(*) required,count(h.hours) covered,sum(h.hours) hours from units u left join hours h using(unit_id)),
costs as(select coalesce(sum(b.amount)filter(where category='personnel'),0) personnel,
coalesce(sum(b.amount)filter(where category='fuel'),0) fuel,
coalesce(sum(b.amount)filter(where category='service_repair'),0) repair
from jsonb_to_recordset(coalesce(p_report->'breakdown','[]')) as b(kind text,category text,amount numeric) where kind='cost'),
base as(select c.*,k.*,(p_report->'summary'->>'revenue')::numeric revenue,(p_report->'summary'->>'cost')::numeric cost,
(p_report->'summary'->>'result')::numeric result,
p_time_scope_ok and c.required>0 and c.covered=c.required and coalesce((p_report->'summary'->>'unassigned_rows')::int,0)=0 complete
from coverage c cross join costs k)
select jsonb_build_object('required_units',required,'covered_units',covered,'hours_complete',complete,
'verified_hours',hours,'worked_hours',case when complete then hours end,
'revenue_per_hour',case when complete and hours>0 then revenue/hours end,
'cost_per_hour',case when complete and hours>0 then cost/hours end,
'result_per_hour',case when complete and hours>0 then result/hours end,
'personnel_share',case when revenue>0 then personnel/revenue*100 end,
'fuel_share',case when revenue>0 then fuel/revenue*100 end,
'repair_share',case when revenue>0 then repair/revenue*100 end) from base;
$fn$;
revoke all on function private.hub_foreman_area_kpis_v1(jsonb,boolean) from public,anon,authenticated;
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
 output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,p_months is null));
 return output;
end $function$
