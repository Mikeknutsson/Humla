-- Vehicle context from annotated TransPA time through canonical Vehicle identity.
-- This is vehicle/unit economy, never a driver's personal economic result.
create or replace function private.hub_driver_vehicle_context_v1(p_tenant uuid,p_person uuid,p_from date,p_to date)
returns jsonb language sql stable set search_path='' as $$
with own_time as materialized(
 select t.transpa_vehicle_ids from public.kpi_transpa_time_facts t where t.tenant_id=p_tenant and t.work_date between p_from and p_to and t.work_hours>0
 and (t.person_object_id=p_person or (t.person_object_id is null and exists(select 1 from public.hub_identity_keys k where k.tenant_id=p_tenant and k.object_id=p_person and k.identity_type='transpa_employee_id' and k.confidence=1 and k.identity_value=t.employee_id and not exists(select 1 from public.hub_identity_keys other where other.tenant_id=k.tenant_id and other.identity_type=k.identity_type and other.identity_value=k.identity_value and other.object_id<>p_person))))
),vehicle_keys as(
 select k.identity_value,(array_agg(distinct k.object_id))[1] vehicle_id from public.hub_identity_keys k where k.tenant_id=p_tenant and k.identity_type='transpa_vehicle_id' and k.confidence=1 group by k.identity_value having count(distinct k.object_id)=1
),vehicles as(select distinct k.vehicle_id from own_time t cross join lateral jsonb_array_elements_text(case when jsonb_typeof(t.transpa_vehicle_ids)='array' then t.transpa_vehicle_ids else '[]' end) id join vehicle_keys k on k.identity_value=id),
registrations as(select distinct v.vehicle_id,public.hub_normalize_vehicle_registration(k.identity_value) registration from vehicles v join public.hub_identity_keys k on k.object_id=v.vehicle_id and k.tenant_id=p_tenant and k.identity_type='registration_number' and k.confidence=1),
facts as materialized(select f.* from private.hub_kpi_prepared_display_facts f join private.hub_kpi_report_state s on s.tenant_id=f.tenant_id and s.active_generation=f.generation_id where f.tenant_id=p_tenant and f.cost_center='30' and f.occurred_on between p_from-(p_to-p_from+1) and p_to and not coalesce((f.original->>'_humla_excluded_from_kpi')::boolean,false)),
linked_units as(select distinct f.unit_id from facts f join registrations r on r.registration=public.hub_normalize_vehicle_registration(f.vehicle) where f.occurred_on>=p_from and f.unit_id is not null),
enriched as(select f.*,coalesce(t.margin_percent,g.margin_percent) goal from facts f join linked_units u using(unit_id) left join private.hub_transport_unit_targets_v2 t on t.tenant_id=f.tenant_id and t.unit_id=f.unit_id and t.valid_from<=f.occurred_on and (t.valid_to is null or t.valid_to>=f.occurred_on) left join private.hub_transport_group_targets_v1 g on g.tenant_id=f.tenant_id and g.business_group=f.business_group),
totals as(select unit_id,min(unit_name) name,
 sum(amount)filter(where kind='revenue' and occurred_on>=p_from) revenue,
 coalesce(sum(amount)filter(where kind='cost' and occurred_on>=p_from),0) cost,
 sum(amount)filter(where kind='revenue' and occurred_on<p_from) old_revenue,
 coalesce(sum(amount)filter(where kind='cost' and occurred_on<p_from),0) old_cost,
 sum(amount*goal/100)filter(where kind='revenue' and occurred_on>=p_from) target_result,
 count(*)filter(where kind='revenue' and occurred_on>=p_from and goal is null and amount<>0) missing_goals,
 sum(amount)filter(where kind='cost' and category='fuel' and occurred_on>=p_from) fuel,
 sum(amount)filter(where kind='cost' and category='fuel' and occurred_on<p_from) old_fuel,
 sum(amount)filter(where kind='cost' and category='service_repair' and occurred_on>=p_from) repair,
 sum(amount)filter(where kind='cost' and category='service_repair' and occurred_on<p_from) old_repair
 from enriched group by unit_id)
select coalesce(jsonb_agg(jsonb_build_object('name',name,
 'balance',case when revenue is null or revenue<=0 or missing_goals>0 or target_result is null then 'unknown' when revenue-cost>=target_result then 'on_target' when (revenue-cost-target_result)/revenue>=-0.05 then 'near_target' else 'below_target' end,
 'revenue_trend',case when revenue is null or old_revenue is null or old_revenue<=0 then 'unknown' when revenue/old_revenue>1.05 then 'up' when revenue/old_revenue<0.95 then 'down' else 'steady' end,
 'result_trend',case when revenue is null or old_revenue is null or revenue<=0 or old_revenue<=0 then 'unknown' when (revenue-cost)/revenue-(old_revenue-old_cost)/old_revenue>0.02 then 'up' when (revenue-cost)/revenue-(old_revenue-old_cost)/old_revenue< -0.02 then 'down' else 'steady' end,
 'fuel_share',case when revenue<=0 or old_revenue<=0 or fuel is null or old_fuel is null then 'unknown' when fuel/revenue-old_fuel/old_revenue>0.02 then 'up' when fuel/revenue-old_fuel/old_revenue< -0.02 then 'down' else 'steady' end,
 'repair_share',case when revenue<=0 or old_revenue<=0 or repair is null or old_repair is null then 'unknown' when repair/revenue-old_repair/old_revenue>0.02 then 'up' when repair/revenue-old_repair/old_revenue< -0.02 then 'down' else 'steady' end) order by name),'[]') from totals;
$$;
revoke all on function private.hub_driver_vehicle_context_v1(uuid,uuid,date,date) from public,anon,authenticated;
