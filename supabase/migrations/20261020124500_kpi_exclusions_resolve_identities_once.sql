-- Resolve the tenant's confirmed exclusion identities once, rather than per financial fact.
CREATE OR REPLACE FUNCTION private.hub_kpi_publish_project_exclusions_v1(p_tenant uuid, p_generation uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
 SET jit TO 'off'
AS $function$
declare n integer; excluded_units uuid[]; excluded_projects text[];
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage') then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant) then raise exception 'Generation tenant mismatch';end if;
 select coalesce(array_agg(distinct e.economic_unit_id) filter(where e.economic_unit_id is not null),'{}'::uuid[]),
 coalesce(array_agg(distinct k.identity_value) filter(where k.identity_value is not null),'{}'::text[])
 into excluded_units,excluded_projects
 from private.hub_kpi_project_exclusions e
 join public.hub_identity_keys k on k.tenant_id=e.tenant_id and k.object_id=e.project_id and k.identity_type='next_project_number' and k.confidence=1
 where e.tenant_id=p_tenant and e.enabled;
 with marked as materialized(
 select f.fact_id,coalesce(f.unit_id=any(excluded_units) or f.project=any(excluded_projects)
 or (f.source='Workify' and trim(f.original->>'Projektnr')=any(excluded_projects)),false) excluded
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
 ), changed as(
 update private.hub_kpi_prepared_facts f set
 display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_excluded_from_kpi',m.excluded),
 classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('excluded_from_kpi',m.excluded)
 from marked m where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=m.fact_id
 and coalesce((f.display_original->>'_humla_excluded_from_kpi')::boolean,false) is distinct from m.excluded
 returning f.fact_id,f.display_original
 ) update private.hub_kpi_prepared_display_facts d set original=c.display_original from changed c
 where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=c.fact_id;
 get diagnostics n=row_count;return n;
end
$function$;
