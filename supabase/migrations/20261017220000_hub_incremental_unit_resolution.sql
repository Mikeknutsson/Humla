-- Keep legacy mapping semantics; only materialize eligible facts and synchronize changed rows.
CREATE OR REPLACE FUNCTION private.hub_kpi_apply_report_collections_v1(p_tenant uuid, p_generation uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare n integer; synced integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where tenant_id=p_tenant and id=p_generation)then raise exception 'Generation tenant mismatch';end if;
 if exists(
  select f.fact_id from private.hub_kpi_prepared_facts f
  join public.hub_object_relations r on r.tenant_id=p_tenant and r.from_object_id=coalesce(nullif(f.classification_source->>'collection_source_unit_id','')::uuid,f.unit_id)
   and r.relation_type='reports_in' and r.status='active' and r.confidence=1
   and(r.valid_from is null or f.occurred_on>=(r.valid_from at time zone 'Europe/Stockholm')::date)
   and(r.valid_to is null or f.occurred_on<=(r.valid_to at time zone 'Europe/Stockholm')::date)
  where f.tenant_id=p_tenant and f.generation_id=p_generation group by f.fact_id having count(distinct r.to_object_id)>1
 )then raise exception 'Conflicting confirmed report collections';end if;
 with targets as materialized(
  select distinct on(f.fact_id) f.fact_id,f.unit_id,f.unit_name,f.classification_source,f.project,f.vehicle,f.cost_center,
   r.id relation_id,r.from_object_id source_unit_id,o.id target_unit_id,o.data->>'name' target_name
  from private.hub_kpi_prepared_facts f
  join public.hub_object_relations r on r.tenant_id=p_tenant and r.from_object_id=coalesce(nullif(f.classification_source->>'collection_source_unit_id','')::uuid,f.unit_id)
   and r.relation_type='reports_in' and r.status='active' and r.confidence=1
   and(r.valid_from is null or f.occurred_on>=(r.valid_from at time zone 'Europe/Stockholm')::date)
   and(r.valid_to is null or f.occurred_on<=(r.valid_to at time zone 'Europe/Stockholm')::date)
  join public.hub_objects o on o.tenant_id=p_tenant and o.id=r.to_object_id and o.object_type='EconomicUnit' and o.data->>'report_fallback'='unresolved'
  join public.hub_objects src on src.tenant_id=p_tenant and src.id=r.from_object_id and src.object_type='EconomicUnit'
  where f.tenant_id=p_tenant and f.generation_id=p_generation and f.unit_id is distinct from o.id
  order by f.fact_id,r.valid_from desc nulls last,r.id
 ),audit as(
  insert into private.hub_remaining_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select p_tenant,p_generation,fact_id,jsonb_build_object('unit_id',unit_id,'unit_name',unit_name,'project',project,'vehicle',vehicle,'cost_center',cost_center),
   jsonb_build_object('unit_id',target_unit_id,'source_unit_id',source_unit_id,'relation_id',relation_id,'reason','confirmed_report_collection'),auth.uid()from targets
  on conflict(generation_id,fact_id)do update set after_record=excluded.after_record returning fact_id
 ),changed as(update private.hub_kpi_prepared_facts f set unit_id=t.target_unit_id,unit_name=t.target_name,
  classification_source=(coalesce(f.classification_source,'{}')-'unresolved_unit')||jsonb_build_object('collection_source_unit_id',t.source_unit_id,'collection_relation_id',t.relation_id,'remaining_unit_resolution','confirmed_report_collection'),
  display_original=(f.display_original-'_humla_unresolved_unit')||jsonb_build_object('_humla_unit_resolution','confirmed_report_collection','_humla_collection_source_unit_id',t.source_unit_id)
 from targets t join audit a using(fact_id)where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id
 returning f.*
 ),display_sync as(
 update private.hub_kpi_prepared_display_facts d set unit_id=f.unit_id,unit_name=f.unit_name,original=f.display_original
 from changed f where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=f.fact_id returning d.fact_id
 )select(select count(*)from changed),(select count(*)from display_sync)into n,synced;
 if n<>synced then raise exception 'Report collection display sync mismatch';end if;
 return n;
