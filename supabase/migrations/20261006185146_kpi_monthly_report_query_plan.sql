-- Keep query planning scoped to this report; do not raise the API timeout.
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set jit='off';
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set work_mem='16MB';
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set enable_nestloop='off';
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set plan_cache_mode='force_custom_plan';
