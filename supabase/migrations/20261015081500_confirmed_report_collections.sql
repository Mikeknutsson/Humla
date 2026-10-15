-- Report grouping is a confirmed, dated relationship between canonical Hub objects.
-- Source identities stay intact; this does not pretend that vehicles are one vehicle.
create or replace function private.hub_kpi_apply_report_collections_v1(p_tenant uuid,p_generation uuid)
returns integer language plpgsql set search_path='' set jit='off' as $$
declare n integer;
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
 )update private.hub_kpi_prepared_facts f set unit_id=t.target_unit_id,unit_name=t.target_name,
  classification_source=(coalesce(f.classification_source,'{}')-'unresolved_unit')||jsonb_build_object('collection_source_unit_id',t.source_unit_id,'collection_relation_id',t.relation_id,'remaining_unit_resolution','confirmed_report_collection'),
  display_original=(f.display_original-'_humla_unresolved_unit')||jsonb_build_object('_humla_unit_resolution','confirmed_report_collection','_humla_collection_source_unit_id',t.source_unit_id)
 from targets t join audit a using(fact_id)where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=t.fact_id;
 get diagnostics n=row_count;
 update private.hub_kpi_prepared_display_facts d set unit_id=f.unit_id,unit_name=f.unit_name,original=f.display_original
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation and f.classification_source->>'remaining_unit_resolution'='confirmed_report_collection'
  and d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=f.fact_id
  and(d.unit_id,d.unit_name,d.original)is distinct from(f.unit_id,f.unit_name,f.display_original);
 return n;
end $$;
revoke all on function private.hub_kpi_apply_report_collections_v1(uuid,uuid)from public,anon,authenticated;
-- Every generation uses the same grouping after normal allocation and resolution.
-- Do not re-resolve a confirmed grouping as though it were an unknown identity.
do $migration$
declare d text;needle text:='return jsonb_build_object(''resolved'',resolved,''newly_collected'',remaining,''fallback_unit'',fallback);';
begin
 d:=pg_get_functiondef('private.hub_resolve_remaining_units_v1(uuid,uuid)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected remaining-unit publication function';end if;
 d:=replace(d,'f.unit_id=fallback or','(f.unit_id=fallback and not(f.classification_source?''collection_source_unit_id'')) or');
 d:=replace(d,needle,'perform private.hub_kpi_apply_report_collections_v1(p_tenant,p_generation);'||chr(10)||needle);
 execute d;
end $migration$;
