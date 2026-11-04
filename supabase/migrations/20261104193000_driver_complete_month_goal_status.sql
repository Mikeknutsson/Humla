-- Completeness must be established by source reconciliation, never by row presence.
-- Generation-scoped: re-imports invalidate earlier reconciliation automatically.
create table if not exists private.hub_driver_closed_months_v1 (
 tenant_id uuid not null references public.hub_tenants(id),
 unit_id uuid not null,
 generation_id uuid not null,
 month_start date not null check(month_start=date_trunc('month',month_start)::date),
 evidence jsonb not null check(jsonb_typeof(evidence)='object'
 and coalesce(length(evidence->>'revenue'),0)>0
 and coalesce(length(evidence->>'cost'),0)>0
 and coalesce(length(evidence->>'work_time'),0)>0
 and coalesce(length(evidence->>'personnel'),0)>0
 and coalesce(length(evidence->>'fuel'),0)>0
 and coalesce(length(evidence->>'overhead'),0)>0),
 reconciled_at timestamptz not null default now(),
 primary key(tenant_id,unit_id,generation_id,month_start)
);
revoke all on private.hub_driver_closed_months_v1 from public,anon,authenticated;

create or replace function private.hub_driver_month_complete_v1(p_tenant uuid,p_unit uuid,p_from date,p_to date)
returns boolean language sql stable set search_path='' as $$
 select coalesce(p_from=date_trunc('month',p_from)::date
 and p_to=(p_from+interval '1 month -1 day')::date
 and p_to<(now() at time zone 'Europe/Stockholm')::date
 and exists(select 1 from private.hub_driver_closed_months_v1 c
 join private.hub_kpi_report_state s on s.tenant_id=c.tenant_id and s.active_generation=c.generation_id
 where c.tenant_id=p_tenant and c.unit_id=p_unit and c.month_start=p_from),false);
$$;
revoke all on function private.hub_driver_month_complete_v1(uuid,uuid,date,date) from public,anon,authenticated;

