-- Verified hardening applied to Humla Hub on 2026-09-28.
-- Future baseline must include the full pre-existing schema.

do $$ declare r record; begin
  for r in
    select p.oid::regprocedure sig,
           has_function_privilege('authenticated',p.oid,'EXECUTE') auth_ok
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'hub_%'
  loop
    if r.auth_ok then execute format('grant execute on function %s to authenticated',r.sig); end if;
    execute format('grant execute on function %s to service_role',r.sig);
    execute format('revoke execute on function %s from public, anon',r.sig);
  end loop;
end $$;

revoke all on table
 public.hub_document_extraction_runs,
 public.hub_document_parser_profiles,
 public.hub_flow_definitions,
 public.hub_project_reference_resolutions
from anon;

revoke execute on function
 public.hub_enable_flow_v1(uuid),
 public.hub_sync_flow_routes_v1(uuid),
 public.hub_validate_flow_v1(uuid),
 public.hub_detect_identity_conflicts_v1(uuid),
 public.hub_scan_fact_discrepancies_v1(uuid),
 public.hub_enforce_climate_integrity(),
 public.hub_enforce_global_identity_integrity(),
 public.hub_inherit_global_data_integrity(),
 public.hub_sync_fuel_climate_activity(),
 public.hub_protect_locked_core_policy(),
 public.hub_validate_connection_template()
from authenticated;
