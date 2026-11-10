CREATE OR REPLACE FUNCTION public.hub_transport_leader_scorecard_v4(p_tenant uuid, p_from date, p_to date, p_user uuid DEFAULT NULL::uuid, p_unit uuid DEFAULT NULL::uuid, p_page integer DEFAULT 0, p_months integer[] DEFAULT NULL::integer[], p_group text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET jit TO 'off'
 SET plan_cache_mode TO 'force_custom_plan'
AS $function$
declare output jsonb; time_basis jsonb; hours numeric; time_to date; time_revenue numeric; time_cost numeric; covered int; ola_view boolean;
begin
 if p_months is not null and (cardinality(p_months)=0 or not p_months <@ array[1,2,3,4,5,6,7,8,9,10,11,12]) then raise exception 'Invalid months';end if;
 if p_page is null or p_page<0 or p_page>10000 then raise exception 'Invalid page';end if;
 select p_group is null and exists(
  select 1 from public.hub_tenant_members m
  where m.tenant_id=p_tenant and m.user_id=p_user and m.status='active'
    and trim(m.display_name) ~* '^ola([[:space:]]|$)'
 ) into ola_view;
 with scope_facts as materialized(select f.*,
  case
   when not ola_view then f.business_group
   when f.unit_name in ('WCF22U','LZP91Z','HGL39H') then 'Asfaltskörning'
   when f.unit_name='DUN012' then 'Fasta uppdrag'
   when f.unit_name='Inhyrda bilar' or f.business_group='Inhyrda lastbilar' then 'Bygg & Anläggning'
   else f.business_group
  end as view_group,
  case when ola_view and f.unit_name='Grusmaterial - Lager'
   then 'Grusmaterial Försäljning' else f.unit_name end as view_unit_name
 from private.hub_transport_leader_facts_v2(p_tenant,p_from,p_to,p_user) f where (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 facts as materialized(select f.*,case when f.category='material' then 'material' when f.category in ('tipp','tipp_deponi') then 'tipp' when f.category='transport' then 'transport' else 'other' end section
 from scope_facts f where (p_unit is null or f.unit_id=p_unit) and (p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group) and (p_months is null or extract(month from f.occurred_on)::integer=any(p_months))),
 enriched as materialized(select f.*,coalesce(t.margin_percent,g.margin_percent,20::numeric) margin_percent from facts f left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on) left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group),
 totals as(select unit_id,min(view_unit_name) unit_name,
 coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 grouping(unit_id,view_group) level,count(*) rows,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,
 count(*)filter(where kind='revenue' and amount<>0 and margin_percent is null) missing_targets,
 sum(amount*margin_percent/100)filter(where kind='revenue') target_result
 from enriched group by grouping sets ((unit_id),(view_group),())),
 metrics as(select *,revenue-cost result,case when revenue>0 then (revenue-cost)/revenue*100 end margin_percent,
 case when missing_targets=0 and revenue>0 and target_result is not null then target_result/revenue*100 end target_margin_percent,
 case when missing_targets=0 and target_result is not null then revenue-cost-target_result end deviation_amount,
 case when missing_targets=0 and revenue>0 and target_result is not null then ((revenue-cost)-target_result)/revenue*100 end deviation_pp from totals),
 unit_cost_rows as materialized(select unit_id,category,sum(amount) amount,count(*) rows from facts where kind='cost' group by unit_id,category),
 unit_cost_breakdowns as materialized(select unit_id,jsonb_agg(jsonb_build_object('category',category,'amount',amount,'rows',rows) order by category) cost_breakdown from unit_cost_rows group by unit_id),
 units as(select * from metrics where level=1),
 breakdown as(select kind,category,sum(amount) amount,count(*) rows from facts group by kind,category),
 sections as(select section,coalesce(sum(amount)filter(where kind='revenue'),0) revenue,coalesce(sum(amount)filter(where kind='cost'),0) cost,count(*) rows from facts group by section),
 analysis_finance as materialized(
 select unit_id,min(view_unit_name) unit_name,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,
 coalesce(sum(amount)filter(where kind='revenue'),0) revenue,
 coalesce(sum(amount)filter(where kind='cost' and category='personnel'),0) personnel,
 coalesce(sum(amount)filter(where kind='cost' and category='service_repair'),0) service_repair,
 coalesce(sum(amount)filter(where kind='cost' and category='fuel'),0) fuel,
 count(*)filter(where kind='cost' and category='personnel' and source<>'TransPA') other_personnel_rows
 from scope_facts where unit_id is not null group by unit_id,coalesce(nullif(view_group,''),'Ej klassificerat')
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
 from analysis_finance a join (select distinct unit_id,coalesce(nullif(view_group,''),'Ej klassificerat') business_group,original->>'time_report_id' time_report_id
 from scope_facts where source='TransPA' and category='personnel') s using(unit_id,business_group)
 join time_links l using(time_report_id)
 left join private.hub_kpi_prepared_kpi_transpa_time_facts t on t.tenant_id=p_tenant
 and t.generation_id=(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant)
 and t.time_report_id=s.time_report_id and t.work_date between p_from and p_to
 group by a.unit_id,a.business_group
 ),
 analysis_inputs as(select a.*,case when a.other_personnel_rows=0 and t.uncertain_reports=0 and t.hours>0 then t.hours end worked_hours
 from analysis_finance a left join analysis_time t using(unit_id,business_group)),
 details as(select fact_id,occurred_on,kind,amount,category,unit_id,view_unit_name as unit_name,project,vehicle,source,cost_center,
 original#>>'{_humla_invoice,order_number}' order_number,original#>>'{_humla_invoice,customer_name}' customer,
 original->'_humla_cost_rule' allocation_rule,original from facts order by occurred_on desc,fact_id limit 100 offset p_page*100)
 select jsonb_build_object('from',p_from,'to',p_to,
 'scope',case when p_user is null and exists(select 1 from public.hub_tenant_members m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role='owner') then 'transport' else 'assigned' end,
 'summary',(select to_jsonb(m)||jsonb_build_object('revenue',case when rows>0 then revenue end,'cost',case when rows>0 then cost end,'result',case when rows>0 then result end,'unassigned_rows',(select count(*) from facts where unit_id is null)) from metrics m where level=3),
 'groups',(select coalesce(jsonb_agg(to_jsonb(m) order by business_group),'[]') from metrics m where level=2),
 'breakdown',(select coalesce(jsonb_agg(to_jsonb(b)||jsonb_build_object('share_of_revenue',case when m.revenue>0 then b.amount/m.revenue*100 end) order by b.kind,b.category),'[]') from breakdown b cross join metrics m where m.level=3),
 'units',(select coalesce(jsonb_agg(to_jsonb(u)||jsonb_build_object('cost_breakdown',coalesce((select c.cost_breakdown from unit_cost_breakdowns c where c.unit_id is not distinct from u.unit_id),'[]'::jsonb)) order by unit_name nulls last),'[]')from units u),
 'sections',(select coalesce(jsonb_agg(to_jsonb(s)||jsonb_build_object('result',case when not exists(select 1 from sections c where c.section='other' and c.cost<>0) then revenue-cost end,'margin_percent',case when revenue<>0 and not exists(select 1 from sections c where c.section='other' and c.cost<>0) then (revenue-cost)/revenue*100 end)),'[]')from sections s),
 'transactions',case when p_unit is not null then(select coalesce(jsonb_agg(to_jsonb(d)),'[]')from details d)else '[]'::jsonb end,
 'analysis_inputs',(select coalesce(jsonb_agg(to_jsonb(a) order by unit_id,business_group),'[]') from analysis_inputs a),
 'saw_breakdown',(select case when count(*)>0 then jsonb_build_object(
 'revenue',coalesce(sum(amount)filter(where kind='revenue'),0),
 'material_revenue',coalesce(sum(amount)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_tons',coalesce(sum((original#>>'{_humla_saw_chip,tons}')::numeric)filter(where kind='revenue' and original?'_humla_saw_chip'),0),
 'material_rate',(select chip_rate_per_ton from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant),
 'cost',coalesce(sum(amount)filter(where kind='cost'),0),
 'management_cost',coalesce(sum(amount)filter(where kind='cost' and category='management'),0),
 'other_cost',coalesce(sum(amount)filter(where kind='cost' and category is distinct from 'management'),0),
 'truck_charge',coalesce(sum((original#>>'{_humla_saw_activity,hours}')::numeric*(original#>>'{_humla_saw_activity,truck_hour_rate}')::numeric)
 filter(where kind='revenue' and original#>>'{_humla_saw_activity,reason}'='article_hour_split' and original#>>'{_humla_saw_activity,branch}'='saw'),0),
 'material_rows',coalesce(jsonb_agg(jsonb_build_object('id',fact_id,'date',occurred_on,'tons',original#>'{_humla_saw_chip,tons}',
 'amount',amount,'source',original#>>'{_humla_saw_chip,source}','ticket',original#>>'{_humla_saw_chip,ticket_number}',
 'order',coalesce(original#>>'{_humla_saw_chip,order_number}',original#>>'{_humla_saw_chip,order_numbers}')) order by occurred_on,fact_id)
 filter(where kind='revenue' and original?'_humla_saw_chip'),'[]'::jsonb)) end
 from facts where unit_id=(select unit_id from private.hub_saw_activity_rules_v1 where tenant_id=p_tenant)),
 'generation',(select active_generation from private.hub_kpi_report_state where tenant_id=p_tenant),
 'synced_at',(select synced_at from private.hub_kpi_report_state where tenant_id=p_tenant)) into output;
 
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,p_to,p_user,p_unit,p_months,p_group);
time_to:=case when(time_basis->>'shared_crane_time')::boolean then(time_basis->>'through')::date else least((time_basis->>'transpa_through')::date,(time_basis->>'next_through')::date)end;
if time_to is not null and time_to<p_to then
time_basis:=private.hub_foreman_hours_v1(p_tenant,p_from,time_to,p_user,p_unit,p_months,p_group);
end if;
hours:=(time_basis->>'worked_hours')::numeric;
select coalesce(sum(f.amount)filter(where f.kind='revenue'),0),coalesce(sum(f.amount)filter(where f.kind='cost'),0)into time_revenue,time_cost
from private.hub_transport_leader_facts_v2(p_tenant,p_from,coalesce(time_to,p_to),p_user)f
where(p_unit is null or f.unit_id=p_unit)and(p_group is null or coalesce(nullif(f.business_group,''),'Ej klassificerat')=p_group)
and(p_months is null or extract(month from f.occurred_on)::int=any(p_months));
select count(*)into covered from jsonb_to_recordset(coalesce(time_basis->'units','[]'))u(unit_id uuid,hours numeric)
where u.hours>0 and exists(select 1 from jsonb_to_recordset(output->'units')r(unit_id uuid)where r.unit_id=u.unit_id);
output:=output||jsonb_build_object('area_kpis',private.hub_foreman_area_kpis_v1(output,true)||jsonb_build_object(
'worked_hours',hours,'verified_hours',hours,'covered_units',covered,'hours_complete',false,
'revenue_per_hour',case when hours>0 then time_revenue/hours end,
'cost_per_hour',case when hours>0 then time_cost/hours end,
'result_per_hour',case when hours>0 then(time_revenue-time_cost)/hours end,
'time_from',p_from,'time_to',time_to,'time_sources',time_basis-'units',
'time_revenue',time_revenue,'time_cost',time_cost,'time_result',time_revenue-time_cost));

 output:=private.hub_foreman_mileage_v1(p_tenant,output,p_user,p_months,p_group);
 return private.hub_foreman_time_cards_v1(p_tenant,output,p_user,p_months,p_group);
end $function$;