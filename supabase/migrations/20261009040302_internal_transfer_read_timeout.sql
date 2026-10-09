-- PostgREST hoists RPC-level timeout settings before executing the call.
-- Keep the authenticated role's normal 8s limit; extend only these read RPCs.
alter function public.hub_kpi_internal_transfers_v1(uuid,date,date,integer[]) set statement_timeout='45s';
alter function public.hub_kpi_internal_transfers_with_purchase_v1(uuid,date,date,integer[]) set statement_timeout='45s';
notify pgrst,'reload schema';
