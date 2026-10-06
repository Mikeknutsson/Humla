do $patch$ declare d text;begin
 select pg_get_functiondef(oid) into d from pg_proc where proname='hub_kpi_transport_period_report_v1' and pronamespace='private'::regnamespace;
 d:=replace(d,'u||jsonb_build_object(''fuel'',','jsonb_build_object(''key'',u->''key'',''label'',u->''label'',''revenue'',u->''revenue'',''worked_hours'',u->''worked_hours'',''occupied_hours'',u->''occupied_hours'',''available_hours'',u->''available_hours'',''fuel'',');
 execute d;
 select pg_get_functiondef(oid) into d from pg_proc where proname='hub_kpi_monthly_transport_report_v1' and pronamespace='public'::regnamespace;
 d:=replace(d,'operations:=private.hub_kpi_prepared_snapshot_v1(p_tenant_id,p_fiscal_year,array[p_month],scope);','operations:=jsonb_build_object(''transpa_vehicle_time'',jsonb_build_object(''utilization'',month_report#>''{metrics,3,value}'',''reported_hours'',month_report#>''{time,reported_vehicle_hours}'',''available_hours'',month_report#>''{time,available_vehicle_hours}''));');
 execute d;
end $patch$;
