-- Imported data availability is distinct from an audited/closed accounting period.
create or replace function private.hub_driver_source_cutoff_v1(p_tenant uuid)
returns date language sql stable set search_path='' set jit=off as $$
 with dates as (
 select f.source,max(f.occurred_on) last_day
 from private.hub_kpi_prepared_display_facts f
 join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 where f.tenant_id=p_tenant and f.cost_center='30'
 and f.occurred_on<(now() at time zone 'Europe/Stockholm')::date
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 and ((f.source='Workify' and f.kind='revenue') or(f.source in('NEXT','TransPA','Piusi') and f.kind='cost'))
 group by f.source
 )select case when count(*)=4 then min(last_day) end from dates;
$$;
revoke all on function private.hub_driver_source_cutoff_v1(uuid) from public,anon,authenticated;

create or replace function private.hub_driver_window_available_v1(p_tenant uuid,p_unit uuid,p_from date,p_to date)
returns boolean language sql stable set search_path='' set jit=off as $$
 with facts as materialized (
 select f.kind,f.category,f.source,f.vehicle from private.hub_kpi_prepared_display_facts f
 join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id
 where f.tenant_id=p_tenant and f.unit_id=p_unit and f.cost_center='30' and f.occurred_on between p_from and p_to
 and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)
 ), vehicles as (
 select distinct k.object_id from facts f join public.hub_identity_keys k on k.tenant_id=p_tenant
 and k.identity_type='registration_number' and k.confidence=1
 and public.hub_normalize_vehicle_registration(k.identity_value)=public.hub_normalize_vehicle_registration(f.vehicle)
 where not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type
 and public.hub_normalize_vehicle_registration(other.identity_value)=public.hub_normalize_vehicle_registration(k.identity_value) and other.object_id<>k.object_id)
 ), time_keys as (
 select k.identity_value from vehicles v join public.hub_identity_keys k on k.tenant_id=p_tenant and k.object_id=v.object_id
 and k.identity_type='transpa_vehicle_id' and k.confidence=1
 where not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>k.object_id)
 )
 select coalesce(p_from<=p_to and p_to<=private.hub_driver_source_cutoff_v1(p_tenant)
 and bool_or(kind='revenue') and bool_or(kind='cost')
 and bool_or(kind='cost' and category='personnel') and bool_or(kind='cost' and category='fuel')
 and bool_or(kind='cost' and source='Overhead')
 and exists(select 1 from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant and t.work_date between p_from and p_to and t.work_hours>0
 and exists(select 1 from time_keys k where t.transpa_vehicle_ids ? k.identity_value)),false) from facts;
$$;
revoke all on function private.hub_driver_window_available_v1(uuid,uuid,date,date) from public,anon,authenticated;
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
metrics as(select *,case when revenue>0 and cost>0 and target_result>0 and missing_goals=0 and private.hub_driver_window_available_v1(p_tenant,unit_id,p.first_day,p.last_day) then round((revenue-cost-target_result)/revenue*100,1) end deviation,
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
'name',name,'coverage_status',case when deviation is not null then 'registered' else 'missing_components' end,'goal_gap_pp',deviation,'previous_goal_gap_pp',previous_deviation,'year_goal_gap_pp',year_deviation,
'change_vs_previous_pp',case when deviation is not null and previous_deviation is not null then deviation-previous_deviation end,
'change_vs_year_pp',case when deviation is not null and year_deviation is not null then deviation-year_deviation end,
'year_from',(p_from-interval '1 year')::date,'year_to',(p_to-interval '1 year')::date,
'comparison_from',p_from-(p_to-p_from+1),'comparison_to',p_from-1,
'margin_pct',case when deviation is not null then round(margin,1) end,'target_pct',case when revenue>0 and missing_goals=0 then round(target_result/revenue*100,1) end,
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
)order by name),'[]'::jsonb)from current_metrics;
$function$;

create or replace function public.hub_driver_goal_periods_v1(p_tenant uuid,p_person uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' set jit=off as $$
declare person uuid;member_role text;answer jsonb;last_work date;cutoff date;
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
 cutoff:=private.hub_driver_source_cutoff_v1(p_tenant);
 select max(t.work_date) into last_work from public.kpi_transpa_time_facts t
 where t.tenant_id=p_tenant and t.work_hours>0 and t.work_date<=coalesce(cutoff,(now() at time zone 'Europe/Stockholm')::date-1)
 and(t.person_object_id=person or(t.person_object_id is null and exists(
 select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=person and k.identity_type='transpa_employee_id'
 and k.confidence=1 and k.identity_value=t.employee_id and not exists(select 1 from public.hub_identity_keys other
 where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>person))));
 if last_work is null then return '[]'::jsonb;end if;
 with candidates as (
 select 1 ord,'four-weeks'::text mode,last_work-27 first_day,last_work last_day
 union all select 2,'month',date_trunc('month',last_work)::date,last_work
 union all select 3,'week',last_work-6,last_work
 ), checks as materialized (
 select c.*,exists(select 1 from jsonb_array_elements(private.hub_driver_vehicle_context_v1(p_tenant,person,c.first_day,c.last_day)) v
 where v->>'coverage_status'='registered') has_economy from candidates c
 )
 select coalesce(jsonb_agg(jsonb_build_object('from',first_day,'to',last_day,'mode',mode,'has_economy',has_economy) order by ord),'[]'::jsonb)
 into answer from checks where has_economy or(ord=1 and not exists(select 1 from checks where has_economy));
 return answer;
end $$;
revoke all on function public.hub_driver_goal_periods_v1(uuid,uuid) from public,anon;
grant execute on function public.hub_driver_goal_periods_v1(uuid,uuid) to authenticated,service_role;

