create or replace function private.hub_driver_goal_deviation_v1(p_revenue numeric,p_cost numeric,p_goal numeric,p_missing bigint)
returns numeric language sql immutable set search_path='' as $g$
select case when p_revenue>0 and p_goal>0 and p_missing=0 then round((p_revenue-p_cost-p_goal)/p_goal*100,1) end;
$g$;
revoke all on function private.hub_driver_goal_deviation_v1(numeric,numeric,numeric,bigint) from public,anon,authenticated;

create or replace function private.hub_driver_vehicle_context_v1(p_tenant uuid,p_person uuid,p_from date,p_to date)
returns jsonb language sql stable set search_path='' set jit=off as $body$
with own_time as materialized(
 select t.transpa_vehicle_ids from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant and t.work_date between p_from and p_to and t.work_hours>0
 and (t.person_object_id=p_person or (t.person_object_id is null and exists(select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=p_person and k.identity_type='transpa_employee_id' and k.confidence=1 and k.identity_value=t.employee_id and not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>p_person))))
),vehicle_keys as(
 select k.identity_value,(array_agg(distinct k.object_id))[1] vehicle_id from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='transpa_vehicle_id' and k.confidence=1 group by k.identity_value having count(distinct k.object_id)=1
),vehicles as(select distinct k.vehicle_id from own_time t cross join lateral jsonb_array_elements_text(case when jsonb_typeof(t.transpa_vehicle_ids)='array' then t.transpa_vehicle_ids else '[]' end) id join vehicle_keys k on k.identity_value=id),
registrations as(select distinct v.vehicle_id,public.hub_normalize_vehicle_registration(k.identity_value) registration from vehicles v join public.hub_identity_keys k on k.object_id=v.vehicle_id and k.tenant_id=p_tenant and k.identity_type='registration_number' and k.confidence=1),

