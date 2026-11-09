alter function private.hub_economic_transactions_v2(uuid,date,date) set plan_cache_mode='force_custom_plan';
alter function public.hub_kpi_economic_reconciliation_v3(uuid,date,date,jsonb,integer) set plan_cache_mode='force_custom_plan';
alter function public.hub_vehicle_allocation_candidates_v2(uuid,date,date,integer) set plan_cache_mode='force_custom_plan';
notify pgrst,'reload schema';