create or replace function public.hub_driver_goal_periods_v1(p_tenant uuid,p_person uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit=off as $$
declare person uuid;member_role text;answer jsonb;
begin
 select role into member_role from public.hub_tenant_members where tenant_id=p_tenant and user_id=auth.uid() and status='active';
 if auth.uid() is null or member_role is null then raise exception 'Forbidden' using errcode='42501';end if;
 if p_person is not null then
  if member_role<>'owner' then raise exception 'Forbidden' using errcode='42501';end if;
  person:=p_person;
 else
  select person_object_id into person from private.hub_driver_account_links where tenant_id=p_tenant and user_id=auth.uid() and valid_from<=now() and valid_to is null;
 end if;
 if person is null then return '[]'::jsonb;end if;
 if not exists(select 1 from public.hub_objects where id=person and tenant_id=p_tenant and object_type='Person' and status='active') then raise exception 'Forbidden' using errcode='42501';end if;
 -- The existing helper is the canonical, self-scoped vehicle adapter.
 -- Evaluate only reconciled months (bounded to the latest 24 months).
 select coalesce(jsonb_agg(jsonb_build_object('from',m.first_day,'to',m.last_day) order by m.first_day desc),'[]'::jsonb)
 into answer from (
 select distinct c.month_start first_day,(c.month_start+interval '1 month -1 day')::date last_day
 from private.hub_driver_closed_months_v1 c
 join private.hub_kpi_report_state s on s.tenant_id=c.tenant_id and s.active_generation=c.generation_id
 where c.tenant_id=p_tenant and c.month_start>=date_trunc('month',now())::date-interval '24 months'
 and (c.month_start+interval '1 month -1 day')::date<(now() at time zone 'Europe/Stockholm')::date
 )m where jsonb_array_length(private.hub_driver_vehicle_context_v1(p_tenant,person,m.first_day,m.last_day))>0;
 return answer;
end $$;
revoke all on function public.hub_driver_goal_periods_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_driver_goal_periods_v1(uuid,uuid) to authenticated,service_role;

CREATE OR REPLACE FUNCTION private.hub_driver_vehicle_context_v1(p_tenant uuid, p_person uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
with own_time as materialized(
 select t.transpa_vehicle_ids from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant and t.work_date between p_from and p_to and t.work_hours>0
 and (t.person_object_id=p_person or (t.person_object_id is null and exists(select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=p_person and k.identity_type='transpa_employee_id' and k.confidence=1 and k.identity_value=t.employee_id and not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>p_person))))
),vehicle_keys as(
 select k.identity_value,(array_agg(distinct k.object_id))[1] vehicle_id from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='transpa_vehicle_id' and k.confidence=1 group by k.identity_value having count(distinct k.object_id)=1
),vehicles as(select distinct k.vehicle_id from own_time t cross join lateral jsonb_array_elements_text(case when jsonb_typeof(t.transpa_vehicle_ids)='array' then t.transpa_vehicle_ids else '[]' end) id join vehicle_keys k on k.identity_value=id),
registrations as(select distinct v.vehicle_id,public.hub_normalize_vehicle_registration(k.identity_value) registration from vehicles v join public.hub_identity_keys k on k.object_id=v.vehicle_id and k.tenant_id=p_tenant and k.identity_type='registration_number' and k.confidence=1),

periods as (
select 'current'::text key,p_from first_day,p_to last_day
union all select 'previous',(date_trunc('month',p_from)-interval '1 month')::date,p_from-1
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
select unit_id,period_key,min(unit_name)name,min(business_group)filter(where kind='revenue' and business_group<>'Ej klassificerat')business_group,
sum(amount)filter(where kind='revenue')revenue,coalesce(sum(amount)filter(where kind='cost'),0)cost,
sum(amount*goal/100)filter(where kind='revenue')target_result,
count(*)filter(where kind='revenue' and amount<>0 and goal is null)missing_goals,
sum(amount)filter(where kind='cost' and category='fuel')fuel,
sum(amount)filter(where kind='cost' and category='service_repair')repair,
sum(amount)filter(where kind='cost' and source='Piusi' and amount>0 and (original#>>'{_humla_fuel,quantity_liters}')::numeric>0)metered_fuel_cost,
sum((original#>>'{_humla_fuel,quantity_liters}')::numeric)filter(where kind='cost' and source='Piusi' and amount>0 and (original#>>'{_humla_fuel,quantity_liters}')::numeric>0)metered_liters
from enriched group by unit_id,period_key
),
metrics as(select *,case when revenue>0 and cost>0 and target_result>0 and missing_goals=0 and private.hub_driver_month_complete_v1(p_tenant,unit_id,p.first_day,p.last_day) then round((revenue-cost-target_result)/revenue*100,1) end deviation,
case when revenue>0 then (revenue-cost)/revenue*100 end margin from sums join periods p on p.key=sums.period_key),
current_metrics as(
select c.*,p.deviation previous_deviation,y.deviation year_deviation,p.margin previous_margin,p.revenue previous_revenue,p.cost previous_cost,
p.fuel previous_fuel,p.repair previous_repair,
case when c.deviation<0 and c.metered_fuel_cost>0 and c.metered_liters>=10 then
least(ceil((c.target_result-(c.revenue-c.cost))*c.metered_liters/c.metered_fuel_cost),floor(c.metered_liters*0.10))end fuel_example_liters
from metrics c left join metrics p on p.unit_id=c.unit_id and p.period_key='previous' and p.deviation is not null
left join metrics y on y.unit_id=c.unit_id and y.period_key='year' and y.deviation is not null where c.period_key='current'
)
select coalesce(jsonb_agg(jsonb_build_object(
'name',name,'goal_gap_pp',deviation,'previous_goal_gap_pp',previous_deviation,'year_goal_gap_pp',year_deviation,
'change_vs_previous_pp',case when deviation is not null and previous_deviation is not null then deviation-previous_deviation end,
'change_vs_year_pp',case when deviation is not null and year_deviation is not null then deviation-year_deviation end,
'year_from',(p_from-interval '1 year')::date,'year_to',(p_to-interval '1 year')::date,
'comparison_from',(date_trunc('month',p_from)-interval '1 month')::date,'comparison_to',p_from-1,
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
'balance',case when deviation is null then 'unknown' when deviation>=0 then 'on_target' else 'below_target' end,
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
)order by name),'[]'::jsonb)from current_metrics where deviation is not null;
$function$