periods as (
select 'current'::text key,p_from first_day,p_to last_day
union all select 'previous',p_from-(p_to-p_from+1),p_from-1
union all select 'year',(p_from-interval '1 year')::date,(p_to-interval '1 year')::date
),
facts as materialized(
select f.*,p.key period_key from private.hub_kpi_prepared_display_facts f
join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
join periods p on f.occurred_on between p.first_day and p.last_day
where f.tenant_id=p_tenant and f.cost_center='30'
and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
),
linked_units as(select distinct f.unit_id from facts f join registrations r on r.registration=public.hub_normalize_vehicle_registration(f.vehicle)
where f.period_key='current' and f.unit_id is not null),
enriched as(
select f.*,coalesce(t.margin_percent,g.margin_percent) goal from facts f join linked_units u using(unit_id)
left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id
and t.valid_from<=f.occurred_on and(t.valid_to is null or t.valid_to>=f.occurred_on)
left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group
),
sums as(
select unit_id,period_key,min(unit_name)name,min(business_group)business_group,
sum(amount)filter(where kind='revenue')revenue,coalesce(sum(amount)filter(where kind='cost'),0)cost,
sum(amount*goal/100)filter(where kind='revenue')target_result,
count(*)filter(where kind='revenue' and amount<>0 and goal is null)missing_goals,
sum(amount)filter(where kind='cost' and category='fuel')fuel,
sum(amount)filter(where kind='cost' and category='service_repair')repair,
sum(amount)filter(where kind='cost' and source='Piusi' and amount>0 and (original#>>'{_humla_fuel,quantity_liters}')::numeric>0)metered_fuel_cost,
sum((original#>>'{_humla_fuel,quantity_liters}')::numeric)filter(where kind='cost' and source='Piusi' and amount>0 and (original#>>'{_humla_fuel,quantity_liters}')::numeric>0)metered_liters
from enriched group by unit_id,period_key
),
metrics as(select *,private.hub_driver_goal_deviation_v1(revenue,cost,target_result,missing_goals)deviation,
case when revenue>0 then (revenue-cost)/revenue*100 end margin from sums),
current_metrics as(
select c.*,p.deviation previous_deviation,y.deviation year_deviation,p.margin previous_margin,p.revenue previous_revenue,p.cost previous_cost,
p.fuel previous_fuel,p.repair previous_repair,
case when c.deviation<0 and c.metered_fuel_cost>0 and c.metered_liters>=10 then
least(ceil((c.target_result-(c.revenue-c.cost))*c.metered_liters/c.metered_fuel_cost),floor(c.metered_liters*0.10))end fuel_example_liters
from metrics c left join metrics p on p.unit_id=c.unit_id and p.period_key='previous'
left join metrics y on y.unit_id=c.unit_id and y.period_key='year' where c.period_key='current'
)
select coalesce(jsonb_agg(jsonb_build_object(
'name',name,'goal_deviation_pct',deviation,'previous_goal_deviation_pct',previous_deviation,'year_goal_deviation_pct',year_deviation,
'change_vs_previous_pp',case when deviation is not null and previous_deviation is not null then deviation-previous_deviation end,
'change_vs_year_pp',case when deviation is not null and year_deviation is not null then deviation-year_deviation end,
'year_from',(p_from-interval '1 year')::date,'year_to',(p_to-interval '1 year')::date,
'comparison_from',p_from-(p_to-p_from+1),'comparison_to',p_from-1,
'margin_pct',round(margin,1),'target_pct',case when revenue>0 and missing_goals=0 then round(target_result/revenue*100,1) end,
'target_gap_pp',case when revenue>0 and missing_goals=0 then round((revenue-cost-target_result)/revenue*100,1) end,
'margin_change_pp',round(margin-previous_margin,1),
'revenue_change_pct',case when previous_revenue>0 and revenue is not null then round((revenue-previous_revenue)/previous_revenue*100,1) end,
'cost_change_pct',case when previous_cost>0 then round((cost-previous_cost)/previous_cost*100,1) end,
'cost_share_pct',case when revenue>0 then round(cost/revenue*100,1) end,
'fuel_share_pct',case when revenue>0 and fuel is not null then round(fuel/revenue*100,1) end,
'repair_share_pct',case when revenue>0 and repair is not null then round(repair/revenue*100,1) end,
'fuel_change_pp',case when revenue>0 and previous_revenue>0 and fuel is not null and previous_fuel is not null then round((fuel/revenue-previous_fuel/previous_revenue)*100,1)end,
'repair_change_pp',case when revenue>0 and previous_revenue>0 and repair is not null and previous_repair is not null then round((repair/revenue-previous_repair/previous_revenue)*100,1)end,
'balance',case when deviation is null then 'unknown' when deviation>=0 then 'on_target' when deviation>=-20 then 'near_target' else 'below_target' end,
'actions',case when deviation is null then '[]'::jsonb when deviation>=0 then jsonb_build_array(jsonb_build_object('kind','maintain'))
else (case when fuel_example_liters>0 then jsonb_build_array(jsonb_build_object('kind','fuel','liters',fuel_example_liters,
'gap_covered_pct',least(100,round(fuel_example_liters*metered_fuel_cost/metered_liters/(target_result-(revenue-cost))*100,0)),
'estimated',true))else '[]'::jsonb end)
||jsonb_build_array(jsonb_build_object('kind',case when business_group='Stena' then 'emptying' else 'load' end,
'quantity',null,'reason','marginal_contribution_missing'),jsonb_build_object('kind','reporting'))end,
'revenue_trend',case when previous_revenue is null or previous_revenue<=0 or revenue is null then 'unknown' when revenue/previous_revenue>1.05 then 'up' when revenue/previous_revenue<0.95 then 'down' else 'steady' end,
'result_trend',case when margin is null or previous_margin is null then 'unknown' when margin-previous_margin>2 then 'up' when margin-previous_margin< -2 then 'down' else 'steady' end,
'fuel_share',case when revenue<=0 or previous_revenue<=0 or fuel is null or previous_fuel is null then 'unknown' when fuel/revenue-previous_fuel/previous_revenue>0.02 then 'up' when fuel/revenue-previous_fuel/previous_revenue< -0.02 then 'down' else 'steady' end,
'repair_share',case when revenue<=0 or previous_revenue<=0 or repair is null or previous_repair is null then 'unknown' when repair/revenue-previous_repair/previous_revenue>0.02 then 'up' when repair/revenue-previous_repair/previous_revenue< -0.02 then 'down' else 'steady' end
)order by name),'[]'::jsonb)from current_metrics;
$body$;
revoke all on function private.hub_driver_vehicle_context_v1(uuid,uuid,date,date) from public,anon,authenticated;
