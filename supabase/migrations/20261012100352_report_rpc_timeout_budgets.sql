-- PostgREST hoists the public RPC timeout before execution; private settings alone do not override the API default.
-- Keep global role limits unchanged, and preserve all existing authorization.
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb) set statement_timeout='45s';
alter function public.hub_fleet_comparison_v1(uuid,integer,integer[],uuid,text) set statement_timeout='30s';
alter function public.hub_asset_tco_v1(uuid,date,uuid) set statement_timeout='30s';
alter function public.hub_asset_market_review_v1(uuid,date,uuid) set statement_timeout='30s';
alter function public.hub_asset_register_projection_v1(uuid,date,uuid) set statement_timeout='30s';
notify pgrst,'reload schema';
