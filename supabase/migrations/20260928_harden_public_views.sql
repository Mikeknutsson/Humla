-- Harden exposed views.
revoke all on table
 public.hub_admin_connector_switches,
 public.hub_climate_data_quality,
 public.hub_energy_context,
 public.hub_energy_objects,
 public.hub_energy_operations,
 public.hub_energy_readiness,
 public.hub_fleet_admin_catalog,
 public.hub_fleet_capability_matrix,
 public.hub_fleet_connector_catalog,
 public.hub_fuel_climate_v
from anon;

alter view public.hub_canonical_resolution_explain set (security_invoker=true);
alter view public.hub_canonical_value_candidates set (security_invoker=true);
alter view public.hub_current_canonical_facts set (security_invoker=true);
alter view public.hub_current_trust set (security_invoker=true);
alter view public.hub_partner_exchange_status set (security_invoker=true);
alter view public.hub_project_delivery_status set (security_invoker=true);
alter view public.hub_project_interop_health set (security_invoker=true);