end $function$;
CREATE OR REPLACE FUNCTION private.hub_resolve_remaining_units_v1(p_tenant uuid, p_generation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
 SET plan_cache_mode TO 'force_custom_plan'
 SET jit TO 'off'
AS $function$
declare fallback uuid; resolved integer; remaining integer;before_count bigint;before_amount numeric; synced integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 select id into fallback from public.hub_objects where tenant_id=p_tenant and object_type='EconomicUnit' and data->>'report_fallback'='unresolved';
 if fallback is null then return jsonb_build_object('resolved',0,'remaining',0);end if;
 select count(*),sum(amount)into before_count,before_amount from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation;
 with eligible as materialized(
  select f.fact_id,f.project,f.vehicle,f.cost_center,f.cost_center_name,f.business_group,f.unit_id,f.unit_name,f.occurred_on,
   coalesce(f.project,case when f.source='Workify' then nullif(trim(f.original->>'Projektnr'),'')
    when f.source='Avskrivningsregister' then substring(f.vehicle from '^(?:AO[[:space:]]*)?([0-9]+)[[:space:]]')end) target_project
  from private.hub_kpi_prepared_facts f
  where f.tenant_id=p_tenant and f.generation_id=p_generation and
   (f.unit_id is null or(f.unit_id=fallback and not(f.classification_source?'collection_source_unit_id'))
    or not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant and o.id=f.unit_id and o.object_type='EconomicUnit'))
 ), members as materialized(
  select o.id,p.value->>'name' name,p.value->>'valid_from' vf,p.value->>'valid_to' vt,
   p.value->>'business_group_id' group_id,m.value->>'kind' kind,m.value->>'source_reference' ref
  from public.hub_objects o cross join lateral jsonb_array_elements(o.data->'periods')p
  cross join lateral jsonb_array_elements(p.value->'members')m
  where o.tenant_id=p_tenant and o.object_type='EconomicUnit'and coalesce((p.value->>'enabled')::boolean,false)
   and m.value->>'resolution'='confirmed'and m.value->>'object_id' is not null
   and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled and e.economic_unit_id=o.id)
 ), candidates as materialized(
  select f.fact_id,f.project,f.vehicle,f.cost_center,f.cost_center_name,f.business_group,f.unit_id,f.unit_name,
   m.id target_id,m.name target_name,m.group_id,f.target_project
  from eligible f join members m on m.kind='project'and m.ref=f.target_project
   and f.occurred_on>=m.vf::date and(m.vt is null or f.occurred_on<=m.vt::date)
  union all
  select f.fact_id,f.project,f.vehicle,f.cost_center,f.cost_center_name,f.business_group,f.unit_id,f.unit_name,
   m.id,m.name,m.group_id,f.target_project
  from eligible f join members m on m.kind='vehicle'and m.ref=f.vehicle
   and f.occurred_on>=m.vf::date and(m.vt is null or f.occurred_on<=m.vt::date)
 ), unique_targets as(
  select fact_id,min(target_id::text)::uuid target_id from candidates group by fact_id having count(distinct target_id)=1
 ), targets as materialized(
  select distinct on(c.fact_id)c.*,coalesce(case when c.cost_center is null or c.cost_center='unclassified' then pc.cost_center end,c.cost_center) target_cost_center,
   coalesce(case when c.cost_center is null or c.cost_center='unclassified' then pc.cost_center_name end,c.cost_center_name) target_cost_center_name,
   coalesce(g.name,c.business_group) target_group
  from candidates c join unique_targets u on u.fact_id=c.fact_id and u.target_id=c.target_id
  join private.hub_kpi_prepared_facts f on f.generation_id=p_generation and f.tenant_id=p_tenant and f.fact_id=c.fact_id
  left join public.kpi_project_classification_periods pc on pc.tenant_id=p_tenant and pc.project_reference=c.target_project
   and f.occurred_on>=pc.valid_from and(pc.valid_to is null or f.occurred_on<=pc.valid_to)
  left join public.kpi_business_groups g on g.tenant_id=p_tenant and g.id::text=c.group_id
  where (c.unit_id,c.project) is distinct from(c.target_id,c.target_project)
  order by c.fact_id,pc.valid_from desc nulls last
 ), audit as(
  insert into private.hub_remaining_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select p_tenant,p_generation,t.fact_id,jsonb_build_object('unit_id',t.unit_id,'project',t.project,'vehicle',t.vehicle,'cost_center',t.cost_center,'business_group',t.business_group),
   jsonb_build_object('unit_id',t.target_id,'project',t.target_project,'cost_center',t.target_cost_center,'reason','confirmed_dated_membership'),auth.uid() from targets t
  on conflict(generation_id,fact_id)do update set after_record=excluded.after_record returning fact_id
 ),changed as(update private.hub_kpi_prepared_facts f set unit_id=t.target_id,unit_name=t.target_name,project=t.target_project,
  cost_center=t.target_cost_center,cost_center_name=t.target_cost_center_name,business_group=t.target_group,
  classification_source=(coalesce(f.classification_source,'{}')-'unresolved_unit')||jsonb_build_object('remaining_unit_resolution','confirmed_dated_membership'),
  display_original=(f.display_original-'_humla_unresolved_unit')||jsonb_build_object('_humla_unit_resolution','confirmed_dated_membership')
 from targets t join audit a on a.fact_id=t.fact_id where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id
 returning f.*
 ),display_sync as(
 update private.hub_kpi_prepared_display_facts d set unit_id=f.unit_id,unit_name=f.unit_name,project=f.project,vehicle=f.vehicle,
 cost_center=f.cost_center,business_group=f.business_group,original=f.display_original
 from changed f where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=f.fact_id returning d.fact_id
 )select(select count(*)from changed),(select count(*)from display_sync)into resolved,synced;
 if resolved<>synced then raise exception 'Unit routing display sync mismatch';end if;
 with targets as materialized(
  select f.fact_id,f.unit_id,f.project,f.vehicle,f.cost_center,f.business_group,
   case when f.project is null and f.vehicle is null then 'missing_reference' else 'no_unique_dated_unit' end reason
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.unit_id is distinct from fallback
   and not exists(select 1 from public.hub_objects o where o.tenant_id=p_tenant and o.id=f.unit_id and o.object_type='EconomicUnit')
 ),audit as(
  insert into private.hub_remaining_unit_routing_audit(tenant_id,generation_id,fact_id,before_record,after_record,actor)
  select p_tenant,p_generation,t.fact_id,jsonb_build_object('unit_id',t.unit_id,'project',t.project,'vehicle',t.vehicle,'cost_center',t.cost_center,'business_group',t.business_group),
   jsonb_build_object('unit_id',fallback,'reason',t.reason),auth.uid()from targets t
  on conflict(generation_id,fact_id)do update set after_record=excluded.after_record returning fact_id
 ),changed as(update private.hub_kpi_prepared_facts f set unit_id=fallback,unit_name='Övrigt',
  classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('remaining_unit_resolution',t.reason,'unresolved_unit',true),
  display_original=f.display_original||jsonb_build_object('_humla_unit_resolution',t.reason,'_humla_unresolved_unit',true)
 from targets t join audit a on a.fact_id=t.fact_id where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id
 returning f.*
 ),display_sync as(
 update private.hub_kpi_prepared_display_facts d set unit_id=f.unit_id,unit_name=f.unit_name,project=f.project,vehicle=f.vehicle,
 cost_center=f.cost_center,business_group=f.business_group,original=f.display_original
 from changed f where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=f.fact_id returning d.fact_id
 )select(select count(*)from changed),(select count(*)from display_sync)into remaining,synced;
 if remaining<>synced then raise exception 'Unit routing display sync mismatch';end if;
 if row(before_count,before_amount)is distinct from(select row(count(*),sum(amount))from private.hub_kpi_prepared_facts where tenant_id=p_tenant and generation_id=p_generation)then raise exception 'Unit resolution changed financial totals';end if;
 perform private.hub_kpi_apply_report_collections_v1(p_tenant,p_generation);
perform private.hub_kpi_publish_project_exclusions_v1(p_tenant,p_generation);
return jsonb_build_object('resolved',resolved,'newly_collected',remaining,'fallback_unit',fallback);
end $function$;
