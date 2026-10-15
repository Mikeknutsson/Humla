-- Explicit report scope, approved by the user. Immutable source data remains intact.
create table private.hub_kpi_project_exclusions(
 tenant_id uuid not null,project_id uuid not null references public.hub_objects(id),
 economic_unit_id uuid not null references public.hub_objects(id),display_name text not null,
 reason text not null,enabled boolean not null default true,approved_by uuid not null,
 approved_at timestamptz not null default now(),primary key(tenant_id,project_id)
);
alter table private.hub_kpi_project_exclusions enable row level security;
revoke all on private.hub_kpi_project_exclusions from public,anon,authenticated;
create or replace function private.hub_kpi_publish_project_exclusions_v1(p_tenant uuid,p_generation uuid)
returns integer language plpgsql set search_path='' set jit='off' as $$
declare n integer;
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant,'kpi.manage')then raise exception 'KPI management required' using errcode='42501';end if;
 if not exists(select 1 from private.hub_kpi_report_generations where id=p_generation and tenant_id=p_tenant)then raise exception 'Generation tenant mismatch';end if;
 with marked as materialized(
  select f.fact_id,exists(select 1 from private.hub_kpi_project_exclusions e
   join public.hub_identity_keys k on k.tenant_id=e.tenant_id and k.object_id=e.project_id and k.identity_type='next_project_number' and k.confidence=1
   where e.tenant_id=p_tenant and e.enabled and (f.unit_id=e.economic_unit_id or f.project=k.identity_value
    or(f.source='Workify' and trim(f.original->>'Projektnr')=k.identity_value))) excluded
  from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
 )update private.hub_kpi_prepared_facts f set
  display_original=coalesce(f.display_original,'{}')||jsonb_build_object('_humla_excluded_from_kpi',m.excluded),
  classification_source=coalesce(f.classification_source,'{}')||jsonb_build_object('excluded_from_kpi',m.excluded)
 from marked m where f.tenant_id=p_tenant and f.generation_id=p_generation and f.fact_id=m.fact_id
 and coalesce((f.display_original->>'_humla_excluded_from_kpi')::boolean,false)is distinct from m.excluded;
 get diagnostics n=row_count;
 update private.hub_kpi_prepared_display_facts d set original=f.display_original
 from private.hub_kpi_prepared_facts f where f.tenant_id=p_tenant and f.generation_id=p_generation
 and d.tenant_id=p_tenant and d.generation_id=p_generation and d.fact_id=f.fact_id
 and d.original is distinct from f.display_original;
 return n;
end $$;
revoke all on function private.hub_kpi_publish_project_exclusions_v1(uuid,uuid)from public,anon,authenticated;
create view private.hub_kpi_report_facts_v1 with(security_invoker=true)as
 select * from private.hub_kpi_prepared_facts where not coalesce((display_original->>'_humla_excluded_from_kpi')::boolean,false);
create view private.hub_kpi_report_display_facts_v1 with(security_invoker=true)as
 select * from private.hub_kpi_prepared_display_facts where not coalesce((original->>'_humla_excluded_from_kpi')::boolean,false);
revoke all on private.hub_kpi_report_facts_v1,private.hub_kpi_report_display_facts_v1 from public,anon,authenticated;
-- Only KPI read projections change scope. Project source reports, reconciliation,
-- allocation engines, original imports and cumulative evidence retain full data.
do $migration$
declare p record;d text;needle text:='return jsonb_build_object(''resolved'',resolved,''newly_collected'',remaining,''fallback_unit'',fallback);';
begin
 for p in select proc.oid from pg_proc proc join pg_namespace n on n.oid=proc.pronamespace where n.nspname in('private','public') and proc.proname=any(array[
 'hub_kpi_prepared_snapshot_v1','hub_kpi_prepared_comparison_v1','hub_kpi_prepared_month_facts_v1','hub_kpi_prepared_range_facts_v1',
 'hub_kpi_month_facts_v1','hub_kpi_internal_overview_v1','hub_kpi_invoice_lead_time_v1','hub_kpi_internal_material_margin_v1',
 'hub_kpi_verified_unit_detail_v1','hub_kpi_billing_balance_v1','hub_overhead_period_v1','hub_kpi_unclassified_projects_v1'])
 loop
  d:=pg_get_functiondef(p.oid);
  d:=replace(d,'private.hub_kpi_prepared_display_facts','private.hub_kpi_report_display_facts_v1');
  d:=replace(d,'private.hub_kpi_prepared_facts','private.hub_kpi_report_facts_v1');
  execute d;
 end loop;
 d:=pg_get_functiondef('private.hub_resolve_remaining_units_v1(uuid,uuid)'::regprocedure);
 if strpos(d,needle)=0 then raise exception 'Unexpected unit resolution publisher';end if;
 d:=replace(d,'and m.value->>''object_id'' is not null','and m.value->>''object_id'' is not null and not exists(select 1 from private.hub_kpi_project_exclusions e where e.tenant_id=p_tenant and e.enabled and e.economic_unit_id=o.id)');
 d:=replace(d,needle,'perform private.hub_kpi_publish_project_exclusions_v1(p_tenant,p_generation);'||chr(10)||needle);
 execute d;
 d:=pg_get_functiondef('private.hub_kpi_mapped_units_projection_v1(uuid,jsonb)'::regprocedure);
 d:=replace(d,'return result;','result:=result||jsonb_build_object(''excluded_projects'',coalesce((select jsonb_agg(jsonb_build_object(''project_id'',project_id,''name'',display_name,''reason'',reason))from private.hub_kpi_project_exclusions where tenant_id=p_tenant and enabled),''[]''::jsonb));'||chr(10)||'return result;');
 execute d;
end $migration$;
