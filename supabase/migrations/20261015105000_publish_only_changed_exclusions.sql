-- Synchronize only changed exclusion evidence, avoiding all-row JSON comparisons.
create or replace function private.hub_kpi_publish_project_exclusions_v1(p_tenant uuid,p_generation uuid)
returns integer language plpgsql set search_path='' set jit='off' as $$
declare n integer;
begin
 if auth.uid()is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required'using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 with marked as materialized(
 select f.fact_id,exists(select 1 from private.hub_kpi_project_exclusions e
 join public.hub_identity_keys k on k.tenant_id=e.tenant_id and k.object_id=e.project_id and k.identity_type='next_project_number'and k.confidence=1
 where e.tenant_id=p_tenant and e.enabled and(f.unit_id=e.economic_unit_id or f.project=k.identity_value
 or(f.source='Workify'and trim(f.original->>'Projektnr')=k.identity_value)))excluded
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
 ), changed as(
 update private.hub_kpi_prepared_facts f set
 display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_excluded_from_kpi',m.excluded),
 classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('excluded_from_kpi',m.excluded)
 from marked m where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=m.fact_id
 and coalesce((f.display_original->>'_humla_excluded_from_kpi')::boolean,false)is distinct from m.excluded
 returning f.fact_id,f.display_original
 )update private.hub_kpi_prepared_display_facts d set original=c.display_original from changed c
 where d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=c.fact_id;
 get diagnostics n=row_count;return n;
end$$;
revoke all on function private.hub_kpi_publish_project_exclusions_v1(uuid,uuid)from public,anon,authenticated;
