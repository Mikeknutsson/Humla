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
 unit_revenue as materialized(
 select public.hub_resolve_canonical_object_v1(p_tenant,r.unit_id) unit_id,r.cost_center,date_trunc('month',r.occurred_on)::date month_start,sum(r.amount) amount
 from private.hub_kpi_prepared_facts r where r.tenant_id=p_tenant and r.generation_id=p_generation and r.kind='revenue'
 and r.unit_id is not null and not coalesce((r.original->>'_humla_excluded_from_kpi')::boolean,false)
 group by 1,2,3 having sum(r.amount)>0),
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
 and (f.allocation_method<>'equal' or exists(select 1 from unit_revenue rev
 where rev.unit_id=public.hub_resolve_canonical_object_v1(p_tenant,p.id)
 and rev.cost_center=f.cost_center and rev.month_start=date_trunc('month',f.occurred_on)::date))
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
