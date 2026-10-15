-- The public RPC prepares and caches two fiscal-period aggregates. Its private
-- implementation already allows 45 s, but PostgREST applied the role's 8 s limit
-- before entering it. Bound only this report to 25 s, below the UI's 35 s limit.
alter function public.hub_kpi_monthly_transport_report_v1(uuid,integer,integer,text,jsonb)set statement_timeout='25s';
notify pgrst,'reload schema';
