create or replace function public.hub_kpi_report_revision_v1(p_tenant_id uuid) returns text
language plpgsql stable security definer set search_path='' as $fn$
declare table_name text; signature text; revisions text:='';
begin
 if auth.uid() is null or not public.hub_has_permission(p_tenant_id,'kpi.read') then raise exception 'KPI access required' using errcode='42501';end if;
 foreach table_name in array array['kpi_import_rows','kpi_import_batches','kpi_personnel_salary_settings','kpi_settings','kpi_workify_article_rules','kpi_cost_category_rules','kpi_dashboard_allocations','kpi_units','kpi_unit_periods','kpi_unit_components','kpi_business_groups','kpi_project_classification_periods','kpi_project_business_groups','kpi_project_vehicle_periods','kpi_project_unit_mappings','kpi_asset_depreciation_periods','kpi_vehicle_distance_periods','hub_transpa_persons','hub_transpa_entities','hub_objects','hub_vehicle_meter_readings'] loop
  execute format('select md5(coalesce(string_agg(xmin::text||'':''||ctid::text,'','' order by ctid),'''')) from public.%I where tenant_id=$1',table_name) into signature using p_tenant_id;
  revisions:=revisions||table_name||':'||signature||';';
 end loop;
 select revisions||coalesce(string_agg(md5(pg_get_functiondef(p.oid)),'' order by p.oid),'') into revisions from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.proname like 'hub_kpi_%' and p.prokind='f';
 return md5(revisions);
end $fn$;
revoke all on function public.hub_kpi_report_revision_v1(uuid) from public,anon;
grant execute on function public.hub_kpi_report_revision_v1(uuid) to authenticated;
